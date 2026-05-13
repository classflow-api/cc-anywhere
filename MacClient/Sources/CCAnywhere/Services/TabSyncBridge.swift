// TabSyncBridge.swift
// Pushes Tab list state to Server so phones can render & refresh the list.
// Responsibilities:
//   1. On WS connected, send the current `tab.list`.
//   2. On any structural TabManager change (added/removed/renamed),
//      send `tab.changed` so phones update in real time.
//   3. On inbound `tab.list.request` from a phone, reply with `tab.list.response`.
//
// See 需求规格说明书 §3.4 4.3.

import Foundation
import Combine

@MainActor
public final class TabSyncBridge {
    private let log = AppLogger.shared.tagged("TabSyncBridge")
    private weak var ws: WSClient?
    private weak var tabManager: TabManager?
    private var cancellables = Set<AnyCancellable>()

    public init(ws: WSClient, tabManager: TabManager) {
        self.ws = ws
        self.tabManager = tabManager

        // Push full list whenever the connection becomes connected.
        ws.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self = self else { return }
                if case .connected = state {
                    Task { await self.sendFullList() }
                }
            }
            .store(in: &cancellables)

        // Push tab.changed on structural mutations.
        tabManager.changes
            .sink { [weak self] event in
                guard let self = self else { return }
                Task { await self.sendTabChanged(event) }
            }
            .store(in: &cancellables)

        // Respond to tab.list.request from phones.
        ws.inbound
            .filter { $0.type == "tab.list.request" }
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task { await self.sendFullList(asResponse: true) }
            }
            .store(in: &cancellables)
    }

    /// Send the entire Tab list to Server (broadcast to phones).
    /// - Parameter asResponse: When true, use `tab.list.response` (reply to
    ///   an explicit pull); otherwise use `tab.list` (proactive push).
    public func sendFullList(asResponse: Bool = false) async {
        guard let ws = ws, let tabManager = tabManager else { return }
        let payload = tabManager.makeTabListPayload()
        let any = encodePayload(payload)
        let type = asResponse ? "tab.list.response" : "tab.list"
        await ws.send(ProtocolMessage(type: type, data: any))
        log.info("sent \(type) (\(payload.tabs.count) tabs)")
    }

    private func sendTabChanged(_ event: TabChangeEvent) async {
        guard let ws = ws, let tabManager = tabManager else { return }
        let summary: TabSummary
        let action: String
        switch event {
        case .added(let t):   summary = tabManager.summary(of: t); action = "added"
        case .removed(let t): summary = tabManager.summary(of: t); action = "removed"
        case .renamed(let t): summary = tabManager.summary(of: t); action = "renamed"
        }
        let payload = TabChangedPayload(tab: summary, action: action)
        let any = encodePayload(payload)
        await ws.send(ProtocolMessage(type: "tab.changed", data: any))
        log.info("sent tab.changed action=\(action) tab=\(summary.id)")
    }

    private func encodePayload<T: Encodable>(_ p: T) -> AnyJSON? {
        guard let data = try? JSONEncoder().encode(p) else { return nil }
        return try? JSONDecoder().decode(AnyJSON.self, from: data)
    }
}
