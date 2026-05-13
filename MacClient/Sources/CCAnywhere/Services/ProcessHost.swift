// ProcessHost.swift
// Owns one LocalProcessTerminalView per Tab. Each Tab gets its own PTY +
// claude subprocess. See 需求规格说明书 §3.1 M2/M3 + 技术实施文档 §4.2.

import Foundation
import AppKit
import SwiftTerm

@MainActor
public final class ProcessHost: NSObject, ObservableObject {
    private let log = AppLogger.shared.tagged("ProcessHost")
    private weak var tabManager: TabManager?
    private let pidTracker: PIDTracker

    /// Mapping tabId -> SwiftTerm view (one per Tab, persisted across selections).
    @Published public private(set) var terminalsByTab: [UUID: LocalProcessTerminalView] = [:]

    /// Callback invoked when a Tab's process unexpectedly terminates.
    public var onProcessExited: (@MainActor (UUID, Int32?) -> Void)?

    public init(tabManager: TabManager, pidTracker: PIDTracker) {
        self.tabManager = tabManager
        self.pidTracker = pidTracker
    }

    // MARK: - Lifecycle

    /// Start (or recreate) a terminal view for the given Tab.
    public func startProcess(for tab: Tab) {
        if terminalsByTab[tab.id] != nil { return }   // already running
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = self
        // wire up callbacks via the LocalProcessTerminalViewDelegate; we'll
        // identify tabs by the view itself, mapped via reverse lookup.
        view.identifier = NSUserInterfaceItemIdentifier(tab.id.uuidString)

        // Look up the claude binary
        let exe = Self.findClaudeBinary()
        let env = makeEnvironment()

        view.feed(text: "\u{1B}[36m[cc-anywhere] launching: \(exe) -c\nin: \(tab.folder.path)\u{1B}[0m\r\n")

        view.startProcess(
            executable: exe,
            args: ["-c"],
            environment: env,
            execName: "claude",
            currentDirectory: tab.folder.path
        )
        terminalsByTab[tab.id] = view
        tabManager?.updateStatus(tab.id, status: .running)
        if view.process.shellPid > 0 {
            pidTracker.track(tabId: tab.id, pid: view.process.shellPid)
        }
        log.info("startProcess tab=\(tab.id) pid=\(view.process.shellPid) cwd=\(tab.folder.path)")
    }

    /// Stop a Tab's process gracefully (SIGTERM) and forget the view.
    public func stopProcess(for tabId: UUID) {
        guard let view = terminalsByTab[tabId] else { return }
        view.terminate()
        terminalsByTab.removeValue(forKey: tabId)
        pidTracker.untrack(tabId: tabId)
        tabManager?.updateStatus(tabId, status: .idle)
        log.info("stopProcess tab=\(tabId)")
    }

    /// Stop every Tab; called on app quit. Wait 500ms then SIGKILL leftovers.
    public func stopAll() {
        log.info("stopAll: terminating \(terminalsByTab.count) processes")
        for view in terminalsByTab.values {
            view.terminate()
        }
        let pids = terminalsByTab.values.map { $0.process.shellPid }.filter { $0 > 0 }
        terminalsByTab.removeAll()
        // Final SIGKILL sweep after 500ms.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            for pid in pids {
                if kill(pid, 0) == 0 {
                    _ = kill(pid, SIGKILL)
                }
            }
        }
    }

    // MARK: - Writing to PTY (used by InputInjector)

    public func write(to tabId: UUID, bytes: [UInt8]) {
        guard let view = terminalsByTab[tabId] else {
            log.warn("write: tab \(tabId) has no terminal view (PTY closed?)")
            return
        }
        // LocalProcessTerminalView exposes `send` indirectly via TerminalViewDelegate;
        // the safe public API is to call `process.send(...)` on the underlying
        // LocalProcess.
        view.process.send(data: ArraySlice(bytes))
    }

    public func write(to tabId: UUID, string: String) {
        write(to: tabId, bytes: Array(string.utf8))
    }

    // MARK: - Helpers

    private func tabId(forView view: LocalProcessTerminalView) -> UUID? {
        for (id, v) in terminalsByTab where v === view {
            return id
        }
        // Fallback: identifier
        if let ident = view.identifier?.rawValue, let id = UUID(uuidString: ident) {
            return id
        }
        return nil
    }

    private func makeEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        if env["LANG"] == nil { env["LANG"] = "zh_CN.UTF-8" }
        if env["LC_ALL"] == nil { env["LC_ALL"] = env["LANG"] ?? "zh_CN.UTF-8" }
        // ensure PATH has the typical claude install locations
        let home = NSHomeDirectory()
        let extraPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "\(home)/.npm-global/bin"
        ]
        let existing = env["PATH"] ?? ""
        env["PATH"] = (extraPaths + [existing]).joined(separator: ":")
        return env.map { "\($0.key)=\($0.value)" }
    }

    /// Pick the first existing `claude` binary from common locations + PATH.
    public static func findClaudeBinary() -> String {
        let home = NSHomeDirectory()
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.bun/bin/claude",
            "\(home)/.npm-global/bin/claude"
        ]
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        // Last resort: rely on PATH via /usr/bin/env
        return "/usr/bin/env"
    }
}

// MARK: - LocalProcessTerminalViewDelegate

extension ProcessHost: LocalProcessTerminalViewDelegate {
    public nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // SwiftTerm already syncs PTY size internally via TIOCSWINSZ.
    }

    public nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // unused
    }

    public nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // unused
    }

    public nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        guard let view = source as? LocalProcessTerminalView else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                let tabId = self.tabId(forView: view)
                self.log.warn("process exited tab=\(tabId?.uuidString ?? "?") exitCode=\(exitCode ?? -1)")
                if let id = tabId {
                    self.tabManager?.updateStatus(id, status: (exitCode == 0 ? .idle : .error), exitCode: exitCode)
                    self.pidTracker.untrack(tabId: id)
                    self.onProcessExited?(id, exitCode)
                }
            }
        }
    }
}
