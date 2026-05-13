// LogViewerWindow.swift
// Standalone log viewer window (helps → 查看日志…).
// Reads ~/Library/Logs/cc-anywhere/cc-anywhere.log (last 1000 lines) with
// filter / search / export controls.

import SwiftUI
import AppKit

final class LogViewerWindowController: NSWindowController {
    static func make() -> LogViewerWindowController {
        let hosting = NSHostingController(rootView: LogViewerView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "日志"
        window.setContentSize(NSSize(width: 760, height: 540))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.center()
        return LogViewerWindowController(window: window)
    }
}

struct LogViewerView: View {
    @State private var level: LogLevel = .info
    @State private var filter: String = ""
    @State private var logContents: String = AppLogger.shared.readRecent()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("级别", selection: $level) {
                    ForEach(LogLevel.allCases, id: \.self) { l in
                        Text(l.label.trimmingCharacters(in: .whitespaces)).tag(l)
                    }
                }
                .frame(maxWidth: 220)
                TextField("搜索关键字…", text: $filter)
                    .textFieldStyle(.roundedBorder)
                Button("刷新") {
                    logContents = AppLogger.shared.readRecent()
                }
                Button("导出…") { exportLog() }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.05))

            ScrollView {
                Text(filtered)
                    .font(AppFont.mono(size: 11))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
    }

    private var filtered: String {
        var out: [Substring] = []
        for line in logContents.split(separator: "\n") {
            if !filter.isEmpty && !line.localizedCaseInsensitiveContains(filter) {
                continue
            }
            if line.contains("[\(level.label)]") || passesLevelFilter(line: String(line)) {
                out.append(line)
            }
        }
        return out.joined(separator: "\n")
    }

    private func passesLevelFilter(line: String) -> Bool {
        // ERROR > WARN > INFO > DEBUG
        let levels = LogLevel.allCases
        for l in levels where l >= level {
            if line.contains("[\(l.label)]") { return true }
        }
        return false
    }

    private func exportLog() {
        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        panel.nameFieldStringValue = "cc-anywhere-\(formatter.string(from: Date())).log"
        panel.allowedContentTypes = []
        if panel.runModal() == .OK, let url = panel.url {
            try? filtered.data(using: .utf8)?.write(to: url)
        }
    }
}
