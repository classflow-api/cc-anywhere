// MainWindow.swift
// Composes the entire main window: ChromeBar + TabStripView + horizontal
// split of Sidebar / TabContentView / ActivityPanel.

import SwiftUI
import AppKit

struct MainWindowView: View {
    @EnvironmentObject var container: DependencyContainer
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var ws: WSClient
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var fileViewerState: FileViewerState
    @EnvironmentObject var askCardController: AskQuestionCardController
    @EnvironmentObject var processHost: ProcessHost

    var body: some View {
        let palette = themeManager.palette
        ZStack {
            // Backdrop
            palette.bg.ignoresSafeArea()
            DotGridBackground(color: palette.dotGrid)
                .ignoresSafeArea()
            AuroraOrbs(tone: .cyan)
                .opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ChromeBar()
                if tabManager.tabs.isEmpty {
                    EmptyStateView()
                } else {
                    HStack(spacing: 0) {
                        SidebarView()
                        if let sel = tabManager.selectedTabId,
                           let tab = tabManager.tab(by: sel) {
                            // 文件树（按 tab.id 强制重建，切 tab 时 root 跟随）
                            FileExplorerView(rootURL: tab.folder)
                                .id(tab.id)
                            TabContentView(tab: tab)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            // 文件阅读器：点击文件树文件时打开，宽度可拖
                            if let openFile = fileViewerState.openFile {
                                ResizableDivider(
                                    width: $fileViewerState.panelWidth,
                                    minWidth: 280,
                                    maxWidth: 1200,
                                    palette: themeManager.palette
                                )
                                FileViewerPanel(url: openFile,
                                                onClose: { fileViewerState.close() })
                                    .frame(width: fileViewerState.panelWidth)
                                    .id(openFile)
                            }
                        } else {
                            EmptyStateView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }

            // AskQuestion 卡片已移到 TabContentView 内嵌底部弹出（按 tab），
            // 不再全局遮罩主窗口 — 多 tab 间互不阻塞。
        }
        .foregroundColor(palette.text)
        // 接住 EmptyStateView 按钮的 ccNewTabRequest（之前由 TabStripView 监听，
        // 但 TabStripView 实际从未在 MainWindow 中实例化，导致按钮 dead click）
        .onReceive(NotificationCenter.default.publisher(for: .ccNewTabRequest)) { _ in
            createTabViaPanel()
        }
    }

    private func createTabViaPanel() {
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
                tabManager.selectedTabId = tab.id
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
}

private struct EmptyStateView: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        let palette = themeManager.palette
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(
                        colors: [palette.accent, Color(hex: 0x9A7BF2)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 60, height: 60)
                    .shadow(color: palette.accent.opacity(0.4), radius: 16, y: 8)
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }
            Text("点击 + 创建第一个 Tab")
                .font(AppFont.ui(size: 16, weight: .semibold))
                .foregroundColor(palette.text)
            Text("每个 Tab 绑定一个本地项目文件夹，启动后由 claude -c 恢复会话。")
                .font(AppFont.ui(size: 12))
                .foregroundColor(palette.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button(action: createTab) {
                Text("选择项目文件夹…")
                    .font(AppFont.ui(size: 12, weight: .semibold))
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(palette.accent)
                    .foregroundColor(palette.accentFg)
                    .clipShape(Capsule())
                    .shadow(color: palette.accent.opacity(0.4), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.bg.opacity(0.001))
    }

    private func createTab() {
        NotificationCenter.default.post(name: .ccNewTabRequest, object: nil)
    }
}
