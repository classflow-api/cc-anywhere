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

    public func createTab(folder: URL,
                          name: String,
                          permissionMode: PermissionMode = .default) throws -> Tab {
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
        let tab = Tab(folder: normalized, name: safeName, permissionMode: permissionMode)
        tabs.append(tab)
        selectedTabId = tab.id
        try persist()
        log.info("created tab \(tab.name) folder=\(normalized.path) mode=\(permissionMode.rawValue)")
        changes.send(.added(tab))
        return tab
    }

    /// 修改 Tab 的 permission mode。仅写入并持久化；**不**主动重启 claude 子进程
    /// —— 调用方（SidebarView / TabStripView）拿到返回值后自行决定是否
    /// `ProcessHost.stopProcess + startProcess`。这样耦合最少。
    /// 返回新 Tab 快照（也用于触发 ws 同步）。失败（id 不存在 / mode 相同 / 持久化失败）返回 nil。
    @discardableResult
    public func setPermissionMode(_ id: UUID, _ mode: PermissionMode) -> Tab? {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        guard tabs[idx].permissionMode != mode else { return nil }
        tabs[idx].permissionMode = mode
        do {
            try persist()
        } catch {
            log.error("persist failed after setPermissionMode: \(error)")
            return nil
        }
        // bypassPermissions / dontAsk 是高危 / 锁定场景，提级到 warn 留可见痕迹
        if mode == .bypassPermissions || mode == .dontAsk {
            log.warn("permission mode → \(mode.rawValue) (tab=\(id)) — elevated mode, ensure intent")
        } else {
            log.info("permission mode → \(mode.rawValue) (tab=\(id))")
        }
        // 复用 .renamed 事件让 ws TabSyncBridge 把更新过的 Tab 广播给手机
        changes.send(.renamed(tabs[idx]))
        return tabs[idx]
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

    /// 重命名 Tab。规则：
    /// - 输入 trim 前后空白；
    /// - trim 后为空 → 视为"重置为默认名"，使用 folder.lastPathComponent；
    /// - trim 后超过 40 字符 → 截断到 40（不抛错，保证用户操作不被打断）。
    /// 调用方仍可用 try? 调用：当前实现实际上从不 throw，保留 throws 是为不破坏现有签名。
    public func renameTab(_ id: UUID, to newName: String) throws {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        // 先把中间的换行/回车折成空格，再 trim 前后空白。避免用户粘贴带 \n 的名字
        // 撑爆侧栏 / 手机端 UI（侧栏 lineLimit(1) 不一定能 100% 防住所有 Unicode 行分隔）。
        let normalized = newName
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved: String
        if trimmed.isEmpty {
            resolved = tabs[idx].folder.lastPathComponent
        } else if trimmed.count > 40 {
            resolved = String(trimmed.prefix(40))
        } else {
            resolved = trimmed
        }
        guard tabs[idx].name != resolved else { return }
        tabs[idx].name = resolved
        try persist()
        log.info("renamed tab to \(resolved)")
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

    /// 设置该 Tab 内 Claude 的活动状态（working / waiting）。
    /// 由 hook 桥接（PreToolUse → working / Notification idle → waiting）驱动。
    /// 返回值：true 表示状态真发生了变化（caller 可据此决定要不要 ws 推 phone）。
    @discardableResult
    public func setActivity(_ id: UUID, _ activity: ClaudeActivity) -> Bool {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return false }
        guard tabs[idx].activity != activity else { return false }
        tabs[idx].activity = activity
        return true
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
        // 先尝试整体解码（fast path）；失败则降级为逐条解码 —— 这样单个 Tab 的
        // 损坏（比如未来某字段类型变更 / 外部编辑器把 mode 写成 number）不会让
        // 整个工作区列表丢失。
        if let decoded = try? JSONDecoder.iso.decode([Tab].self, from: data) {
            self.tabs = decoded
            self.selectedTabId = tabs.first?.id
            log.info("loaded \(decoded.count) tab(s) from disk")
            return
        }
        log.warn("tabs.json full decode failed; falling back to per-row decode")
        if let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            var rescued: [Tab] = []
            for raw in array {
                guard let rowData = try? JSONSerialization.data(withJSONObject: raw) else { continue }
                if let one = try? JSONDecoder.iso.decode(Tab.self, from: rowData) {
                    rescued.append(one)
                } else {
                    log.warn("dropping malformed tab row: \(raw)")
                }
            }
            self.tabs = rescued
            self.selectedTabId = tabs.first?.id
            log.info("rescued \(rescued.count) tab(s) from per-row decode")
        } else {
            log.error("tabs.json corrupted beyond rescue; starting empty")
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
