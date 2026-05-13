// TabStripView.swift
// Mirrors MacTabStrip in mac-client.jsx: horizontal scrolling tab bar with
// pulsing status dot + close button + unread badge + (+) on the right.

import SwiftUI
import AppKit

struct TabStripView: View {
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var processHost: ProcessHost
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        let palette = themeManager.palette
        HStack(alignment: .bottom, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(tabManager.tabs) { tab in
                        TabPill(tab: tab, palette: palette,
                                isActive: tab.id == tabManager.selectedTabId)
                            .onTapGesture {
                                tabManager.selectedTabId = tab.id
                                tabManager.clearUnread(tab.id)
                            }
                            .contextMenu {
                                Button("重命名…") { startRename(tab) }
                                Button("在 Finder 中显示") {
                                    NSWorkspace.shared.activateFileViewerSelecting([tab.folder])
                                }
                                Divider()
                                Button("关闭", role: .destructive) {
                                    confirmAndClose(tab)
                                }
                            }
                    }
                }
                .padding(.horizontal, 12)
            }
            Button(action: createTab) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundColor(palette.textMuted)
            }
            .buttonStyle(.plain)
            .help("新建 Tab")
            Spacer(minLength: 4)
        }
        .frame(height: 38)
        .background(palette.bg)
        .overlay(
            Rectangle()
                .fill(palette.line)
                .frame(height: 1),
            alignment: .bottom
        )
        .onReceive(NotificationCenter.default.publisher(for: .ccNewTabRequest)) { _ in
            createTab()
        }
    }

    // MARK: - Actions

    private func createTab() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "选择项目文件夹"
        panel.prompt = "打开"
        panel.message = "选择一个文件夹以创建新的 Claude Code Tab"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let name = url.lastPathComponent
                let tab = try tabManager.createTab(folder: url, name: name)
                processHost.startProcess(for: tab)
            } catch {
                let alert = NSAlert()
                alert.messageText = "无法创建 Tab"
                alert.informativeText = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "确定")
                alert.runModal()
            }
        }
    }

    private func startRename(_ tab: Tab) {
        let alert = NSAlert()
        alert.messageText = "重命名 Tab"
        alert.alertStyle = .informational
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.stringValue = tab.name
        alert.accessoryView = input
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            try? tabManager.renameTab(tab.id, to: input.stringValue)
        }
    }

    private func confirmAndClose(_ tab: Tab) {
        let alert = NSAlert()
        alert.messageText = "关闭 Tab"
        alert.informativeText = "关闭后 Claude Code 进程将退出（对话历史已自动保存）。确定关闭 \(tab.name)？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "关闭")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            processHost.stopProcess(for: tab.id)
            try? tabManager.removeTab(tab.id)
        }
    }
}

// MARK: - Single Tab pill

private struct TabPill: View {
    let tab: Tab
    let palette: ColorPalette
    let isActive: Bool
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var processHost: ProcessHost

    var body: some View {
        HStack(spacing: 8) {
            PulseDot(color: dotColor, size: 7, pulse: tab.status == .running && isActive)
            Text(tab.name)
                .font(AppFont.ui(size: 12, weight: isActive ? .semibold : .medium))
                .foregroundColor(isActive ? palette.text : palette.textMuted)
                .lineLimit(1)
            if tab.unread > 0 {
                Text("\(tab.unread)")
                    .font(.system(size: 9.5, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(palette.accent))
                    .foregroundColor(palette.accentFg)
            }
            Button(action: { closeTab() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(palette.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? palette.bgElev : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isActive ? palette.line : .clear, lineWidth: 1)
        )
        .padding(.bottom, isActive ? -1 : 0)
    }

    private var dotColor: Color {
        switch tab.status {
        case .running: return palette.success
        case .error:   return palette.danger
        case .idle:    return palette.textFaint
        }
    }

    private func closeTab() {
        let alert = NSAlert()
        alert.messageText = "关闭 Tab"
        alert.informativeText = "关闭后 Claude Code 进程将退出。确定关闭 \(tab.name)？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "关闭")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            processHost.stopProcess(for: tab.id)
            try? tabManager.removeTab(tab.id)
        }
    }
}
