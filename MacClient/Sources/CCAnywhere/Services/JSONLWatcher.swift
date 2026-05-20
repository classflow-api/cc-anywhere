// JSONLWatcher.swift
// Watches ~/.claude/projects/<encoded>/ for *.jsonl line appends and pushes
// parsed messages out (throttled 100ms, uuid-dedup).
//
// See 需求规格说明书 §3.1 M4 + 技术实施文档 §4.3.
// FSEvents is used because polling is forbidden by R-M4-05.

import Foundation
import CoreServices.FSEvents

/// Public observer interface; we keep this side-effect free for testing.
public protocol JSONLWatcherDelegate: AnyObject {
    func watcher(_ watcher: JSONLWatcher, didReceive batch: [ParsedMessage], for tabId: UUID)
}

/// 子 agent 元数据（R-F2-002 / R-F2-003 / R-F5-001 / R-F5-004）。
///
/// 由 JSONLWatcher 的两阶段匹配（父 Task tool_use ↔ agent-*.jsonl 首条 user message）
/// 写入；HookIpcServer / MsgStreamBridge 反查使用。
///
/// 为什么按 promptHash 关联：JSONL 实测（见 JSONL实测结果.md 实测 1-3）显示
/// agent-X.jsonl 内部 record 既无 `parentToolUseId` 字段，agentId 也与父 Task
/// tool_use_id 无可见映射。唯一可靠的桥梁是"agent 首条 user message 的内容 ==
/// 父 Task tool_use 的 input.prompt"，所以走 prompt 前缀的 SHA1 哈希匹配。
public struct SubAgentMeta: SubAgentMetaProtocol, Sendable {
    /// 父 session 中 Task tool_use 的 id；两阶段匹配成功才填，未匹配为 nil。
    public let parentToolUseId: String?
    /// agent-X.jsonl 文件名后缀的 7 字符 hex hash，sidechain 内唯一。
    public let agentId: String
    /// 子 agent 独立 sessionId（来自 agent-X.jsonl 内 record.sessionId）；
    /// HookIpcServer 按 hook stdin 的 session_id 反查时用。
    public let agentSessionId: String
    /// 父 Task input.prompt 截断到 60 字符（R-F5-002），用作 tool_approval chip。
    public let promptSummary: String
    public let createdAt: Date
}

public final class JSONLWatcher {
    private let log = AppLogger.shared.tagged("JSONLWatcher")
    public weak var delegate: JSONLWatcherDelegate?

    /// Throttle window per Tab (R-M4-02).
    public var throttleInterval: TimeInterval = 0.1

    private let queue = DispatchQueue(label: "cc-anywhere.jsonl-watcher", qos: .userInitiated)
    private var streams: [UUID: WatchStream] = [:]

    /// hook 已实时推送过的 tool_use_id，跳过 JSONL 中的对应记录避免双推。
    /// TTL 10 分钟。R-F5-001/002/003
    private var hookPushedToolUseIds: [String: Date] = [:]
    private let hookPushedTTL: TimeInterval = 600

    /// 子 agent 索引：tabId → agentId → meta（R-F2-002）。
    /// 唯一访问线程 = `queue`（同 hookPushedToolUseIds 模式），外部读走
    /// `queue.sync`；内部 WatchStream 也跑在该 queue 上直接读写。
    private var activeSubAgents: [UUID: [String: SubAgentMeta]] = [:]

    /// 两阶段匹配 buffer：父 Task tool_use 先到，等子 agent。
    /// key = promptHash (sha1 前 200 字符)
    private var pendingTaskMatches: [UUID: [String: PendingTaskMatch]] = [:]
    /// 子 agent 首条 user message 先到，等父 Task tool_use。
    private var pendingAgentMatches: [UUID: [String: PendingAgentMatch]] = [:]

    /// 30 秒后清理孤儿（R-F2-003：超时后子消息仍可展示，但无 parentToolUseId 关联）。
    private let pendingMatchTTL: TimeInterval = 30

    fileprivate struct PendingTaskMatch {
        let toolUseId: String
        let prompt: String
        let ts: Date
    }
    fileprivate struct PendingAgentMatch {
        let agentId: String
        let agentSessionId: String
        let firstContent: String
        let ts: Date
    }

    public init() {}

    public func watch(tab: Tab) {
        unwatch(tabId: tab.id)
        let dir = Self.claudeProjectsDir(for: tab.folder)
        let stream = WatchStream(
            tabId: tab.id,
            directory: dir,
            throttleInterval: throttleInterval,
            queue: queue,
            log: log,
            hookPushedCheck: { [weak self] toolUseId in
                guard let self = self else { return false }
                // queue.sync 安全读：本闭包总是在 watcher.queue 上被 WatchStream 调用，
                // 直接读取即可（同 queue 不会自我死锁）。
                return self.isHookPushed(toolUseId: toolUseId)
            },
            onTaskToolUse: { [weak self] toolUseId, prompt, tabId in
                self?.onTaskToolUse(tabId: tabId, toolUseId: toolUseId, prompt: prompt)
            },
            onAgentFirstMessage: { [weak self] agentId, sessionId, firstContent, tabId in
                self?.onAgentFirstMessage(
                    tabId: tabId,
                    agentId: agentId,
                    agentSessionId: sessionId,
                    firstContent: firstContent
                )
            },
            onBatch: { [weak self] (id, batch) in
                guard let self = self else { return }
                self.delegate?.watcher(self, didReceive: batch, for: id)
            }
        )
        stream.start()
        streams[tab.id] = stream
        log.info("watching \(dir.path) for tab=\(tab.id)")
    }

    /// 同 queue 调用（来自 WatchStream），直接判定并顺带清理过期项。
    fileprivate func isHookPushed(toolUseId: String) -> Bool {
        let now = Date()
        if let ts = hookPushedToolUseIds[toolUseId] {
            if now.timeIntervalSince(ts) < hookPushedTTL {
                return true
            } else {
                hookPushedToolUseIds.removeValue(forKey: toolUseId)
            }
        }
        return false
    }

    // MARK: - 两阶段匹配（R-F2-002 / R-F2-003）
    //
    // 决策依据：JSONL实测结果.md 决策 A —— agent-X.jsonl record 无原生
    // parentToolUseId 字段，唯一可靠关联线索是"agent 首条 user message 的
    // 内容 == 父 Task tool_use 的 input.prompt"。
    //
    // 两阶段：先到的一方放入对应 pendingBuffer，另一方到达时按 promptHash 命中
    // 即建立映射。30s 超时清理 → 孤儿 agentId（仍可作为独立块展示）。

    /// 父 session.jsonl 解析到 Task tool_use 时调用。**queue 内部调用**。
    fileprivate func onTaskToolUse(tabId: UUID, toolUseId: String, prompt: String) {
        let hash = Self.promptHash(prompt)
        gcPendingMatches(now: Date())
        if let agent = pendingAgentMatches[tabId]?.removeValue(forKey: hash) {
            // 子先到，命中
            registerMatch(
                tabId: tabId,
                toolUseId: toolUseId,
                agentId: agent.agentId,
                agentSessionId: agent.agentSessionId,
                prompt: prompt
            )
        } else {
            pendingTaskMatches[tabId, default: [:]][hash] = PendingTaskMatch(
                toolUseId: toolUseId,
                prompt: prompt,
                ts: Date()
            )
            log.debug("subagent pending task tab=\(tabId) toolUseId=\(toolUseId) (waiting agent-*.jsonl)")
        }
    }

    /// agent-*.jsonl 解析到首条（parentUuid == null）user message 时调用。
    /// **queue 内部调用**。
    fileprivate func onAgentFirstMessage(tabId: UUID,
                                         agentId: String,
                                         agentSessionId: String,
                                         firstContent: String) {
        let hash = Self.promptHash(firstContent)
        gcPendingMatches(now: Date())
        if let task = pendingTaskMatches[tabId]?.removeValue(forKey: hash) {
            // 父先到，命中
            registerMatch(
                tabId: tabId,
                toolUseId: task.toolUseId,
                agentId: agentId,
                agentSessionId: agentSessionId,
                prompt: task.prompt
            )
        } else {
            pendingAgentMatches[tabId, default: [:]][hash] = PendingAgentMatch(
                agentId: agentId,
                agentSessionId: agentSessionId,
                firstContent: firstContent,
                ts: Date()
            )
            // 即便父未到，也先以 parentToolUseId=nil 占位写入索引；HookIpcServer
            // 仍能按 agentSessionId 反查到 promptSummary（chip 不带链接）。
            // 关键契约（第一轮 review 阻塞 #3）：如果 activeSubAgents[tabId][agentId]
            // 已经存在且 parentToolUseId 非空（registerMatch 已写入正式映射），
            // 重复触发 onAgentFirstMessage（理论上 watch 单次防护下不发生，但留
            // 防御性兜底）**不得**用 nil 占位覆盖正式 meta。
            let existing = activeSubAgents[tabId]?[agentId]
            if existing?.parentToolUseId == nil {
                let placeholder = SubAgentMeta(
                    parentToolUseId: nil,
                    agentId: agentId,
                    agentSessionId: agentSessionId,
                    promptSummary: Self.truncatePromptSummary(firstContent),
                    createdAt: Date()
                )
                activeSubAgents[tabId, default: [:]][agentId] = placeholder
                log.debug("subagent pending agent tab=\(tabId) agentId=\(agentId) (placeholder, waiting Task tool_use)")
            }
        }
    }

    /// 命中后写入正式映射（覆盖可能的占位）。
    private func registerMatch(tabId: UUID,
                               toolUseId: String,
                               agentId: String,
                               agentSessionId: String,
                               prompt: String) {
        let meta = SubAgentMeta(
            parentToolUseId: toolUseId,
            agentId: agentId,
            agentSessionId: agentSessionId,
            promptSummary: Self.truncatePromptSummary(prompt),
            createdAt: Date()
        )
        activeSubAgents[tabId, default: [:]][agentId] = meta
        log.info("subagent matched tab=\(tabId) agentId=\(agentId) -> parentToolUseId=\(toolUseId)")
    }

    /// 30s 超时清理（懒清理，每次匹配触发顺带 GC）。
    private func gcPendingMatches(now: Date) {
        let ttl = pendingMatchTTL
        var droppedTasks = 0
        var droppedAgents = 0
        for tabId in pendingTaskMatches.keys {
            let before = pendingTaskMatches[tabId]?.count ?? 0
            pendingTaskMatches[tabId] = pendingTaskMatches[tabId]?.filter {
                now.timeIntervalSince($0.value.ts) < ttl
            }
            droppedTasks += before - (pendingTaskMatches[tabId]?.count ?? 0)
        }
        for tabId in pendingAgentMatches.keys {
            let before = pendingAgentMatches[tabId]?.count ?? 0
            pendingAgentMatches[tabId] = pendingAgentMatches[tabId]?.filter {
                now.timeIntervalSince($0.value.ts) < ttl
            }
            droppedAgents += before - (pendingAgentMatches[tabId]?.count ?? 0)
        }
        if droppedTasks > 0 || droppedAgents > 0 {
            log.info("subagent gc: dropped tasks=\(droppedTasks) agents=\(droppedAgents) (ttl=\(ttl)s)")
        }
    }

    /// 计算 prompt 的匹配哈希。截前 200 字符避免超长 prompt 性能问题，
    /// 同时保留足够熵避免冲突（200 字符的 SHA1 冲突概率可忽略）。
    private static func promptHash(_ s: String) -> String {
        let prefix = String(s.prefix(200))
        return sha1Hex(prefix)
    }

    private static func sha1Hex(_ s: String) -> String {
        // CommonCrypto SHA1 - 项目无加密强度需求（仅匹配 key）但 Foundation
        // 没有内置 hash；用 hashValue 不稳定（跨进程 / 跨版本可能变化）。
        // 自实现一个最小 SHA1 避免引入 CommonCrypto bridging header 改动。
        var h: [UInt32] = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0]
        var data = Array(s.utf8)
        let originalLen = UInt64(data.count) * 8
        data.append(0x80)
        while data.count % 64 != 56 { data.append(0) }
        for i in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8((originalLen >> i) & 0xff))
        }
        for chunkStart in stride(from: 0, to: data.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 80)
            for i in 0..<16 {
                let base = chunkStart + i * 4
                w[i] = (UInt32(data[base]) << 24) |
                       (UInt32(data[base+1]) << 16) |
                       (UInt32(data[base+2]) << 8) |
                       UInt32(data[base+3])
            }
            for i in 16..<80 {
                let v = w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16]
                w[i] = (v << 1) | (v >> 31)
            }
            var (a, b, c, d, e) = (h[0], h[1], h[2], h[3], h[4])
            for i in 0..<80 {
                let f: UInt32, k: UInt32
                switch i {
                case 0..<20: f = (b & c) | (~b & d); k = 0x5a827999
                case 20..<40: f = b ^ c ^ d;           k = 0x6ed9eba1
                case 40..<60: f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc
                default:      f = b ^ c ^ d;           k = 0xca62c1d6
                }
                let temp = ((a << 5) | (a >> 27)) &+ f &+ e &+ k &+ w[i]
                e = d; d = c; c = (b << 30) | (b >> 2); b = a; a = temp
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c
            h[3] = h[3] &+ d; h[4] = h[4] &+ e
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }

    private static func truncatePromptSummary(_ s: String) -> String {
        // R-F5-002：截到 60 字符；超长加 ellipsis。
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 60 { return trimmed }
        let cut = trimmed.index(trimmed.startIndex, offsetBy: 60)
        return String(trimmed[..<cut]) + "…"
    }

    // MARK: - 反查 API（HookIpcServer / MsgStreamBridge 用）

    /// 按 hook stdin 的 sessionId 反查子 agent meta（R-F5-001 / R-F5-004）。
    /// 线程安全：queue.sync 串行化访问 activeSubAgents。
    /// 实现 HookIpcJsonlSink.findSubAgent。
    public func findSubAgent(tabId: UUID, sessionId: String) -> SubAgentMetaProtocol? {
        return queue.sync {
            return activeSubAgents[tabId]?.values.first { $0.agentSessionId == sessionId }
        }
    }

    /// 按 agentId 反查 parentToolUseId（外部线程安全版本，自带 queue.sync）。
    /// 调用方**不得**在 watcher.queue 上调用本方法，否则会触发自我死锁。
    public func parentToolUseId(tabId: UUID, agentId: String) -> String? {
        return queue.sync {
            return activeSubAgents[tabId]?[agentId]?.parentToolUseId
        }
    }

    /// 反查 parentToolUseId 的 queue-internal 版本。
    /// **调用方必须已经在 watcher.queue 上**（例如 `JSONLWatcherDelegate.watcher(_:didReceive:for:)`
    /// 回调内部 — 该回调由 throttle 派发到本 queue 上执行）。在非 queue 线程调用
    /// 无 sync 保护，会产生数据竞争；在 queue 上调用 sync 版本会自我死锁。
    /// 由 MsgStreamBridge.injectParentToolUseId 使用，避免死锁。
    public func parentToolUseIdLocked(tabId: UUID, agentId: String) -> String? {
        return activeSubAgents[tabId]?[agentId]?.parentToolUseId
    }

    /// 反查整个 SubAgentMeta 的 queue-internal 版本（同上线程约定）。
    /// 用于 HistoryBridge 的非 queue 线程访问 — HistoryBridge 自己 hop 到 queue 上调用。
    public func subAgentMetaLocked(tabId: UUID, agentId: String) -> SubAgentMeta? {
        return activeSubAgents[tabId]?[agentId]
    }

    /// queue 访问入口（HistoryBridge / 其他外部代码使用，把 work 在 queue 上同步执行）。
    public func performLocked<T>(_ work: () -> T) -> T {
        return queue.sync(execute: work)
    }

    public func unwatch(tabId: UUID) {
        guard let s = streams.removeValue(forKey: tabId) else { return }
        s.stop()
        // 第三轮 review 🟡-3：tab 关闭时清理 sub-agent 索引，避免长期累积。
        // 在 queue 上同步执行 — activeSubAgents / pendingTaskMatches /
        // pendingAgentMatches 的所有写都串行化在此 queue。
        queue.sync {
            activeSubAgents.removeValue(forKey: tabId)
            pendingTaskMatches.removeValue(forKey: tabId)
            pendingAgentMatches.removeValue(forKey: tabId)
        }
    }

    public func unwatchAll() {
        for s in streams.values { s.stop() }
        streams.removeAll()
        // 同 unwatch：清理所有 tab 的 sub-agent 索引
        queue.sync {
            activeSubAgents.removeAll()
            pendingTaskMatches.removeAll()
            pendingAgentMatches.removeAll()
        }
    }

    /// Read-only check used by the container.
    public func isWatching(tabId: UUID) -> Bool {
        streams[tabId] != nil
    }

    /// Stop watchers for tabs that are no longer present.
    public func unwatchAllExcept(ids: Set<UUID>) {
        let stale = streams.keys.filter { !ids.contains($0) }
        for id in stale { unwatch(tabId: id) }
    }

    /// Encoded path used by Claude Code: /Users/foo/bar -> -Users-foo-bar.
    public static func encodeFolderPath(_ url: URL) -> String {
        let standardized = url.standardizedFileURL.path
        return standardized.replacingOccurrences(of: "/", with: "-")
    }

    public static func claudeProjectsDir(for folder: URL) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".claude/projects/\(encodeFolderPath(folder))",
                                    isDirectory: true)
    }
}

// MARK: - WatchStream

/// Per-Tab state. NOT MainActor; runs on watcher.queue.
final class WatchStream {
    let tabId: UUID
    let directory: URL
    let throttleInterval: TimeInterval
    let queue: DispatchQueue
    let log: TaggedLogger
    let onBatch: (UUID, [ParsedMessage]) -> Void
    /// 由 JSONLWatcher 注入：判断给定 tool_use_id 是否已被 hook 实时推送过。
    /// 闭包必须在 watcher.queue 上被调用（线程安全约束）。
    let hookPushedCheck: (String) -> Bool
    /// 父 session 中发现 Task tool_use 时回调（R-F2-002 两阶段匹配）。
    let onTaskToolUse: (_ toolUseId: String, _ prompt: String, _ tabId: UUID) -> Void
    /// agent-*.jsonl 首条 user message 时回调。
    let onAgentFirstMessage: (_ agentId: String, _ sessionId: String, _ firstContent: String, _ tabId: UUID) -> Void

    private var stream: FSEventStreamRef?
    /// 父 session 文件（非 agent-*.jsonl）。仅本字段参与 -c continue 决策。
    private var activeSessionFile: URL?
    private var lastOffset: UInt64 = 0
    /// agent-*.jsonl 多文件并行追加；每个文件独立维护 offset + dedup（R-F2-001）。
    /// 父 session.jsonl 不再独占 activeSessionFile 的角色 — 它现在跟 agent-*
    /// 一起进 multi-file watcher。
    private var fileOffsets: [URL: UInt64] = [:]
    /// 已发现首条 user message 并已上报的 agent-*.jsonl 文件集合（去重防止
    /// 同一 agent 文件被多次解析首条）。
    private var agentFirstSeen: Set<URL> = []

    private var pendingMessages: [ParsedMessage] = []
    private var throttleWorkItem: DispatchWorkItem?
    private var seenUuids = Set<String>()
    private var seenFallback = Set<String>()

    init(tabId: UUID,
         directory: URL,
         throttleInterval: TimeInterval,
         queue: DispatchQueue,
         log: TaggedLogger,
         hookPushedCheck: @escaping (String) -> Bool,
         onTaskToolUse: @escaping (_ toolUseId: String, _ prompt: String, _ tabId: UUID) -> Void,
         onAgentFirstMessage: @escaping (_ agentId: String, _ sessionId: String, _ firstContent: String, _ tabId: UUID) -> Void,
         onBatch: @escaping (UUID, [ParsedMessage]) -> Void) {
        self.tabId = tabId
        self.directory = directory
        self.throttleInterval = throttleInterval
        self.queue = queue
        self.log = log
        self.hookPushedCheck = hookPushedCheck
        self.onTaskToolUse = onTaskToolUse
        self.onAgentFirstMessage = onAgentFirstMessage
        self.onBatch = onBatch
    }

    func start() {
        // Ensure dir exists; if not, still set up FSEvents on parent so we
        // catch its creation (Claude Code creates it lazily on first message).
        let watchPaths: CFArray
        if FileManager.default.fileExists(atPath: directory.path) {
            watchPaths = [directory.path] as CFArray
        } else {
            let parent = directory.deletingLastPathComponent().path
            watchPaths = [parent] as CFArray
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // kFSEventStreamCreateFlagUseCFTypes is REQUIRED for our callback to
        // safely cast `eventPaths` to NSArray. Without it, `eventPaths` is a
        // raw `char**` (C string array) and unsafeBitCast → NSArray crashes
        // with EXC_BAD_ACCESS when dereferenced.
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagUseCFTypes
        )

        let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (_, info, count, eventPaths, _, _) in
                guard let info = info else { return }
                let me = Unmanaged<WatchStream>.fromOpaque(info).takeUnretainedValue()
                let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
                me.handleEvent(paths: paths, count: count)
            },
            &context,
            watchPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05,
            flags
        )
        guard let s = s else {
            log.error("FSEventStreamCreate failed for \(directory.path)")
            return
        }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        self.stream = s

        // Initial silent scan：
        // 启动时认领当前 latest session，把 lastOffset 推到 EOF 并预填 dedup
        // 集合（seenUuids / seenFallback）。**不**触发 onBatch — 这避免了：
        //   1. App 重启时每个 tab 把自己的整段历史推给 phone（phone 自带
        //      msg.history.request 协议按需拉，无需主动 flood）
        //   2. 历史回放被 MsgStreamBridge 误判为 "Claude 正在写入" → 把全部
        //      tab 都标成 working（即便用户当前只在某一个 tab 工作）
        // 只有后续 FSEvent 增量（用户实际操作产生的新行）才会走 onBatch。
        identifyActiveSession()
        // silentInitialScan 写入的字段（fileOffsets / seenUuids / seenFallback /
        // activeSubAgents / pendingTaskMatches / pendingAgentMatches）随后会被
        // FSEvent callback 在 watcher.queue 上访问。dispatch 到 queue 上做 scan，
        // 让所有写都串行化在同一 queue（第一轮 review 阻塞 #2）。
        // queue 是 serial 的：后续 FSEvent callback 自然排在 scan 之后执行。
        queue.async { [weak self] in
            self?.silentInitialScan()
        }
    }

    /// 启动时把当前 directory 下所有 *.jsonl（父 + agent-*）历史 "吃掉"：
    /// 推进每文件 offset + 填充 dedup 集合 + 把已存在的子 agent meta 预填
    /// （让重启后能继续识别历史子 agent 的反查需求）。
    private func silentInitialScan() {
        // 父 session 走 activeSessionFile（保留为 -c continue 决策依据）；
        // 所有 .jsonl 文件（含 agent-*）都执行 silent scan 让 dedup 起作用。
        let allFiles = enumerateAllJsonlFiles()
        for file in allFiles {
            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            let data: Data
            if #available(macOS 10.15.4, *) {
                data = (try? handle.readToEnd()) ?? Data()
            } else {
                data = handle.readDataToEndOfFile()
            }
            guard !data.isEmpty,
                  let chunk = String(data: data, encoding: .utf8) else { continue }
            fileOffsets[file] = UInt64(data.count)
            if file == activeSessionFile { lastOffset = UInt64(data.count) }
            let lines = chunk.split(separator: "\n", omittingEmptySubsequences: true)
            var isFirstLine = true
            for line in lines {
                let raw = String(line)
                if let msg = parseLine(raw) {
                    if let u = msg.uuid {
                        seenUuids.insert(u)
                    } else {
                        let stamp = msg.timestamp.map { "\(Int($0.timeIntervalSince1970 * 1000))" } ?? ""
                        seenFallback.insert("\(msg.type)|\(msg.sessionId ?? "")|\(stamp)")
                    }
                    // 静默扫描期间也要把两阶段匹配的索引建好，否则 App 重启后
                    // 历史子 agent 的 tool_approval / msg.stream 无法反查 parent。
                    indexMatchingHints(raw: raw, file: file, isFirstLine: isFirstLine)
                }
                isFirstLine = false
            }
            if file.lastPathComponent.hasPrefix("agent-") {
                agentFirstSeen.insert(file)
            }
        }
        log.info("silent initial scan: tab=\(tabId) files=\(allFiles.count) seenUuids=\(seenUuids.count)")
    }

    func stop() {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
        stream = nil
        throttleWorkItem?.cancel()
        throttleWorkItem = nil
    }

    private func handleEvent(paths: [String], count: Int) {
        // Re-identify session in case of rotation (R-M4-07).
        identifyActiveSession()
        // R-F2-001：读所有 .jsonl（父 + agent-*）增量行；每个文件独立 offset。
        let files = enumerateAllJsonlFiles()
        for file in files {
            readNewLines(from: file)
        }
        scheduleThrottle()
    }

    /// 列出 directory 下所有 .jsonl 文件。包括 agent-*.jsonl（R-F2-001 解除过滤）。
    fileprivate func enumerateAllJsonlFiles() -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { $0.lastPathComponent.hasSuffix(".jsonl") }
    }

    /// 识别父 session 文件（仅 *非* agent-* 的 latest）—— 该字段保留是因为
    /// `silentInitialScan` 需要把父 session 的 lastOffset 单独记录给 -c continue
    /// 体验保持一致；agent-* 文件不参与该判定（与 ProcessHost.hasHistory 对齐）。
    private func identifyActiveSession() {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let jsonls = urls.filter { url in
            let name = url.lastPathComponent
            return name.hasSuffix(".jsonl") && !name.hasPrefix("agent-")
        }
        let latest = jsonls.max { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return l < r
        }
        if let latest = latest, latest != activeSessionFile {
            activeSessionFile = latest
            lastOffset = 0
            log.info("active session => \(latest.lastPathComponent) (tab=\(tabId))")
        }
    }

    private func readNewLines(from file: URL) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        let isAgentFile = file.lastPathComponent.hasPrefix("agent-")
        let priorOffset = fileOffsets[file] ?? 0
        try? handle.seek(toOffset: priorOffset)
        let data: Data
        if #available(macOS 10.15.4, *) {
            data = (try? handle.readToEnd()) ?? Data()
        } else {
            data = handle.readDataToEndOfFile()
        }
        guard !data.isEmpty,
              let chunk = String(data: data, encoding: .utf8) else { return }
        let newOffset = priorOffset + UInt64(data.count)
        fileOffsets[file] = newOffset
        if file == activeSessionFile { lastOffset = newOffset }

        // Process complete lines only (last line might be incomplete; we
        // accept that — next FSEvent will reprocess from new offset).
        let lines = chunk.split(separator: "\n", omittingEmptySubsequences: true)
        var isFirstLineOfAgentFile = isAgentFile && !agentFirstSeen.contains(file) && priorOffset == 0
        for line in lines {
            let raw = String(line)
            if let msg = parseLine(raw) {
                // 两阶段匹配：在 dedup/emit 之前先解析 hint，让索引尽早建立
                // （否则若同批次同时收到 agent 首条 + 父 Task tool_use，先来的
                // 还没建索引，后来的就会孤儿）。
                indexMatchingHints(raw: raw, file: file, isFirstLine: isFirstLineOfAgentFile)
                if isFirstLineOfAgentFile {
                    agentFirstSeen.insert(file)
                    isFirstLineOfAgentFile = false
                }
                if shouldEmit(msg) {
                    pendingMessages.append(msg)
                }
            } else {
                let rawMsg = ParsedMessage(
                    type: "raw",
                    uuid: nil,
                    sessionId: nil,
                    timestamp: nil,
                    raw: raw,
                    parsed: nil
                )
                pendingMessages.append(rawMsg)
                log.warn("parse-failed line: \(raw.prefix(120))…")
            }
        }
    }

    /// 解析一行 raw JSON，触发两阶段匹配回调（R-F2-002 / R-F2-003）。
    /// 不影响 dedup / emit 流程；仅在 JSONLWatcher 的 activeSubAgents 索引上建立映射。
    fileprivate func indexMatchingHints(raw: String, file: URL, isFirstLine: Bool) {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let isAgentFile = file.lastPathComponent.hasPrefix("agent-")

        // 路径 1：父 session 中的 assistant.message.content[].type=tool_use, name=Task
        // → 提取 (id, input.prompt) 上报匹配
        if !isAgentFile, (obj["type"] as? String) == "assistant" {
            if let message = obj["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for item in content {
                    guard (item["type"] as? String) == "tool_use",
                          (item["name"] as? String) == "Task",
                          let id = item["id"] as? String,
                          let input = item["input"] as? [String: Any],
                          let prompt = input["prompt"] as? String,
                          !prompt.isEmpty else { continue }
                    onTaskToolUse(id, prompt, tabId)
                }
            }
            return
        }

        // 路径 2：agent-*.jsonl 的首条 user message（parentUuid == null）
        // → 提取 (agentId, sessionId, content) 上报匹配
        if isAgentFile, isFirstLine,
           (obj["type"] as? String) == "user",
           obj["parentUuid"] is NSNull || obj["parentUuid"] == nil {
            guard let agentId = obj["agentId"] as? String,
                  let sessionId = obj["sessionId"] as? String,
                  let message = obj["message"] as? [String: Any] else { return }
            // message.content 可能是 string，也可能是 [{type:text,text:...}]
            let content: String
            if let s = message["content"] as? String {
                content = s
            } else if let arr = message["content"] as? [[String: Any]] {
                content = arr.compactMap { ($0["text"] as? String) }.joined(separator: "\n")
            } else {
                return
            }
            guard !content.isEmpty else { return }
            onAgentFirstMessage(agentId, sessionId, content, tabId)
        }
    }

    private func parseLine(_ line: String) -> ParsedMessage? {
        guard let data = line.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        let type = (obj["type"] as? String) ?? "unknown"
        let uuid = obj["uuid"] as? String
        let session = obj["sessionId"] as? String ?? obj["session_id"] as? String
        var timestamp: Date? = nil
        if let ts = obj["timestamp"] as? String {
            timestamp = ISO8601DateFormatter().date(from: ts)
        }
        // We don't need to fully decode parsed object — the raw line is what
        // we forward to the Server. We pass nil here to keep memory lean.
        return ParsedMessage(
            type: type,
            uuid: uuid,
            sessionId: session,
            timestamp: timestamp,
            raw: line,
            parsed: nil
        )
    }

    private func shouldEmit(_ msg: ParsedMessage) -> Bool {
        // R-F5-001/002/003：若该消息包含的 tool_use_id 已被 hook 实时推送过，
        // 则跳过此条 JSONL，避免对手机端双推。
        let toolUseIds = extractToolUseIds(from: msg.raw)
        for id in toolUseIds where hookPushedCheck(id) {
            log.info("skip JSONL row dedup-by-hook tool_use_id=\(id)")
            return false
        }

        if let u = msg.uuid {
            if seenUuids.contains(u) { return false }
            seenUuids.insert(u)
            return true
        }
        // No uuid: use (type, session, timestamp) composite key (R-M4-03).
        let stamp = msg.timestamp.map { "\(Int($0.timeIntervalSince1970 * 1000))" } ?? ""
        let key = "\(msg.type)|\(msg.sessionId ?? "")|\(stamp)"
        if seenFallback.contains(key) { return false }
        seenFallback.insert(key)
        return true
    }

    /// 从 JSONL raw 行中提取已被 hook 推送过的 tool_use_id（仅 assistant.tool_use.id）。
    /// **不**包含 user.tool_result.tool_use_id —— tool_result 是答案落地记录，
    /// phone 端 message_card_list 需要它来配对 toolUseId 渲染"已回答"精简记录卡，
    /// 不能因为 hook 推过 tool_use 就把 tool_result 一并跳过（否则 phone 永远
    /// 看不到 ask 的答案历史）。
    private func extractToolUseIds(from raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        // 只处理 assistant message 中的 tool_use（user message 中的 tool_result 不去重）
        guard (obj["type"] as? String) == "assistant" else { return [] }
        var ids: [String] = []
        if let message = obj["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            for item in content {
                guard (item["type"] as? String) == "tool_use",
                      let id = item["id"] as? String else { continue }
                // Task* 三件套（TaskCreate/TaskUpdate/TaskList/TaskGet）完全 bypass
                // Pre/PostToolUse hook (Claude Code issue #20243)，但 PostToolUse
                // matcher=`.*` 仍可能把这些 tool_use_id 加进 hookPushedToolUseIds
                // 导致 JSONL 通道误 dedup —— 手机端就拿不到真实 Task tool_use raw。
                // 这里显式排除 Task* 工具，让它们的 JSONL row 始终走透传路径。
                let name = item["name"] as? String ?? ""
                if name == "TaskCreate" || name == "TaskUpdate" || name == "TaskList" || name == "TaskGet" {
                    continue
                }
                ids.append(id)
            }
        }
        return ids
    }

    private func scheduleThrottle() {
        throttleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard !self.pendingMessages.isEmpty else { return }
            let batch = self.pendingMessages
            self.pendingMessages.removeAll()
            self.onBatch(self.tabId, batch)
        }
        throttleWorkItem = work
        queue.asyncAfter(deadline: .now() + throttleInterval, execute: work)
    }
}

// MARK: - HookIpcJsonlSink conformance

extension JSONLWatcher: HookIpcJsonlSink {
    /// Hook（PreToolUse / Stop / SessionEnd 等）已实时推送过该 tool_use 后调用，
    /// 后续 JSONL 中对应的 assistant.tool_use / user.tool_result 会被跳过。
    /// R-F5-001/002/003。
    public func markHookPushed(toolUseId: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.hookPushedToolUseIds[toolUseId] = Date()
            // 顺带清理过期项
            let now = Date()
            let ttl = self.hookPushedTTL
            self.hookPushedToolUseIds = self.hookPushedToolUseIds.filter {
                now.timeIntervalSince($0.value) < ttl
            }
        }
    }
}
