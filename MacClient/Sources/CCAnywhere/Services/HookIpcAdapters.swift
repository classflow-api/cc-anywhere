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

    public init() {}

    /// 在 MainActor 上挂订阅；变更回写到 activeTabIds（线程安全）。
    /// 由 DependencyContainer.wireUp 在初始化时调用。
    @MainActor
    public func start(tabManager: TabManager,
                      storeIn bag: inout Set<AnyCancellable>) {
        // 立即同步一次当前值，避免订阅前的窗口期 hook 请求被误判为 unknown tab。
        let initial = Set(tabManager.tabs.map { $0.id })
        replace(with: initial)

        tabManager.$tabs
            .map { Set($0.map { $0.id }) }
            .removeDuplicates()
            .sink { [weak self] ids in
                self?.replace(with: ids)
            }
            .store(in: &bag)
    }

    private func replace(with ids: Set<UUID>) {
        lock.lock()
        activeTabIds = ids
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
}
