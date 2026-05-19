// DependencyContainer.swift
// Wires up every service. Held by the SwiftUI App as a StateObject so they
// share a single instance for the lifetime of the process.

import Foundation
import SwiftUI
import Combine

@MainActor
public final class DependencyContainer: ObservableObject {
    public let preferences: PreferencesService
    public let hookPreferences: HookPreferencesService
    public let themeManager: ThemeManager
    public let pidTracker: PIDTracker
    public let tabManager: TabManager
    public let processHost: ProcessHost
    public let jsonlWatcher: JSONLWatcher
    public let wsClient: WSClient
    public let deviceManager: DeviceManager
    public let inputInjector: InputInjector
    public let tabSyncBridge: TabSyncBridge
    public let slashCommandBridge: SlashCommandBridge
    public let historyBridge: HistoryBridge
    public let fileViewerState: FileViewerState

    // MARK: - AskUserQuestion 远程交互（阶段七 wiring）

    /// hook bridge Python 脚本部署器；启动时把 bundle 内置脚本复制到
    /// `~/Library/Application Support/cc-anywhere/bin/`。
    public let hookBridgeDeployer: HookBridgeDeployer

    /// settings.json 安装/卸载入口；HookPane 通过 settingsJsonInstaller 字段调用。
    public let settingsJsonInstallerImpl: SettingsJsonInstaller

    /// Mac App 端 AskQuestionCard 控制器；视图通过 environmentObject 绑定。
    public let askCardController: AskQuestionCardController

    /// 把 WSClient 适配为 HookIpcWsSink（payload → ProtocolMessage envelope）。
    public let wsHookIpcSink: WSClientHookIpcSink
    public var hookActivitySink: HookIpcActivityAdapter?

    /// 把 TabManager 适配为 HookIpcTabRouter（线程安全 snapshot）。
    public let hookIpcTabRouter: TabManagerHookIpcTabRouter

    /// hook bridge ↔ Mac App 的 Unix domain socket 服务端。
    /// 启动时机由 AppDelegate 根据 hookPreferences.enableRemoteHook 决定。
    public let hookIpcServer: HookIpcServer

    /// HookPane 通过本字段拿到 SettingsJsonInstaller（HookInstaller protocol）。
    /// 早期为可空字段（T11 wiring 完成前），现 wiring 完成后恒非空。
    public var settingsJsonInstaller: HookInstaller? = nil

    private var cancellables = Set<AnyCancellable>()
    private let log = AppLogger.shared.tagged("Container")

    public init() {
        self.preferences = PreferencesService()
        self.hookPreferences = HookPreferencesService()
        self.themeManager = ThemeManager(pref: preferences)
        self.pidTracker = PIDTracker()
        self.tabManager = TabManager()
        self.processHost = ProcessHost(tabManager: tabManager, pidTracker: pidTracker)
        self.jsonlWatcher = JSONLWatcher()
        self.wsClient = WSClient()
        self.deviceManager = DeviceManager(ws: wsClient, pref: preferences)
        self.inputInjector = InputInjector(processHost: processHost, ws: wsClient)
        self.tabSyncBridge = TabSyncBridge(ws: wsClient, tabManager: tabManager)
        self.slashCommandBridge = SlashCommandBridge(ws: wsClient, tabManager: tabManager)
        self.historyBridge = HistoryBridge(ws: wsClient, tabManager: tabManager)
        self.fileViewerState = FileViewerState()

        // hook bridge / settings.json wiring
        let deployer = HookBridgeDeployer()
        self.hookBridgeDeployer = deployer
        self.settingsJsonInstallerImpl = SettingsJsonInstaller(
            hookBridgePath: deployer.deployedScriptURL
        )
        self.askCardController = AskQuestionCardController()
        self.wsHookIpcSink = WSClientHookIpcSink(ws: wsClient)
        self.hookIpcTabRouter = TabManagerHookIpcTabRouter()
        let socketURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("cc-anywhere/hook.sock")
        self.hookIpcServer = HookIpcServer(
            socketPath: socketURL,
            tabRouter: self.hookIpcTabRouter
        )

        // HookPane 已能通过 settingsJsonInstaller 字段拿到 installer 实例。
        self.settingsJsonInstaller = settingsJsonInstallerImpl

        // Reap any stale claude PIDs (R-M2-05) before doing anything else.
        pidTracker.reapStaleProcesses()

        wireUp()
    }

    private func wireUp() {
        // Bridge JSONLWatcher batches -> WS msg.stream + activity bump
        let bridge = MsgStreamBridge(ws: wsClient, tabManager: tabManager)
        jsonlWatcher.delegate = bridge
        self.msgStreamBridge = bridge

        // Process exit hook: surface to UI / tabManager already handled inside ProcessHost
        processHost.onProcessExited = { [weak self] tabId, code in
            self?.log.info("process exited tab=\(tabId) code=\(code ?? -1)")
        }

        // Let ProcessHost read the user-configured claude path override
        // without holding a strong reference to PreferencesService.
        processHost.claudePathProvider = { [weak preferences] in
            preferences?.claudePathOverride
        }

        // When a new tab is created, automatically start its watcher.
        tabManager.$tabs
            .removeDuplicates()
            .sink { [weak self] tabs in
                guard let self = self else { return }
                let knownTabIds = Set(tabs.map { $0.id })
                for tab in tabs where !self.jsonlWatcher.isWatching(tabId: tab.id) {
                    self.jsonlWatcher.watch(tab: tab)
                }
                self.jsonlWatcher.unwatchAllExcept(ids: knownTabIds)
            }
            .store(in: &cancellables)

        // HookIpcServer 用的 tab router snapshot：订阅 TabManager.tabs。
        hookIpcTabRouter.start(tabManager: tabManager, storeIn: &cancellables)

        // HookIpcServer 内部需要 ws / jsonl / card / activity 的弱引用。
        // 这些 setter 是 actor 方法，需要 await；用 Task 包装。
        let server = hookIpcServer
        let wsSink = wsHookIpcSink
        let jsonl: HookIpcJsonlSink = jsonlWatcher
        let card = askCardController
        let activitySink = HookIpcActivityAdapter(tabManager: tabManager, ws: wsHookIpcSink)
        self.hookActivitySink = activitySink
        // 同时把 activitySink 注入 JSONLWatcher 桥接器（JSONL 写入 → working）
        msgStreamBridge?.activitySink = activitySink
        Task {
            await server.setWsClient(wsSink)
            await server.setJsonlWatcher(jsonl)
            await server.setCardController(card)
            await server.setActivitySink(activitySink)
        }
        // AskCardController 反向持有 server 弱引用（用户提交时回调 actor）。
        askCardController.hookIpcServer = hookIpcServer

        // WSClient inbound：把 phone 端的 ask 回答路由进 HookIpcServer。
        // - `ask.question.answer`：user_question 分支（answers map）
        // - `ask.tool_approval.answer`：tool_approval 分支（decision + reason）
        //   TODO(phone-T13)：phone 端目前尚未实现 tool_approval UI，下游
        //   envelope 字段以本端期望为准；如 phone 团队最终选用别的字段名，
        //   需双方对齐后调整 AskQuestionAnswerPayload / 解析逻辑。
        wsClient.inbound
            .filter { $0.type == "ask.question.answer" }
            .sink { [weak self] msg in
                self?.handleAskAnswerInbound(msg)
            }
            .store(in: &cancellables)
        wsClient.inbound
            .filter { $0.type == "ask.tool_approval.answer" }
            .sink { [weak self] msg in
                self?.handleAskToolApprovalInbound(msg)
            }
            .store(in: &cancellables)

        // phone 重连 / 新 phone 上线时（phoneCount 增加），重发所有未答 pending ask
        // 给 phone — 解决用户场景：phone 端 ask 未答时退出 App 重开后看不到 pending 卡片。
        wsClient.$phoneCount
            .removeDuplicates()
            .scan((prev: 0, curr: 0)) { ($0.curr, $1) }
            .filter { $0.curr > $0.prev }
            .sink { [weak self] _ in
                guard let self = self else { return }
                let server = self.hookIpcServer
                Task { await server.republishPendingToPhone() }
            }
            .store(in: &cancellables)
    }

    /// 把 ws 进来的 `ask.question.answer` 投递到 HookIpcServer.actor。
    /// 注：phone 端 envelope 里不带 sender 信息，answeredBy 一律标 "phone"
    /// 占位（足够 UI / 日志区分本机 vs 远端）。
    private func handleAskAnswerInbound(_ msg: ProtocolMessage) {
        guard let data = msg.data,
              let payload = decode(data, AskQuestionAnswerPayload.self) else {
            log.warn("malformed ask.question.answer")
            return
        }
        let server = hookIpcServer
        Task {
            await server.receiveAnswerFromWs(
                requestId: payload.requestId,
                answers: payload.answers,
                answeredBy: "phone"
            )
        }
    }

    /// phone 端 tool_approval 回复。envelope 暂定 schema：
    ///   { "request_id": "...", "decision": "allow"|"deny", "reason": "..." }
    /// 解析为本地 dict 后转发给 HookIpcServer.receiveApprovalFromWs。
    private func handleAskToolApprovalInbound(_ msg: ProtocolMessage) {
        guard let data = msg.data, case .object(let obj) = data else {
            log.warn("malformed ask.tool_approval.answer (not object)")
            return
        }
        guard let requestId = obj["request_id"]?.asString,
              let decision = obj["decision"]?.asString else {
            log.warn("ask.tool_approval.answer missing request_id/decision")
            return
        }
        let reason = obj["reason"]?.asString
        let server = hookIpcServer
        Task {
            await server.receiveApprovalFromWs(
                requestId: requestId,
                decision: decision,
                reason: reason,
                answeredBy: "phone"
            )
        }
    }

    private var msgStreamBridge: MsgStreamBridge?

    /// Called at the moment the app finished launching: restore all tabs.
    public func appDidFinishLaunching() {
        log.info("appDidFinishLaunching: restoring \(tabManager.tabs.count) tab(s)")
        for tab in tabManager.tabs {
            processHost.startProcess(for: tab)
            jsonlWatcher.watch(tab: tab)
        }
        // 自动选中第一个 tab（否则 MainWindow 会停在 EmptyStateView，
        // 即使 tabs.json 里有 tab 也"看起来工作区没打开"）
        if tabManager.selectedTabId == nil, let first = tabManager.tabs.first {
            tabManager.selectedTabId = first.id
            log.info("auto-selected first tab: \(first.name)")
        }
        // Connect to Server if configured.
        let cfg = preferences.serverConfig
        if cfg.isUsable {
            wsClient.connect(config: cfg)
        } else {
            log.info("Server config incomplete; skipping initial connect.")
        }
        Task { await ImageDownloader.shared.purgeOldFiles() }
    }

    /// Called right before NSApplication terminates.
    public func appWillTerminate() {
        log.info("appWillTerminate: stopping processes")
        wsClient.disconnect()
        processHost.stopAll()
        jsonlWatcher.unwatchAll()
        // HookIpcServer 也要停（清理 socket 文件 + cancel pending）。
        // 进程即将退出，best-effort，不阻塞。
        let server = hookIpcServer
        Task.detached { await server.stop() }
    }
}

// MARK: - JSONL -> WS bridge

private final class MsgStreamBridge: JSONLWatcherDelegate {
    let ws: WSClient
    let tabManager: TabManager
    /// 弱引用：JSONL 写入时上报 activity = working（Claude 在产出内容）。
    /// Notification idle hook 那一侧负责 → waiting。
    weak var activitySink: HookIpcActivityAdapter?

    init(ws: WSClient, tabManager: TabManager) {
        self.ws = ws
        self.tabManager = tabManager
    }

    func watcher(_ watcher: JSONLWatcher, didReceive batch: [ParsedMessage], for tabId: UUID) {
        // Convert ParsedMessage[] -> array of raw JSON objects.
        // R-F2-002/003：对 isSidechain=true 的消息，若已建立 agentId →
        // parentToolUseId 映射，则在 AnyJSON.object 上注入 parent_tool_use_id
        // 字段，让 phone 端 ChatRepository 直接按该字段聚合，不必再做匹配。
        let array: [AnyJSON] = batch.map { msg in
            guard let data = msg.raw.data(using: .utf8),
                  let any = try? JSONDecoder().decode(AnyJSON.self, from: data) else {
                return .object(["type": .string("raw"), "raw": .string(msg.raw)])
            }
            return Self.injectParentToolUseId(any, watcher: watcher, tabId: tabId)
        }
        let payload: AnyJSON = .object([
            "tab_id": .string(tabId.uuidString),
            "messages": .array(array)
        ])
        Task { @MainActor [weak activitySink] in
            await ws.send(ProtocolMessage(type: "msg.stream", data: payload))
            tabManager.bumpActivity(tabId)
            // Claude 在写 JSONL = 在产出内容 = working。
            // 比 PreToolUse hook 覆盖更广（纯文本思考也算 working）。
            activitySink?.setActivity(tabId: tabId, activity: "working")
        }
    }

    /// R-F2-002：若消息 isSidechain=true 且 agentId 在 watcher.activeSubAgents
    /// 中已建立 parentToolUseId 映射 → 注入到 AnyJSON。
    /// 注：JSONL 原生 record 已带 sessionId / parentUuid / isSidechain；只补
    /// parentToolUseId 这个"两阶段匹配派生字段"即可。
    private static func injectParentToolUseId(_ any: AnyJSON,
                                              watcher: JSONLWatcher,
                                              tabId: UUID) -> AnyJSON {
        guard case .object(var obj) = any else { return any }
        // 必须是 sidechain 才注入；非 sidechain 消息不携带 parent_tool_use_id。
        guard case .bool(true) = (obj["isSidechain"] ?? .null) else { return any }
        guard case .string(let agentId) = (obj["agentId"] ?? .null) else { return any }
        // 已注入过的不重复（防御性：JSONL record 通常没这字段，但兜底无害）
        if case .string = obj["parent_tool_use_id"] { return any }
        // delegate 回调由 throttle 的 queue.asyncAfter 派发，已经在 watcher.queue 上执行
        // → 必须用 *Locked 版本读取，避免 queue.sync 自我死锁（第一轮 review 阻塞 #1）。
        guard let parentId = watcher.parentToolUseIdLocked(tabId: tabId, agentId: agentId) else {
            return any
        }
        obj["parent_tool_use_id"] = .string(parentId)
        return .object(obj)
    }
}
