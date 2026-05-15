// DependencyContainer.swift
// Wires up every service. Held by the SwiftUI App as a StateObject so they
// share a single instance for the lifetime of the process.

import Foundation
import SwiftUI
import Combine

@MainActor
public final class DependencyContainer: ObservableObject {
    public let preferences: PreferencesService
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

    private var cancellables = Set<AnyCancellable>()
    private let log = AppLogger.shared.tagged("Container")

    public init() {
        self.preferences = PreferencesService()
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
    }
}

// MARK: - JSONL -> WS bridge

private final class MsgStreamBridge: JSONLWatcherDelegate {
    let ws: WSClient
    let tabManager: TabManager
    init(ws: WSClient, tabManager: TabManager) {
        self.ws = ws
        self.tabManager = tabManager
    }

    func watcher(_ watcher: JSONLWatcher, didReceive batch: [ParsedMessage], for tabId: UUID) {
        // Convert ParsedMessage[] -> array of raw JSON objects.
        let array: [AnyJSON] = batch.map { msg in
            if let data = msg.raw.data(using: .utf8),
               let any = try? JSONDecoder().decode(AnyJSON.self, from: data) {
                return any
            }
            return .object(["type": .string("raw"), "raw": .string(msg.raw)])
        }
        let payload: AnyJSON = .object([
            "tab_id": .string(tabId.uuidString),
            "messages": .array(array)
        ])
        Task { @MainActor in
            await ws.send(ProtocolMessage(type: "msg.stream", data: payload))
            tabManager.bumpActivity(tabId)
        }
    }
}

