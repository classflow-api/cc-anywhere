// Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.
//
// HookIpcServer.swift
// Unix domain socket server，作为 hook bridge Python 脚本 ↔ Mac App 的中转。
//
// 详见 技术实施文档.md §4.2。
//
// 关键设计：
// 1. `actor` 串行化 pendingRequests 表的读写，天然保证 winner 锁无竞态（R-F1-013）。
// 2. accept loop + 每连接独立 Task 处理，不互相阻塞。
// 3. line-delimited JSON 双向分帧，与 hook bridge Python 端约定。
// 4. 5 分钟超时 + 每 30s reapTimer 扫描 pending 表回收过期请求（R-F1-007）。
// 5. tab_id 校验通过 `HookIpcTabRouter` 抽象注入，避免依赖 TabManager 实现细节。
// 6. winner 锁：进入 actor 后检查 `answered` flag；已 answered 直接丢弃，否则
//    mark answered + resolve continuation。
// 7. socket 文件权限 0600（R-F1-005），启动时 unlink 残留文件再 bind。

import Foundation
import Darwin

// MARK: - IpcConn (BSD socket connection wrapper)
//
// 为什么不用 Network.framework：macOS 的 NWListener 对 Unix domain SOCK_STREAM
// 监听返回 POSIXErrorCode 22 (EINVAL) — 这是 Network.framework 的已知限制（它的
// .unix endpoint 只支持 client 侧 NWConnection，不支持 server 侧 NWListener）。
// 因此 IPC server 用 BSD socket(2) + DispatchSourceRead 实现 accept loop，
// 每个 client fd 包装为 IpcConn 给上层用。

/// 单个 client 连接的轻量包装。所有 I/O 阻塞，但封装为 async。
final class IpcConn: @unchecked Sendable {
    let fd: Int32
    private var closed = false
    private let closeLock = NSLock()

    init(fd: Int32) {
        self.fd = fd
    }

    /// 阻塞读至 `\n` 或 EOF；返回不含 `\n` 的 Data。
    func recvLine(maxLen: Int = 1024 * 1024) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            var buf = Data()
            var chunk = [UInt8](repeating: 0, count: 65536)
            while buf.count < maxLen {
                let n = chunk.withUnsafeMutableBufferPointer { ptr in
                    Darwin.read(self.fd, ptr.baseAddress, ptr.count)
                }
                if n == 0 {
                    if buf.isEmpty { throw HookIpcServerError.connectionClosed }
                    return buf
                }
                if n < 0 {
                    let err = errno
                    if err == EINTR { continue }
                    throw HookIpcServerError.connectionClosed
                }
                let received = chunk.prefix(n)
                buf.append(contentsOf: received)
                if let _ = received.firstIndex(of: 0x0A) {
                    // 截到 \n 之前
                    if let nl = buf.firstIndex(of: 0x0A) {
                        return buf.prefix(nl)
                    }
                    return buf
                }
            }
            throw HookIpcServerError.frameTooLarge
        }.value
    }

    /// 阻塞写完整 data（包括尾部 `\n` 由调用方追加）。
    func sendData(_ data: Data) async {
        await Task.detached(priority: .userInitiated) {
            var sent = 0
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let p = raw.baseAddress!
                while sent < data.count {
                    let n = Darwin.write(self.fd, p.advanced(by: sent), data.count - sent)
                    if n < 0 {
                        if errno == EINTR { continue }
                        return
                    }
                    if n == 0 { return }
                    sent += n
                }
            }
        }.value
    }

    func close() {
        closeLock.lock()
        defer { closeLock.unlock() }
        if !closed {
            _ = Darwin.close(fd)
            closed = true
        }
    }
}

// MARK: - 内部数据结构

/// 登记表中一条 pending ask 请求。
private struct PendingAskRequest {
    let requestId: String            // UUIDv4，R-F1-015
    let tabId: UUID
    let toolUseId: String
    let askKind: String              // "user_question" | "tool_approval"
    let createdAt: Date
    let deadline: Date               // createdAt + 5 min
    /// 用于把响应回写给 hook bridge socket。
    let continuation: CheckedContinuation<HookIpcResponseAsk, Never>
    var answered: Bool = false
    // 以下字段用于 republishPendingToPhone 重发（phone 重连恢复未答 ask 卡片）
    let questions: [AskQuestionItem]?
    let toolName: String?
    let toolInput: AnyJSON?
    // R-F5：子 agent 上下文（仅 tool_approval 类有值）
    let parentToolUseIdForCard: String?
    let subAgentSummary: String?
    let isFromSubAgent: Bool?
}

// MARK: - HookIpcServer

public actor HookIpcServer {
    private let log = AppLogger.shared.tagged("HookIpcServer")

    /// socket 文件路径，默认 `~/Library/Application Support/cc-anywhere/hook.sock`。
    public let socketPath: URL

    // MARK: 协作对象（弱引用，由外部 wiring 时注入）

    /// ws 客户端推送通道。
    public weak var wsClient: HookIpcWsSink?
    /// JSONLWatcher，用于去重（hook 已推 tool_use_id）。
    public weak var jsonlWatcher: HookIpcJsonlSink?
    /// Mac 端 AskQuestionCard 控制器。
    public weak var cardController: HookIpcCardSink?
    /// 上报 Claude 活动状态变化（hook 收到 ask/progress_pre → working / notification idle → waiting）
    public weak var activitySink: HookIpcActivitySink?

    private let tabRouter: HookIpcTabRouter

    // MARK: 内部状态

    private var pendingRequests: [String: PendingAskRequest] = [:]
    private var serverFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var reapTimer: Task<Void, Never>?
    private var running: Bool = false

    /// 默认 ask 请求超时 5 分钟。
    /// Mac App inner timeout — 卡片未答时降级到 Claude TUI 自带弹窗的时机。
    /// 与 settings.json 中 hook `timeout: 1800` (30 分钟) 对齐，保证 30 分钟内
    /// 走在 cc-anywhere 远程通道（中途走开干点别的也不会被踢回 TUI）。
    public static let defaultAskDeadline: TimeInterval = 30 * 60
    /// reaper 扫描间隔 30s。
    public static let reapInterval: TimeInterval = 30

    // MARK: 初始化

    public init(socketPath: URL, tabRouter: HookIpcTabRouter) {
        self.socketPath = socketPath
        self.tabRouter = tabRouter
    }

    // MARK: 公共 API

    public func setWsClient(_ ws: HookIpcWsSink?) {
        self.wsClient = ws
    }

    public func setJsonlWatcher(_ watcher: HookIpcJsonlSink?) {
        self.jsonlWatcher = watcher
    }

    public func setCardController(_ controller: HookIpcCardSink?) {
        self.cardController = controller
    }

    public func setActivitySink(_ sink: HookIpcActivitySink?) {
        self.activitySink = sink
    }

    /// 报告 Claude 活动状态变化（hook 调用入口）。
    /// 不在 actor 内做 UI 更新，由 sink 在 MainActor 上处理。
    private func reportActivity(tabUUID: UUID, activity: String) {
        guard let sink = activitySink else { return }
        Task { @MainActor in
            sink.setActivity(tabId: tabUUID, activity: activity)
        }
    }

    public func isRunning() -> Bool { running }

    /// 启动 BSD Unix domain socket listener + reapTimer。
    /// - 若残留 socket 文件存在，先 unlink。
    /// - bind 后 chmod 0600（R-F1-005）。
    public func start() throws {
        guard !running else {
            log.warn("start() called while already running, ignored")
            return
        }
        let path = socketPath.path

        // 确保父目录存在
        let parent = socketPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )

        // unlink 残留文件
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }

        // 1. socket(2)
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 {
            throw HookIpcServerError.listenerInitFailed("socket() errno=\(errno)")
        }

        // 2. bind(2)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        // sun_path 限长 104（macOS）。
        let pathBytes = path.utf8CString
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        if pathBytes.count > maxLen {
            Darwin.close(fd)
            throw HookIpcServerError.listenerInitFailed("socket path too long (>\(maxLen))")
        }
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: maxLen) { dst in
                pathBytes.withUnsafeBufferPointer { src in
                    memcpy(dst, src.baseAddress, pathBytes.count)
                }
            }
        }
        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if bindResult < 0 {
            let e = errno
            Darwin.close(fd)
            throw HookIpcServerError.listenerInitFailed("bind() errno=\(e)")
        }

        // 3. chmod 0600（R-F1-005）
        _ = Darwin.chmod(path, 0o600)

        // 4. listen(2)
        if Darwin.listen(fd, 16) < 0 {
            let e = errno
            Darwin.close(fd)
            try? FileManager.default.removeItem(atPath: path)
            throw HookIpcServerError.listenerInitFailed("listen() errno=\(e)")
        }

        self.serverFD = fd

        // 5. accept loop via DispatchSourceRead — fd 可读即代表有新连接
        let source = DispatchSource.makeReadSource(
            fileDescriptor: fd,
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let clientFD = Darwin.accept(fd, nil, nil)
            if clientFD < 0 { return }
            let conn = IpcConn(fd: clientFD)
            Task { await self.handleConnection(conn) }
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        self.acceptSource = source
        self.running = true

        // reap timer
        reapTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.reapInterval) * 1_000_000_000)
                if Task.isCancelled { break }
                await self?.reapExpired()
            }
        }

        log.info("HookIpcServer started at \(path) (BSD socket fd=\(fd))")
    }

    /// 停止 listener，清理 pending requests（全部 resolve 为 cancelled），删除 socket 文件。
    public func stop() async {
        guard running else { return }
        running = false

        reapTimer?.cancel()
        reapTimer = nil

        acceptSource?.cancel()  // setCancelHandler 内已 close(fd)
        acceptSource = nil
        serverFD = -1

        // resolve 所有还在 pending 的请求（按 cancelled 处理）
        for (_, var req) in pendingRequests where !req.answered {
            req.answered = true
            req.continuation.resume(returning: .failure(error: "server stopped"))
        }
        pendingRequests.removeAll()

        // 删除 socket 文件
        try? FileManager.default.removeItem(at: socketPath)

        log.info("HookIpcServer stopped")
    }

    /// 重新广播所有未答完的 pending request 给 ws 端（phone）。
    /// 触发时机：phone 重连或新 phone 上线时（DependencyContainer 监听 phoneCount 增加）。
    /// 避免用户场景：phone 端 ask 未答时关 App → 重开后看不到 pending 卡片（state 丢失）。
    public func republishPendingToPhone() async {
        guard let ws = wsClient else { return }
        for (_, req) in pendingRequests where !req.answered {
            let payload = AskQuestionPendingPayload(
                requestId: req.requestId,
                tabId: req.tabId.uuidString,
                toolUseId: req.toolUseId,
                askKind: req.askKind,
                allowOther: true,
                questions: req.questions,
                toolName: req.toolName,
                toolInput: req.toolInput,
                parentToolUseId: req.parentToolUseIdForCard,
                subAgentSummary: req.subAgentSummary,
                isFromSubAgent: req.isFromSubAgent
            )
            await MainActor.run {
                ws.sendAskQuestionPending(payload)
            }
        }
        log.info("republished \(pendingRequests.count) pending ask request(s) to phone")
    }

    // MARK: ws 入口（外部 ws 收到 phone 回复时调用）

    /// 由 ws 客户端在收到 `ask.question.answer` 时调用。R-F1-013 winner 锁。
    public func receiveAnswerFromWs(requestId: String,
                                    answers: [String: String],
                                    answeredBy: String) async {
        await resolveAsk(
            requestId: requestId,
            response: .userQuestion(answers: answers),
            answeredBy: answeredBy,
            answersForBroadcast: answers
        )
    }

    /// 由 ws 客户端在收到 tool_approval 回复时调用。
    public func receiveApprovalFromWs(requestId: String,
                                      decision: String,
                                      reason: String?,
                                      answeredBy: String) async {
        await resolveAsk(
            requestId: requestId,
            response: .toolApproval(decision: decision, reason: reason),
            answeredBy: answeredBy,
            answersForBroadcast: [:]
        )
    }

    /// 由 Mac Card UI 在用户点击提交时调用。
    public func receiveLocalAnswerFromMacCard(requestId: String,
                                              answers: [String: String]) async {
        await resolveAsk(
            requestId: requestId,
            response: .userQuestion(answers: answers),
            answeredBy: "mac",
            answersForBroadcast: answers
        )
    }

    /// Mac Card UI 端用户对 tool_approval 的本地决定。
    public func receiveLocalApprovalFromMacCard(requestId: String,
                                                decision: String,
                                                reason: String?) async {
        await resolveAsk(
            requestId: requestId,
            response: .toolApproval(decision: decision, reason: reason),
            answeredBy: "mac",
            answersForBroadcast: [:]
        )
    }

    // MARK: 内部：winner 锁仲裁

    /// 进入 actor 后串行化执行；这是 winner 锁的唯一入口。
    private func resolveAsk(requestId: String,
                            response: HookIpcResponseAsk,
                            answeredBy: String,
                            answersForBroadcast: [String: String]) async {
        guard var req = pendingRequests[requestId] else {
            log.debug("resolveAsk: requestId=\(requestId) not found (already gone)")
            return
        }
        if req.answered {
            log.info("resolveAsk: requestId=\(requestId) already answered, dropping winner=\(answeredBy)")
            return
        }
        req.answered = true
        pendingRequests[requestId] = req

        // resolve continuation（回写 socket）
        req.continuation.resume(returning: response)
        pendingRequests.removeValue(forKey: requestId)

        // 仅在 answered 成功路径 markHookPushed（第二轮 Review 阻塞 #2 修复）：
        // - 成功 answered → hook 已实际承担推送责任，JSONL 落盘可跳过避免双推
        // - 注：reapExpired/cancelled 路径走的是另一条 resolve 链，不进入这里，
        //   因此 timeout 后 JSONL 仍会正常推 → phone 补拉历史可见
        if !req.toolUseId.isEmpty {
            jsonlWatcher?.markHookPushed(toolUseId: req.toolUseId)
        }

        // 通知 Mac Card UI dismiss
        if let cardController = cardController {
            await cardController.dismiss(
                requestId: requestId,
                reason: .answered,
                by: answeredBy
            )
        }

        // ws 广播 ask.question.answered（让其他端展示已被回答）
        if let ws = wsClient {
            let payload = AskQuestionAnsweredPayload(
                requestId: requestId,
                answeredBy: answeredBy,
                answers: answersForBroadcast
            )
            await MainActor.run {
                ws.sendAskQuestionAnswered(payload)
            }
        }

        log.info("resolveAsk: requestId=\(requestId) winner=\(answeredBy)")
    }

    // MARK: 内部：超时回收

    private func reapExpired() async {
        let now = Date()
        let expired = pendingRequests.values.filter { !$0.answered && $0.deadline < now }
        guard !expired.isEmpty else { return }
        log.info("reapExpired: found \(expired.count) expired request(s)")
        for var req in expired {
            req.answered = true
            pendingRequests[req.requestId] = req
            req.continuation.resume(returning: .failure(error: "timeout"))
            pendingRequests.removeValue(forKey: req.requestId)

            // 通知 Mac Card UI
            if let cardController = cardController {
                await cardController.dismiss(
                    requestId: req.requestId,
                    reason: .timeout,
                    by: nil
                )
            }

            // ws 推 timeout
            if let ws = wsClient {
                let payload = AskQuestionTimeoutPayload(
                    requestId: req.requestId,
                    reason: "timeout"
                )
                await MainActor.run {
                    ws.sendAskQuestionTimeout(payload)
                }
            }
        }
    }

    // MARK: 内部：连接处理

    /// 处理一个 hook bridge 进来的连接：
    /// 1. 读 line-delimited JSON
    /// 2. 反序列化 HookIpcRequest
    /// 3. 根据 kind 路由：ask 阻塞等待 / progress|notification 立即 reply `{}`
    private func handleConnection(_ connection: IpcConn) async {
        // 读一帧（直到 `\n` 为止）
        let reqLineData: Data
        do {
            reqLineData = try await connection.recvLine()
        } catch {
            log.warn("read request line failed: \(error)")
            connection.close()
            return
        }

        // 反序列化
        let req: HookIpcRequest
        do {
            req = try JSONDecoder().decode(HookIpcRequest.self, from: reqLineData)
        } catch {
            // NFR-U1：系统级错误（decode 失败 / payload 损坏）不能比"没装 hook"更糟。
            // 返回空对象 → hook bridge 透传给 SDK → 走 fallback。
            log.warn("decode request failed: \(error); raw=\(String(data: reqLineData, encoding: .utf8) ?? "")")
            await Self.sendResponse(connection: connection, json: [:])
            connection.close()
            return
        }

        // 校验 tab_id（R-F1-006）
        // NFR-U1/U2：tab 路由失败属系统级错误（非用户决策），按"软失败"返回空对象，
        // 让 SDK 走 fallback；不返回 error，避免 hook bridge 翻译为 deny 误拦工具调用。
        guard tabRouter.isActive(tabIdString: req.tabId),
              let tabUUID = tabRouter.uuid(forTabIdString: req.tabId) else {
            log.warn("unknown tab_id=\(req.tabId), kind=\(req.kind); soft-fail")
            await Self.sendResponse(connection: connection, json: [:])
            connection.close()
            return
        }

        switch req.kind {
        case "ask":
            await handleAsk(req: req, tabUUID: tabUUID, connection: connection)
        case "progress_pre":
            await handleProgressPre(req: req, tabUUID: tabUUID, connection: connection)
        case "progress_post":
            await handleProgressPost(req: req, tabUUID: tabUUID, connection: connection)
        case "notification":
            await handleNotification(req: req, tabUUID: tabUUID, connection: connection)
        default:
            // NFR-U1：未知 kind 属系统级错误，软失败返回 {} 让 SDK 走 fallback
            log.warn("unknown kind=\(req.kind); soft-fail")
            await Self.sendResponse(connection: connection, json: [:])
            connection.close()
        }
    }

    // MARK: 内部：ask 处理

    private func handleAsk(req: HookIpcRequest, tabUUID: UUID, connection: IpcConn) async {
        let requestId = UUID().uuidString  // R-F1-015
        let toolUseId = req.toolUseId ?? ""
        let toolName = req.toolName ?? ""
        log.info("handleAsk: req=\(requestId) tool=\(toolName) toolUseId=\(toolUseId) tab=\(tabUUID)")
        // PreToolUse hook 命中 = Claude 在调工具（或问问题）= 工作中
        reportActivity(tabUUID: tabUUID, activity: "working")

        // 判定 askKind：AskUserQuestion → user_question；其它 → tool_approval
        let askKind: String = (toolName == "AskUserQuestion") ? "user_question" : "tool_approval"

        // 与 Claude permission mode 对齐：tool_approval 类（PreToolUse 拦截 Bash/Edit/...）
        // 在高权限 mode（acceptEdits/auto/dontAsk/bypassPermissions）下直接 auto-allow，
        // 不弹 Mac 卡片、不推手机端 —— 用户已经明确授信 Claude 自决工具。
        // user_question 类（Claude 主动调 AskUserQuestion 工具问用户）始终走完整流程，
        // 这是 Claude 自己想问的，与权限模式无关。
        if askKind == "tool_approval" {
            let mode = tabRouter.permissionMode(forTabIdString: tabUUID.uuidString)
                ?? PermissionMode.default.rawValue
            let highTrustModes: Set<String> = [
                PermissionMode.acceptEdits.rawValue,
                PermissionMode.auto.rawValue,
                PermissionMode.dontAsk.rawValue,
                PermissionMode.bypassPermissions.rawValue,
            ]
            if highTrustModes.contains(mode) {
                log.info("handleAsk auto-allow (mode=\(mode)): req=\(requestId) tool=\(toolName)")
                let resp = HookIpcResponseAsk.toolApproval(
                    decision: "allow",
                    reason: "permission_mode=\(mode)"
                )
                await Self.sendResponseAsk(connection: connection, response: resp)
                connection.close()
                return
            }
        }

        // 解析 questions（如果是 user_question）
        var questions: [AskQuestionItem]? = nil
        if askKind == "user_question", let toolInput = req.toolInput {
            questions = parseQuestions(from: toolInput)
        }

        // R-F5-001 / R-F5-004：tool_approval 类卡片注入子 agent 上下文。
        // 反查路径：hook stdin 的 sessionId → JSONLWatcher.activeSubAgents
        // → SubAgentMeta（含 parentToolUseId + 父 Task prompt 摘要）。
        // 注：findSubAgent 内部用 queue.sync 串行化（线程安全），不需 await。
        // R-F7-001 / R-F7-002（permission mode 继承）：本路径**不**做改动 ——
        // 子 agent 内部触发 hook bridge 时，bridge Python 是父 claude 子进程
        // fork 出来的，CC_ANYWHERE_TAB_ID env 必然继承父 tab；handleAsk line
        // 555-573 的 auto-allow 走 `tabRouter.permissionMode(forTabIdString:)`
        // 查的就是父 tab 的 mode → permission mode 继承默认成立。
        var parentToolUseIdForCard: String? = nil
        var subAgentSummary: String? = nil
        var isFromSubAgent: Bool? = nil
        if askKind == "tool_approval", let hookSessionId = req.sessionId {
            if let meta = jsonlWatcher?.findSubAgent(tabId: tabUUID, sessionId: hookSessionId) {
                parentToolUseIdForCard = meta.parentToolUseId
                subAgentSummary = meta.promptSummary
                isFromSubAgent = true
                log.info("ask sub-agent context hit: req=\(requestId) sessionId=\(hookSessionId) parentToolUseId=\(meta.parentToolUseId ?? "<unmatched>")")
            } else {
                log.debug("ask no sub-agent context: req=\(requestId) sessionId=\(hookSessionId) (parent session tool call)")
            }
        }

        // 注册 pending continuation；continuation 在 resolveAsk / reapExpired 内 resume
        let response: HookIpcResponseAsk = await withCheckedContinuation { continuation in
            let pending = PendingAskRequest(
                requestId: requestId,
                tabId: tabUUID,
                toolUseId: toolUseId,
                askKind: askKind,
                createdAt: Date(),
                deadline: Date().addingTimeInterval(Self.defaultAskDeadline),
                continuation: continuation,
                answered: false,
                questions: questions,
                toolName: req.toolName,
                toolInput: req.toolInput,
                parentToolUseIdForCard: parentToolUseIdForCard,
                subAgentSummary: subAgentSummary,
                isFromSubAgent: isFromSubAgent
            )
            pendingRequests[requestId] = pending

            // 注意：不在此处 markHookPushed。原因（第二轮 Review 阻塞 #2）：
            //   ask 路径有可能因 timeout / cancelled 而最终走 SDK fallback
            //   （TUI 弹原问题让 Mac 用户答），此时 JSONL 落盘的 tool_use 才是
            //   "用户唯一可见的历史记录"，phone 离线回上线后必须能补拉看到。
            //   如果在 ask 注册时就 markHookPushed，会让 JSONLWatcher 误判跳过
            //   该记录，phone 永远看不到这次问答历史。
            //   正确时机：仅在 resolveAsk 成功（answered）路径中 mark。

            // 通知 Mac Card UI 显示卡片
            let cardData = AskCardRequestData(
                requestId: requestId,
                tabId: tabUUID,
                toolUseId: toolUseId,
                askKind: askKind,
                questions: questions,
                toolName: req.toolName,
                toolInput: req.toolInput
            )
            Task { [weak cardController] in
                await cardController?.show(request: cardData)
            }

            // ws 推 ask.question.pending（让 phone 端弹卡片）
            if let ws = wsClient {
                // R-F1-012：allow_other 默认 true
                // R-F4-004：tool_approval 类的 tool_input 截断到 500 字符（user_question 不截，
                // 因 questions 列表是结构化数据，已通过 parseQuestions 抽取）
                let outboundToolInput: AnyJSON?
                if askKind == "tool_approval", let ti = req.toolInput {
                    outboundToolInput = Self.truncateToolInput(ti, maxLen: 500)
                } else {
                    outboundToolInput = req.toolInput
                }
                let payload = AskQuestionPendingPayload(
                    requestId: requestId,
                    tabId: tabUUID.uuidString,
                    toolUseId: toolUseId,
                    askKind: askKind,
                    allowOther: true,
                    questions: questions,
                    toolName: req.toolName,
                    toolInput: outboundToolInput,
                    parentToolUseId: parentToolUseIdForCard,
                    subAgentSummary: subAgentSummary,
                    isFromSubAgent: isFromSubAgent
                )
                Task { @MainActor in
                    ws.sendAskQuestionPending(payload)
                }
            }
        }

        // 把响应写回 hook bridge socket（一行 JSON + \n）
        await Self.sendResponseAsk(connection: connection, response: response)
        connection.close()
    }

    // MARK: 内部：progress / notification

    private func handleProgressPre(req: HookIpcRequest, tabUUID: UUID, connection: IpcConn) async {
        let toolUseId = req.toolUseId ?? ""
        if !toolUseId.isEmpty {
            jsonlWatcher?.markHookPushed(toolUseId: toolUseId)
        }
        // PreToolUse (Bash/Write/Edit progress) = Claude 在执行工具 = 工作中
        reportActivity(tabUUID: tabUUID, activity: "working")
        if let ws = wsClient, let toolInput = req.toolInput {
            // R-F2-004：长字段截断 200 字符（带宽 + 隐私保护）
            let truncated = Self.truncateToolInput(toolInput, maxLen: 200)
            let payload = ToolProgressPrePayload(
                tabId: tabUUID.uuidString,
                toolUseId: toolUseId,
                toolName: req.toolName ?? "",
                toolInput: truncated
            )
            await MainActor.run { ws.sendToolProgressPre(payload) }
        }
        await Self.sendResponse(connection: connection, json: [:])
        connection.close()
    }

    private func handleProgressPost(req: HookIpcRequest, tabUUID: UUID, connection: IpcConn) async {
        let toolUseId = req.toolUseId ?? ""
        if !toolUseId.isEmpty {
            jsonlWatcher?.markHookPushed(toolUseId: toolUseId)
        }
        if let ws = wsClient {
            // 从 tool_response 中解析 success / error
            let (success, errorMsg) = parseToolResponse(req.toolResponse)
            let payload = ToolProgressPostPayload(
                tabId: tabUUID.uuidString,
                toolUseId: toolUseId,
                toolName: req.toolName ?? "",
                success: success,
                error: errorMsg
            )
            await MainActor.run { ws.sendToolProgressPost(payload) }
        }
        await Self.sendResponse(connection: connection, json: [:])
        connection.close()
    }

    private func handleNotification(req: HookIpcRequest, tabUUID: UUID, connection: IpcConn) async {
        let notifType = req.notificationType ?? "idle"
        if let ws = wsClient {
            let payload = NotificationPayload(
                tabId: tabUUID.uuidString,
                notificationType: notifType,
                title: req.title ?? "Claude",
                message: req.notification ?? ""
            )
            await MainActor.run { ws.sendNotification(payload) }
        }
        // idle notification = Claude 进入等待用户输入状态
        if notifType == "idle" {
            reportActivity(tabUUID: tabUUID, activity: "waiting")
        }
        await Self.sendResponse(connection: connection, json: [:])
        connection.close()
    }

    // MARK: 内部：JSON 解析辅助

    /// 从 tool_input 中解析 AskUserQuestion 的 questions 列表。
    /// AskUserQuestion 的 tool_input schema：
    ///   { "questions": [ { "question": "...", "header": "...",
    ///                       "multiSelect": false,
    ///                       "options": [ { "label": "...", "description": "..." } ] } ] }
    private func parseQuestions(from input: AnyJSON) -> [AskQuestionItem]? {
        guard case let .object(obj) = input else { return nil }
        guard case let .array(qs) = (obj["questions"] ?? .null) else { return nil }
        var result: [AskQuestionItem] = []
        for q in qs {
            guard case let .object(qObj) = q else { continue }
            let question = qObj["question"]?.asString ?? ""
            let header = qObj["header"]?.asString ?? ""
            var multiSelect = false
            if case let .bool(b) = (qObj["multiSelect"] ?? qObj["multi_select"] ?? .null) {
                multiSelect = b
            }
            var options: [AskQuestionOption] = []
            if case let .array(opts) = (qObj["options"] ?? .null) {
                for o in opts {
                    guard case let .object(oObj) = o else { continue }
                    let label = oObj["label"]?.asString ?? ""
                    let desc = oObj["description"]?.asString
                    options.append(AskQuestionOption(label: label, description: desc))
                }
            }
            result.append(AskQuestionItem(
                question: question,
                header: header,
                multiSelect: multiSelect,
                options: options
            ))
        }
        return result
    }

    /// R-F2-004 / R-F4-004：递归截断 tool_input 中的长字符串字段，
    /// 防止带宽浪费 + 隐私泄漏。仅截断 .string，对结构保留。
    /// 超出时尾部追加 `…` 标记被截断。
    static func truncateToolInput(_ input: AnyJSON, maxLen: Int) -> AnyJSON {
        switch input {
        case .string(let s):
            if s.count <= maxLen { return .string(s) }
            let cutIndex = s.index(s.startIndex, offsetBy: maxLen)
            return .string(String(s[..<cutIndex]) + "…")
        case .array(let arr):
            return .array(arr.map { truncateToolInput($0, maxLen: maxLen) })
        case .object(let obj):
            var result: [String: AnyJSON] = [:]
            for (k, v) in obj {
                result[k] = truncateToolInput(v, maxLen: maxLen)
            }
            return .object(result)
        default:
            return input
        }
    }

    /// 从 tool_response 中解析 success / error。
    /// 约定：tool_response 是个 dict；包含 `is_error: true` 或缺失 / false → success；
    /// 如果 `is_error == true`，从 `content` / `error` 中取错误消息。
    private func parseToolResponse(_ resp: AnyJSON?) -> (Bool, String?) {
        guard let resp = resp, case let .object(obj) = resp else {
            return (true, nil)
        }
        var isError = false
        if case let .bool(b) = (obj["is_error"] ?? .null) {
            isError = b
        }
        if !isError {
            return (true, nil)
        }
        // 取错误消息
        var errMsg: String? = nil
        if let s = obj["error"]?.asString {
            errMsg = s
        } else if let s = obj["content"]?.asString {
            errMsg = s
        }
        return (false, errMsg)
    }

    // MARK: 静态辅助：socket I/O

    /// 把 HookIpcResponseAsk 编码为一行 JSON + `\n` 写回。
    private static func sendResponseAsk(connection: IpcConn,
                                        response: HookIpcResponseAsk) async {
        do {
            var data = try JSONEncoder().encode(response)
            data.append(0x0A)
            await connection.sendData(data)
        } catch {
            AppLogger.shared.tagged("HookIpcServer").error("encode response failed: \(error)")
        }
    }

    /// 把任意 dict 编码为一行 JSON + `\n` 写回。
    private static func sendResponse(connection: IpcConn,
                                     json: [String: Any]) async {
        do {
            var data = try JSONSerialization.data(withJSONObject: json, options: [])
            data.append(0x0A)
            await connection.sendData(data)
        } catch {
            AppLogger.shared.tagged("HookIpcServer").error("encode response dict failed: \(error)")
        }
    }
}

// MARK: - 错误类型

public enum HookIpcServerError: Error, LocalizedError {
    case socketUnlinkFailed(String)
    case listenerInitFailed(String)
    case connectionClosed
    case frameTooLarge

    public var errorDescription: String? {
        switch self {
        case .socketUnlinkFailed(let s): return "socket unlink failed: \(s)"
        case .listenerInitFailed(let s): return "listener init failed: \(s)"
        case .connectionClosed: return "connection closed before line completed"
        case .frameTooLarge: return "frame exceeded 1MB without newline"
        }
    }
}
