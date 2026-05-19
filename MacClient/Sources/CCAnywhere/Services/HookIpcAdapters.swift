// Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.
//
// HookIpcAdapters.swift
// 把既有的 WSClient / TabManager 适配为 HookIpcServer 需要的窄接口
// （HookIpcWsSink / HookIpcTabRouter）。
//
// 设计要点：
// 1. WSClientHookIpcSink：把 HookIpcServer 推出的 Codable payload 包装成
//    ProtocolMessage envelope，通过 WSClient 现有 send API 发出。
//    HookIpcServer 在 actor 内部通过 `await MainActor.run { ... }` 调用本 sink，
//    保证 wsClient.send 始终在主线程上排队。
// 2. TabManagerHookIpcTabRouter：把 hook bridge 传来的 tab_id 字符串验证转换
//    为 UUID 并校验是否在 TabManager.tabs 内（R-F1-006）。HookIpcServer 在
//    accept loop 上同步调用本路由（非 MainActor），因此我们用线程安全的内部
//    snapshot：在 @MainActor 上订阅 TabManager.$tabs，把每次变化写入一个由
//    NSLock 保护的 UUID set；查询时拿锁读即可，纯同步、无 await。
//
// 这层 adapter 故意单独成文件，保持既有 WSClient / TabManager 实现零侵入。

import Foundation
import Combine

// MARK: - WSClientHookIpcSink

/// `HookIpcWsSink` 的 WSClient 适配器。
///
/// HookIpcServer 在收到 hook bridge 的事件后，通过本 sink 把对应协议消息
/// 推到 server，进而广播到所有手机端。所有方法都假定运行在 `@MainActor` 上，
/// 由 HookIpcServer 通过 `MainActor.run { ... }` 桥接。
@MainActor
public final class WSClientHookIpcSink: HookIpcWsSink {
    private weak var ws: WSClient?
    private let log = AppLogger.shared.tagged("HookIpcWsSink")

    public init(ws: WSClient) {
        self.ws = ws
    }

    public func sendAskQuestionPending(_ payload: AskQuestionPendingPayload) {
        sendEnvelope(type: "ask.question.pending", payload: payload)
    }

    public func sendAskQuestionAnswered(_ payload: AskQuestionAnsweredPayload) {
        sendEnvelope(type: "ask.question.answered", payload: payload)
    }

    public func sendAskQuestionTimeout(_ payload: AskQuestionTimeoutPayload) {
        sendEnvelope(type: "ask.question.timeout", payload: payload)
    }

    public func sendToolProgressPre(_ payload: ToolProgressPrePayload) {
        sendEnvelope(type: "tool.progress.pre", payload: payload)
    }

    public func sendToolProgressPost(_ payload: ToolProgressPostPayload) {
        sendEnvelope(type: "tool.progress.post", payload: payload)
    }

    public func sendNotification(_ payload: NotificationPayload) {
        sendEnvelope(type: "notification", payload: payload)
    }

    public func sendTabActivity(_ payload: TabActivityPayload) {
        sendEnvelope(type: "tab.activity", payload: payload)
    }

    func sendEnvelopePublic<P: Encodable>(type: String, payload: P) {
        sendEnvelope(type: type, payload: payload)
    }

    // MARK: - 私有

    /// 通用：把任意 Codable payload 编码成 AnyJSON，包入 ProtocolMessage envelope，
    /// 通过 WSClient.send 发送。编码失败仅写日志，不抛错（fire-and-forget）。
    private func sendEnvelope<P: Encodable>(type: String, payload: P) {
        guard let ws = ws else {
            log.warn("send \(type) dropped: ws client released")
            return
        }
        let any: AnyJSON?
        do {
            let data = try JSONEncoder().encode(payload)
            any = try JSONDecoder().decode(AnyJSON.self, from: data)
        } catch {
            log.error("encode \(type) failed: \(error)")
            return
        }
        log.info("ws push: type=\(type)")
        Task { @MainActor in
            await ws.send(ProtocolMessage(type: type, data: any))
        }
    }
}

// MARK: - TabManagerHookIpcTabRouter

/// `HookIpcTabRouter` 的 TabManager 适配器。
///
/// HookIpcServer 在 socket 入站回调上同步调用 `isActive` / `uuid(for:)`，
/// 调用线程并非 MainActor。直接读取 `@MainActor` 的 TabManager 会触发隔离
/// 校验失败。因此本类维护一个内部 snapshot（NSLock 保护），由 `start(...)`
/// 在 MainActor 上订阅 TabManager.$tabs，把每次变化写入 set；查询读锁即可。
public final class TabManagerHookIpcTabRouter: HookIpcTabRouter, @unchecked Sendable {
    private let lock = NSLock()
    /// 锁内独占访问。当前 TabManager 持有的所有 tab UUID。
    private var activeTabIds: Set<UUID> = []
    /// 锁内独占访问。每个 tab 当前的 permission mode rawValue 快照。
    /// 用 String 而非 PermissionMode 是为了让本类保持 Sendable（PermissionMode
    /// 已 Sendable 但 dictionary 转换有额外开销，rawValue 更轻）。
    private var permissionModes: [UUID: String] = [:]

    public init() {}

    /// 在 MainActor 上挂订阅；变更回写到 activeTabIds（线程安全）。
    /// 由 DependencyContainer.wireUp 在初始化时调用。
    @MainActor
    public func start(tabManager: TabManager,
                      storeIn bag: inout Set<AnyCancellable>) {
        // 立即同步一次当前值，避免订阅前的窗口期 hook 请求被误判为 unknown tab。
        replaceSnapshot(from: tabManager.tabs)

        tabManager.$tabs
            .sink { [weak self] tabs in
                self?.replaceSnapshot(from: tabs)
            }
            .store(in: &bag)
    }

    private func replaceSnapshot(from tabs: [Tab]) {
        var ids = Set<UUID>()
        var modes: [UUID: String] = [:]
        for t in tabs {
            ids.insert(t.id)
            modes[t.id] = t.permissionMode.rawValue
        }
        lock.lock()
        activeTabIds = ids
        permissionModes = modes
        lock.unlock()
    }

    public func isActive(tabIdString: String) -> Bool {
        guard let uuid = UUID(uuidString: tabIdString) else { return false }
        lock.lock()
        defer { lock.unlock() }
        return activeTabIds.contains(uuid)
    }

    public func uuid(forTabIdString s: String) -> UUID? {
        guard let uuid = UUID(uuidString: s) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return activeTabIds.contains(uuid) ? uuid : nil
    }

    public func permissionMode(forTabIdString s: String) -> String? {
        guard let uuid = UUID(uuidString: s) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return permissionModes[uuid]
    }
}

// MARK: - HookIpcActivityAdapter

/// `HookIpcActivitySink` 的 TabManager + WSClient 适配器。
///
/// HookIpcServer 在收到 PreToolUse / askKind / Notification idle 时调
/// `setActivity(tabId: activity:)`，本适配器：
///   1. 更新 TabManager 内的 Tab.activity（驱动 Mac UI 重绘）
///   2. 如果状态确实变化了 → 通过 ws 推 `tab.activity` 给 phone（增量推送）
@MainActor
public final class HookIpcActivityAdapter: HookIpcActivitySink {
    private let tabManager: TabManager
    private weak var ws: WSClientHookIpcSink?

    /// 每个 tab 的 idle 倒计时：working 持续 5 秒没新事件 → 自动转 waiting。
    /// 用 DispatchSourceTimer 而非 Timer.scheduledTimer — 后者默认走 RunLoop
    /// default mode，SwiftUI 在 menu / view rebuild 时会阻塞该 mode 导致 timer
    /// fire 被推迟，实测会让 idle 状态永远不切。
    private var idleTimers: [UUID: DispatchSourceTimer] = [:]
    /// idle 阈值（秒）。Claude 思考 + 工具调用之间一般 < 3s，5s 留 buffer。
    public static let idleTimeout: TimeInterval = 5

    public init(tabManager: TabManager, ws: WSClientHookIpcSink) {
        self.tabManager = tabManager
        self.ws = ws
    }

    public func setActivity(tabId: UUID, activity: String) {
        let act: ClaudeActivity = (activity == "working") ? .working : .waiting
        let changed = tabManager.setActivity(tabId, act)
        if changed {
            ws?.sendTabActivity(TabActivityPayload(tabId: tabId.uuidString, activity: act.rawValue))
        }

        // 清理任何残留 timer（无论新状态是 working 还是 waiting）
        idleTimers[tabId]?.cancel()
        idleTimers.removeValue(forKey: tabId)

        if act == .working {
            // working 状态下启动 5s 倒计时；到点自动切 waiting
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + Self.idleTimeout)
            timer.setEventHandler { [weak self, tabId] in
                self?.setActivity(tabId: tabId, activity: "waiting")
            }
            idleTimers[tabId] = timer
            timer.resume()
        }
    }
}
