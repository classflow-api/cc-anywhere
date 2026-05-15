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
import Network

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

    private let tabRouter: HookIpcTabRouter

    // MARK: 内部状态

    private var pendingRequests: [String: PendingAskRequest] = [:]
    private var listener: NWListener?
    private var reapTimer: Task<Void, Never>?
    private var running: Bool = false

    /// 默认 ask 请求超时 5 分钟。
    public static let defaultAskDeadline: TimeInterval = 5 * 60
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

    public func isRunning() -> Bool { running }

    /// 启动 NWListener + reapTimer。
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
            do {
                try FileManager.default.removeItem(atPath: path)
                log.info("removed stale socket at \(path)")
            } catch {
                log.error("failed to remove stale socket: \(error)")
                throw HookIpcServerError.socketUnlinkFailed(error.localizedDescription)
            }
        }

        // 创建 NWListener 监听 Unix domain socket
        let params = NWParameters()
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.unix(path: path)

        let listener: NWListener
        do {
            listener = try NWListener(using: params)
        } catch {
            log.error("NWListener init failed: \(error)")
            throw HookIpcServerError.listenerInitFailed(error.localizedDescription)
        }

        // accept loop（每个连接独立 Task）
        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self else {
                connection.cancel()
                return
            }
            Task { await self.handleConnection(connection) }
        }

        listener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            Task { await self.handleListenerState(state) }
        }

        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
        self.running = true

        // chmod 0600 — NWListener 创建出 socket 文件后立即 chmod。
        // 注意：bind 是异步的，文件可能尚未存在。我们 spawn 一个 Task 轮询若干次。
        Task { [path, log] in
            for _ in 0..<20 {
                if FileManager.default.fileExists(atPath: path) {
                    do {
                        try FileManager.default.setAttributes(
                            [.posixPermissions: NSNumber(value: 0o600)],
                            ofItemAtPath: path
                        )
                        log.info("socket chmod 0600 applied at \(path)")
                    } catch {
                        log.error("chmod failed: \(error)")
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            log.warn("socket file did not appear within 2s for chmod")
        }

        // reap timer
        reapTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.reapInterval) * 1_000_000_000)
                if Task.isCancelled { break }
                await self?.reapExpired()
            }
        }

        log.info("HookIpcServer started at \(path)")
    }

    /// 停止 listener，清理 pending requests（全部 resolve 为 cancelled），删除 socket 文件。
    public func stop() async {
        guard running else { return }
        running = false

        reapTimer?.cancel()
        reapTimer = nil

        listener?.cancel()
        listener = nil

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

    // MARK: 内部：listener 状态

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            log.info("listener ready")
        case .failed(let error):
            log.error("listener failed: \(error)")
            running = false
        case .cancelled:
            log.info("listener cancelled")
            running = false
        default:
            log.debug("listener state=\(state)")
        }
    }

    // MARK: 内部：连接处理

    /// 处理一个 hook bridge 进来的连接：
    /// 1. 读 line-delimited JSON
    /// 2. 反序列化 HookIpcRequest
    /// 3. 根据 kind 路由：ask 阻塞等待 / progress|notification 立即 reply `{}`
    private func handleConnection(_ connection: NWConnection) async {
        connection.start(queue: .global(qos: .userInitiated))

        // 读一帧（直到 `\n` 为止）
        let reqLineData: Data
        do {
            reqLineData = try await Self.readLine(from: connection)
        } catch {
            log.warn("read request line failed: \(error)")
            connection.cancel()
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
            connection.cancel()
            return
        }

        // 校验 tab_id（R-F1-006）
        // NFR-U1/U2：tab 路由失败属系统级错误（非用户决策），按"软失败"返回空对象，
        // 让 SDK 走 fallback；不返回 error，避免 hook bridge 翻译为 deny 误拦工具调用。
        guard tabRouter.isActive(tabIdString: req.tabId),
              let tabUUID = tabRouter.uuid(forTabIdString: req.tabId) else {
            log.warn("unknown tab_id=\(req.tabId), kind=\(req.kind); soft-fail")
            await Self.sendResponse(connection: connection, json: [:])
            connection.cancel()
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
            connection.cancel()
        }
    }

    // MARK: 内部：ask 处理

    private func handleAsk(req: HookIpcRequest, tabUUID: UUID, connection: NWConnection) async {
        let requestId = UUID().uuidString  // R-F1-015
        let toolUseId = req.toolUseId ?? ""
        let toolName = req.toolName ?? ""

        // 判定 askKind：AskUserQuestion → user_question；其它 → tool_approval
        let askKind: String = (toolName == "AskUserQuestion") ? "user_question" : "tool_approval"

        // 解析 questions（如果是 user_question）
        var questions: [AskQuestionItem]? = nil
        if askKind == "user_question", let toolInput = req.toolInput {
            questions = parseQuestions(from: toolInput)
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
                answered: false
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
                    toolInput: outboundToolInput
                )
                Task { @MainActor in
                    ws.sendAskQuestionPending(payload)
                }
            }
        }

        // 把响应写回 hook bridge socket（一行 JSON + \n）
        await Self.sendResponseAsk(connection: connection, response: response)
        connection.cancel()
    }

    // MARK: 内部：progress / notification

    private func handleProgressPre(req: HookIpcRequest, tabUUID: UUID, connection: NWConnection) async {
        let toolUseId = req.toolUseId ?? ""
        if !toolUseId.isEmpty {
            jsonlWatcher?.markHookPushed(toolUseId: toolUseId)
        }
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
        connection.cancel()
    }

    private func handleProgressPost(req: HookIpcRequest, tabUUID: UUID, connection: NWConnection) async {
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
        connection.cancel()
    }

    private func handleNotification(req: HookIpcRequest, tabUUID: UUID, connection: NWConnection) async {
        if let ws = wsClient {
            let payload = NotificationPayload(
                tabId: tabUUID.uuidString,
                notificationType: req.notificationType ?? "idle",
                title: req.title ?? "Claude",
                message: req.notification ?? ""
            )
            await MainActor.run { ws.sendNotification(payload) }
        }
        await Self.sendResponse(connection: connection, json: [:])
        connection.cancel()
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

    /// 从 NWConnection 读一帧（直到 `\n`，最大 1MB）。
    private static func readLine(from connection: NWConnection) async throws -> Data {
        // 简单循环读，直到遇到 \n 或连接断开。
        var buf = Data()
        let maxLen = 1024 * 1024
        while buf.count < maxLen {
            let chunk: Data? = try await withCheckedThrowingContinuation { cont in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                    if let error = error {
                        cont.resume(throwing: error)
                        return
                    }
                    if let data = data, !data.isEmpty {
                        cont.resume(returning: data)
                        return
                    }
                    if isComplete {
                        cont.resume(returning: nil)
                        return
                    }
                    cont.resume(returning: Data())
                }
            }
            guard let chunk = chunk else {
                // 连接已关闭
                if buf.isEmpty {
                    throw HookIpcServerError.connectionClosed
                }
                return buf
            }
            buf.append(chunk)
            if let nl = chunk.firstIndex(of: 0x0A) {
                // 找到 \n。截到 \n 之前。
                let bufNLIdx = buf.count - (chunk.count - nl)
                return buf.prefix(bufNLIdx)
            }
        }
        throw HookIpcServerError.frameTooLarge
    }

    /// 把 HookIpcResponseAsk 编码为一行 JSON + `\n` 写回。
    private static func sendResponseAsk(connection: NWConnection,
                                        response: HookIpcResponseAsk) async {
        do {
            var data = try JSONEncoder().encode(response)
            data.append(0x0A)
            await sendData(connection: connection, data: data)
        } catch {
            AppLogger.shared.tagged("HookIpcServer").error("encode response failed: \(error)")
        }
    }

    /// 把任意 dict 编码为一行 JSON + `\n` 写回。
    private static func sendResponse(connection: NWConnection,
                                     json: [String: Any]) async {
        do {
            var data = try JSONSerialization.data(withJSONObject: json, options: [])
            data.append(0x0A)
            await sendData(connection: connection, data: data)
        } catch {
            AppLogger.shared.tagged("HookIpcServer").error("encode response dict failed: \(error)")
        }
    }

    private static func sendData(connection: NWConnection, data: Data) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            connection.send(content: data, completion: .contentProcessed { _ in
                cont.resume()
            })
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
