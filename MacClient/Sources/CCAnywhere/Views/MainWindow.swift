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
                TabStripView()
                Divider().opacity(0.0001)
                if tabManager.tabs.isEmpty {
                    EmptyStateView()
                } else {
                    HStack(spacing: 0) {
                        SidebarView()
                        if let sel = tabManager.selectedTabId,
                           let tab = tabManager.tab(by: sel) {
                            TabContentView(tab: tab)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            EmptyStateView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        ActivityPanelView(ws: ws)
                    }
                }
            }
        }
        .foregroundColor(palette.text)
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
