// HistoryBridge.swift
// Replies to phone-originated `msg.history.request` envelopes by reading the
// active JSONL file for that Tab and returning the last N messages (optionally
// filtered to lines before a given timestamp).
//
// See 需求规格说明书 §3.4 4.4 / R-A3-* (loadHistory).
// R-F8-001：历史回放也透传 agent-*.jsonl，让 phone 端 ChatRepository 把历史中
// 的子 agent 消息按 isSidechain/parentToolUseId 重组（与实时通道同逻辑）。
// R-F8-002：历史回放时 phone 端 pendingSidechainBuffer 超时延长到 30s，这是
// phone 侧的策略，mac 侧不需要做特殊延时 —— mac 仍按时间顺序送，phone 自处理。

import Foundation
import Combine

@MainActor
public final class HistoryBridge {
    private let log = AppLogger.shared.tagged("HistoryBridge")
    private weak var ws: WSClient?
    private weak var tabManager: TabManager?
    private var cancellables = Set<AnyCancellable>()

    /// Hard cap so a misbehaving phone cannot force us to read the entire file.
    private let maxLimit = 200
    private let defaultLimit = 50

    public init(ws: WSClient, tabManager: TabManager) {
        self.ws = ws
        self.tabManager = tabManager
        ws.inbound
            .filter { $0.type == "msg.history.request" }
            .sink { [weak self] msg in
                guard let self = self else { return }
                Task { await self.handle(msg) }
            }
            .store(in: &cancellables)
    }

    private func handle(_ msg: ProtocolMessage) async {
        guard let data = msg.data,
              let req = decode(data, MsgHistoryRequestPayload.self) else {
            log.warn("malformed msg.history.request")
            return
        }
        guard let tabUUID = UUID(uuidString: req.tabId),
              let tab = tabManager?.tab(by: tabUUID) else {
            await sendResponse(tabId: req.tabId, messages: [], hasMore: false)
            return
        }
        let limit = min(max(1, req.limit ?? defaultLimit), maxLimit)
        let beforeDate: Date? = req.before.flatMap {
            ISO8601DateFormatter().date(from: $0)
        }
        let (messages, hasMore) = await Self.readHistory(
            folder: tab.folder, limit: limit, before: beforeDate
        )
        await sendResponse(tabId: req.tabId, messages: messages, hasMore: hasMore)
    }

    private func sendResponse(tabId: String, messages: [AnyJSON], hasMore: Bool) async {
        let payload = MsgHistoryResponsePayload(tabId: tabId, messages: messages, hasMore: hasMore)
        let any: AnyJSON? = {
            guard let data = try? JSONEncoder().encode(payload) else { return nil }
            return try? JSONDecoder().decode(AnyJSON.self, from: data)
        }()
        await ws?.send(ProtocolMessage(type: "msg.history.response", data: any))
        log.info("sent msg.history.response tab=\(tabId) count=\(messages.count) hasMore=\(hasMore)")
    }

    // MARK: - File IO (off main actor would be nicer, but JSONL files are
    // tiny and we already pay for I/O in the watcher loop; keep this simple).

    /// Reads the latest session JSONL file *and* any agent-*.jsonl files
    /// (R-F8-001) for the given Tab folder and returns at most `limit` parsed
    /// lines whose `timestamp` is < `before` (if provided). Lines are merged
    /// across files by timestamp (oldest first) so the phone can prepend them
    /// and reconstruct sub-agent folded blocks identically to live streaming.
    nonisolated public static func readHistory(
        folder: URL,
        limit: Int,
        before: Date?
    ) async -> (messages: [AnyJSON], hasMore: Bool) {
        let dir = JSONLWatcher.claudeProjectsDir(for: folder)
        let files = allHistoryFiles(in: dir)
        guard !files.isEmpty else { return ([], false) }

        var parsed: [(Date?, AnyJSON)] = []
        let iso = ISO8601DateFormatter()
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let text = String(data: data, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            parsed.reserveCapacity(parsed.count + lines.count)
            for line in lines {
                guard let lineData = line.data(using: .utf8) else { continue }
                guard let any = try? JSONDecoder().decode(AnyJSON.self, from: lineData) else {
                    continue
                }
                var ts: Date? = nil
                if case .object(let dict) = any,
                   case .string(let tsStr) = dict["timestamp"] ?? .null {
                    ts = iso.date(from: tsStr)
                }
                parsed.append((ts, any))
            }
        }
        // 跨文件按 timestamp 排序：父 session 和 agent-* 是同一对话的不同分支，
        // phone 端需要按时间顺序重组折叠块。
        parsed.sort { ($0.0 ?? .distantPast) < ($1.0 ?? .distantPast) }

        // 第一轮 review 阻塞 #2 修复：R-F8-001 要求历史回放也带 parent_tool_use_id，
        // 否则手机端历史回放重建的子 agent 块与父 Task tool_use 永远分离为两个块。
        // 这里就地做"两阶段 promptHash 匹配"（与 JSONLWatcher 同算法），不跨 actor。
        let agentIdToParent = buildAgentIdToParentMap(parsed: parsed)
        let injected = parsed.map { (ts, any) -> (Date?, AnyJSON) in
            return (ts, injectParentToolUseId(any, agentMap: agentIdToParent))
        }

        // Filter by `before` if provided. A row without a timestamp is kept
        // (we can't prove it's after `before`).
        let filtered: [(Date?, AnyJSON)] = {
            guard let before = before else { return injected }
            return injected.filter { ($0.0 ?? .distantPast) < before }
        }()
        // Take last `limit` (most recent before).
        let tailStart = max(0, filtered.count - limit)
        let tail = filtered[tailStart...]
        let hasMore = tailStart > 0
        return (tail.map { $0.1 }, hasMore)
    }

    /// 历史回放就地匹配（agentId → parentToolUseId）。
    /// 算法与 JSONLWatcher 的 promptHash 一致：父 session Task tool_use 的 input.prompt
    /// 与 agent-X.jsonl 首条 user message 的 content 内容相同 → 匹配。
    nonisolated private static func buildAgentIdToParentMap(
        parsed: [(Date?, AnyJSON)]
    ) -> [String: String] {
        var parentByHash: [String: String] = [:]   // promptHash → toolUseId
        var agentByHash: [String: String] = [:]    // promptHash → agentId
        for (_, any) in parsed {
            guard case .object(let obj) = any else { continue }
            // 父 session 的 Task tool_use
            if case .object(let msg) = obj["message"] ?? .null,
               case .array(let contents) = msg["content"] ?? .null {
                for c in contents {
                    if case .object(let item) = c,
                       case .string("tool_use") = item["type"] ?? .null,
                       case .string("Task") = item["name"] ?? .null,
                       case .string(let id) = item["id"] ?? .null,
                       case .object(let input) = item["input"] ?? .null,
                       case .string(let prompt) = input["prompt"] ?? .null {
                        let h = promptHash(prompt)
                        parentByHash[h] = id
                    }
                }
            }
            // agent-X.jsonl 首条（parentUuid == null + isSidechain=true）
            let isFirst: Bool = {
                if case .null = (obj["parentUuid"] ?? .null) { return true }
                return false
            }()
            guard case .bool(true) = (obj["isSidechain"] ?? .null),
                  isFirst,
                  case .string(let agentId) = (obj["agentId"] ?? .null),
                  case .object(let msg) = (obj["message"] ?? .null) else { continue }
            // content 可能是 string（user message）或 array（含 text 块）
            var firstText: String? = nil
            if case .string(let s) = msg["content"] ?? .null {
                firstText = s
            } else if case .array(let arr) = msg["content"] ?? .null {
                for c in arr {
                    if case .object(let item) = c,
                       case .string(let txt) = item["text"] ?? .null {
                        firstText = txt; break
                    }
                }
            }
            if let txt = firstText {
                agentByHash[promptHash(txt)] = agentId
            }
        }
        // 两 map 在 hash 上 join
        var result: [String: String] = [:]
        for (h, agentId) in agentByHash {
            if let toolUseId = parentByHash[h] {
                result[agentId] = toolUseId
            }
        }
        return result
    }

    /// 在 sidechain message 上注入 parent_tool_use_id 字段（与 MsgStreamBridge 同语义）。
    nonisolated private static func injectParentToolUseId(
        _ any: AnyJSON, agentMap: [String: String]
    ) -> AnyJSON {
        guard case .object(var obj) = any else { return any }
        guard case .bool(true) = (obj["isSidechain"] ?? .null) else { return any }
        guard case .string(let agentId) = (obj["agentId"] ?? .null) else { return any }
        if case .string = obj["parent_tool_use_id"] { return any }  // 已有则保留
        guard let parentId = agentMap[agentId] else { return any }
        obj["parent_tool_use_id"] = .string(parentId)
        return .object(obj)
    }

    /// 前 200 字符 Swift Hasher（**进程内**自洽即可 — 父 Task tool_use 和子 agent
    /// 首条都在 readHistory 一次调用内 hash，不跨进程不跨调用比较。算法与
    /// JSONLWatcher.promptHash（SHA1）独立，无需一致 — 两边都是各自闭环的匹配。
    nonisolated private static func promptHash(_ prompt: String) -> String {
        let truncated = String(prompt.prefix(200))
        var hasher = Hasher()
        hasher.combine(truncated)
        return String(hasher.finalize(), radix: 16, uppercase: false)
    }

    /// R-F8-001：列出最新父 session.jsonl + 全部 agent-*.jsonl。
    /// 不收录历史 session（per-project 可能堆积多份）—— 那是别的对话历史，
    /// 不应混入本次重连回填。agent-*.jsonl 只跟"最近一次 session"绑定（Claude
    /// SDK 创建后不会删，但 phone 端 dedup 兜底 + limit cap，足够安全）。
    nonisolated private static func allHistoryFiles(in dir: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        // 父 session：选 mtime 最新的非 agent-* 文件
        let parents = urls.filter { url in
            let name = url.lastPathComponent
            return name.hasSuffix(".jsonl") && !name.hasPrefix("agent-")
        }
        let latestParent = parents.max { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return l < r
        }
        // 第二轮 review 🟡-1：跨会话污染过滤。
        // project 目录里可能累积多个旧会话的 agent-*.jsonl。如果全部纳入
        // buildAgentIdToParentMap，会用与本次重连无关的 Task tool_use 去匹配
        // 父子关系。即便 mtime cutoff 不能 100% 精准，至少能裁掉跨日累积。
        // 策略：仅取 mtime ≥ 父 session mtime - 24h 的 agent-*。父 session
        // mtime 不可得时（理论上不会发生）退化为全集（与改造前行为一致）。
        let cutoff: Date? = latestParent.flatMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }.flatMap { $0.addingTimeInterval(-24 * 3600) }
        let agents = urls.filter { url in
            let name = url.lastPathComponent
            guard name.hasSuffix(".jsonl"), name.hasPrefix("agent-") else { return false }
            guard let cutoff = cutoff,
                  let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
                return true  // 父 session mtime 取不到 → 不过滤，与旧行为一致
            }
            return mtime >= cutoff
        }
        return ([latestParent].compactMap { $0 }) + agents
    }
}
