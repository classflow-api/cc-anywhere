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

    /// Optional user override for the claude binary path. Consulted by
    /// `resolveClaudeBinary()` before the built-in candidate list. Wired up
    /// from `PreferencesService.claudePathOverride`.
    public var claudePathProvider: (@MainActor () -> String?)?

    public init(tabManager: TabManager, pidTracker: PIDTracker) {
        self.tabManager = tabManager
        self.pidTracker = pidTracker
    }

    // MARK: - Lifecycle

    /// Start (or recreate) a terminal view for the given Tab.
    public func startProcess(for tab: Tab) {
        if terminalsByTab[tab.id] != nil { return }   // already running

        // Resolve claude binary first; if missing, surface a structured error
        // rather than silently fall back to `/usr/bin/env -c` (which env would
        // reject immediately and leave the user with an unexplained exit-2).
        guard let exe = resolveClaudeBinary() else {
            let reason = Self.claudeNotFoundReason(overrideUsed: claudePathProvider?())
            log.error("startProcess failed: claude binary not found (tab=\(tab.id))")
            tabManager?.updateStatus(tab.id,
                                     status: .error,
                                     exitCode: nil,
                                     errorReason: reason)
            return
        }

        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = self
        // wire up callbacks via the LocalProcessTerminalViewDelegate; we'll
        // identify tabs by the view itself, mapped via reverse lookup.
        view.identifier = NSUserInterfaceItemIdentifier(tab.id.uuidString)

        let env = makeEnvironment(tabId: tab.id)

        // Only pass `-c` when the project already has Claude history.
        // Otherwise `claude -c` exits 1 with "No conversation found to continue".
        // PRD: "启动 `claude -c` 自动恢复对话历史，无则启新对话".
        let encodedPath = tab.folder.path.replacingOccurrences(of: "/", with: "-")
        let claudeProjectDir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects/\(encodedPath)")
        let hasHistory = (try? FileManager.default.contentsOfDirectory(
            at: claudeProjectDir, includingPropertiesForKeys: nil))?
            .contains { $0.pathExtension == "jsonl" && !$0.lastPathComponent.hasPrefix("agent-") } ?? false

        let args = hasHistory ? ["-c"] : []
        let mode = hasHistory ? "-c (continue)" : "(new conversation)"
        view.feed(text: "\u{1B}[36m[cc-anywhere] launching: \(exe) \(mode)\nin: \(tab.folder.path)\u{1B}[0m\r\n")

        view.startProcess(
            executable: exe,
            args: args,
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

    private func makeEnvironment(tabId: UUID) -> [String] {
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
        // Hook bridge uses this to route AskUserQuestion back to the owning tab.
        env["CC_ANYWHERE_TAB_ID"] = tabId.uuidString
        return env.map { "\($0.key)=\($0.value)" }
    }

    /// The set of paths probed when no override is configured. Exposed so the
    /// preferences UI can show the user where we look.
    public static let defaultClaudeCandidates: [String] = {
        let home = NSHomeDirectory()
        return [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "\(home)/.bun/bin/claude",
            "\(home)/.npm-global/bin/claude"
        ]
    }()

    /// Resolve the `claude` binary path. Honors the user-supplied override
    /// from PreferencesService first; otherwise probes common install
    /// locations. Returns `nil` when nothing executable is found — callers
    /// MUST surface a user-visible error rather than fall back to a generic
    /// shell (the previous behavior of returning `/usr/bin/env` masked a
    /// missing-install as an opaque exit-2 with no UI feedback).
    public func resolveClaudeBinary() -> String? {
        let fm = FileManager.default
        if let override = claudePathProvider?()?.trimmingCharacters(in: .whitespaces),
           !override.isEmpty {
            if fm.isExecutableFile(atPath: override) {
                return override
            }
            log.warn("claudePathOverride \(override) is not executable; falling back to search")
        }
        for path in Self.defaultClaudeCandidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    /// Static convenience used by code that doesn't have a ProcessHost
    /// instance handy (e.g. preview / one-shot diagnostics). Returns `nil`
    /// when no claude binary can be located. Honors no override.
    public static func findClaudeBinary() -> String? {
        let fm = FileManager.default
        for path in defaultClaudeCandidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    /// Build a human-readable explanation for the missing-binary error,
    /// including all the paths we just probed so users know where they could
    /// install or where to point the override.
    public static func claudeNotFoundReason(overrideUsed: String?) -> String {
        var lines: [String] = []
        lines.append("未找到 claude 命令。")
        if let o = overrideUsed?.trimmingCharacters(in: .whitespaces), !o.isEmpty {
            lines.append("当前偏好设置中指定的路径 \(o) 不可执行。")
        }
        lines.append("已搜索以下位置：")
        for p in defaultClaudeCandidates {
            lines.append("  • \(p)")
        }
        lines.append("请确认 Claude Code CLI 已安装，或在「偏好设置 > 通用」中手动指定 claude 路径。")
        return lines.joined(separator: "\n")
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
