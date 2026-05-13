// TabManager.swift
// Owns the Tab model list and persistence (tabs.json).
// See 需求规格说明书 §3.1 M1 + 技术实施文档 §4.1.

import Foundation
import SwiftUI

@MainActor
public final class TabManager: ObservableObject {
    private let log = AppLogger.shared.tagged("TabManager")

    @Published public private(set) var tabs: [Tab] = []
    @Published public var selectedTabId: UUID? = nil

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
    }

    public func updateStatus(_ id: UUID, status: TabStatus, exitCode: Int32? = nil) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[idx].status = status
        tabs[idx].exitCode = exitCode
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

    public func makeTabListPayload() -> TabListPayload {
        let summaries = tabs.map { t in
            TabSummary(
                id: t.id.uuidString,
                name: t.name,
                folder: t.folder.path,
                claudeStatus: t.status.rawValue,
                lastActivityAt: t.lastActivityAt.map { ISO8601DateFormatter().string(from: $0) }
            )
        }
        return TabListPayload(tabs: summaries)
    }
}
