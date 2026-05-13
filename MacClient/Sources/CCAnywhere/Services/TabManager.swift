// TabManager.swift
// Owns the Tab model list and persistence (tabs.json).
// See 需求规格说明书 §3.1 M1 + 技术实施文档 §4.1.

import Foundation
import SwiftUI
import Combine

/// Lifecycle events emitted whenever the Tab list mutates. Consumers
/// (e.g. WS bridge) translate these into `tab.changed` envelopes.
public enum TabChangeEvent: Sendable {
    case added(Tab)
    case removed(Tab)
    case renamed(Tab)
}

@MainActor
public final class TabManager: ObservableObject {
    private let log = AppLogger.shared.tagged("TabManager")

    @Published public private(set) var tabs: [Tab] = []
    @Published public var selectedTabId: UUID? = nil

    /// Hot stream of structural change events. Subscribers push `tab.changed`
    /// envelopes to the Server so phones can update their list in real time.
    public let changes = PassthroughSubject<TabChangeEvent, Never>()

    private var storeURL: URL {
        PreferencesService.appSupportDir.appendingPathComponent("tabs.json")
    }

    public init() {
        loadFromDisk()
    }

    // MARK: - CRUD

    public func createTab(folder: URL, name: String) throws -> Tab {
        let normalized = folder.standardizedFileURL
        // Validate not duplicate
        if tabs.contains(where: { $0.folder.standardizedFileURL.path == normalized.path }) {
            throw TabError.folderAlreadyOpen(normalized)
        }
        var exists = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: normalized.path, isDirectory: &exists),
              exists.boolValue else {
            throw TabError.folderNotExists(normalized)
        }
        let safeName: String
        if name.isEmpty {
            safeName = normalized.lastPathComponent
        } else if name.count > 50 {
            throw TabError.nameTooLong
        } else {
            safeName = name
        }
        let tab = Tab(folder: normalized, name: safeName)
        tabs.append(tab)
        selectedTabId = tab.id
        try persist()
        log.info("created tab \(tab.name) folder=\(normalized.path)")
        changes.send(.added(tab))
        return tab
    }

    public func removeTab(_ id: UUID) throws {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let removed = tabs.remove(at: idx)
        if selectedTabId == id {
            selectedTabId = tabs.first?.id
        }
        try persist()
        log.info("removed tab \(removed.name)")
        changes.send(.removed(removed))
    }

    public func renameTab(_ id: UUID, to newName: String) throws {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let safe = newName.isEmpty
            ? tabs[idx].folder.lastPathComponent
            : newName
        if safe.count > 50 { throw TabError.nameTooLong }
        tabs[idx].name = safe
        try persist()
        log.info("renamed tab to \(safe)")
        changes.send(.renamed(tabs[idx]))
    }

    public func updateStatus(_ id: UUID,
                             status: TabStatus,
                             exitCode: Int32? = nil,
                             errorReason: String? = nil) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[idx].status = status
        tabs[idx].exitCode = exitCode
        // Clear stale reason whenever we leave the error state; preserve it
        // when caller didn't supply one but we're still in error.
        if status != .error {
            tabs[idx].errorReason = nil
        } else if errorReason != nil {
            tabs[idx].errorReason = errorReason
        }
    }

    public func bumpActivity(_ id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[idx].lastActivityAt = Date()
        if selectedTabId != id {
            tabs[idx].unread += 1
        }
    }

    public func clearUnread(_ id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[idx].unread = 0
    }

    public func tab(by id: UUID) -> Tab? {
        tabs.first { $0.id == id }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        do {
            let decoded = try JSONDecoder.iso.decode([Tab].self, from: data)
            self.tabs = decoded
            self.selectedTabId = tabs.first?.id
            log.info("loaded \(decoded.count) tab(s) from disk")
        } catch {
            log.error("failed to decode tabs.json: \(error). Starting empty.")
            self.tabs = []
        }
    }

    private func persist() throws {
        do {
            let data = try JSONEncoder.pretty.encode(tabs)
            try data.atomicWrite(to: storeURL, permissions: 0o600)
        } catch {
            throw TabError.fileSystem(error)
        }
    }

    // MARK: - WebSocket projection

    public func summary(of tab: Tab) -> TabSummary {
        TabSummary(
            id: tab.id.uuidString,
            name: tab.name,
            folder: tab.folder.path,
            claudeStatus: tab.status.rawValue,
            lastActivityAt: tab.lastActivityAt.map { ISO8601DateFormatter().string(from: $0) }
        )
    }

    public func makeTabListPayload() -> TabListPayload {
        TabListPayload(tabs: tabs.map(summary(of:)))
    }
}
