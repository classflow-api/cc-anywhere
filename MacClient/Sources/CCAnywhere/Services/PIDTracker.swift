// PIDTracker.swift
// Tracks the PID of each Tab's claude subprocess in `last-pids.json` so we
// can clean up zombies if the app crashed last run (M2 R-M2-05).

import Foundation

@MainActor
public final class PIDTracker {
    private let log = AppLogger.shared.tagged("PIDTracker")
    private var pidsByTab: [String: Int32] = [:]   // tab UUID string -> pid

    private var storeURL: URL {
        PreferencesService.appSupportDir.appendingPathComponent("last-pids.json")
    }

    public init() {
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let dict = try? JSONDecoder().decode([String: Int32].self, from: data)
        else { return }
        pidsByTab = dict
    }

    private func persist() {
        do {
            let data = try JSONEncoder.pretty.encode(pidsByTab)
            try data.atomicWrite(to: storeURL, permissions: 0o600)
        } catch {
            log.error("persist failed: \(error)")
        }
    }

    public func track(tabId: UUID, pid: Int32) {
        pidsByTab[tabId.uuidString] = pid
        persist()
    }

    public func untrack(tabId: UUID) {
        pidsByTab.removeValue(forKey: tabId.uuidString)
        persist()
    }

    /// Walk every tracked PID; if it still belongs to a `claude` process,
    /// SIGKILL it. Done at startup to recover from crashes.
    public func reapStaleProcesses() {
        guard !pidsByTab.isEmpty else { return }
        for (tabId, pid) in pidsByTab {
            if pid <= 0 { continue }
            if isClaudeProcess(pid: pid) {
                log.warn("reaping stale claude PID \(pid) for tab \(tabId)")
                kill(pid, SIGKILL)
            }
        }
        pidsByTab.removeAll()
        persist()
    }

    private func isClaudeProcess(pid: pid_t) -> Bool {
        // Use `ps -p <pid> -o comm=` to read the command name.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", "\(pid)", "-o", "comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return false
        }
        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let str = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return false }
        // The full executable path is shown by ps; we look for `claude`.
        return str.lowercased().contains("claude")
    }
}
