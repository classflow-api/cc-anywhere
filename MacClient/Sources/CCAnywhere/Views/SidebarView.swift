// SidebarView.swift
// 工作区列表（每行 = 一个 Tab）+ 手机端列表 + 本次会话统计。
// Logo + 软件名已移到顶部 ChromeBar；本视图聚焦"工作区 / 手机端 / 统计"。

import SwiftUI
import AppKit

struct SidebarView: View {
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var processHost: ProcessHost
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var ws: WSClient

    var body: some View {
        let palette = themeManager.palette
        VStack(alignment: .leading, spacing: 14) {
            // 工作区 section header（含 + 按钮）
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    SectionLabel("工作区", palette: palette)
                    Spacer()
                    Button(action: createTab) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 20, height: 20)
                            .foregroundColor(palette.textMuted)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("新建工作区（选择项目文件夹）")
                    .keyboardShortcut("n", modifiers: .command)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)

                ForEach(tabManager.tabs) { tab in
                    WorkspaceRow(
                        tab: tab,
                        palette: palette,
                        isActive: tab.id == tabManager.selectedTabId
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        tabManager.selectedTabId = tab.id
                        tabManager.clearUnread(tab.id)
                    }
                    .contextMenu {
                        Button("在 Finder 中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([tab.folder])
                        }
                        Divider()
                        Button("关闭工作区", role: .destructive) { confirmAndClose(tab) }
                    }
                }
                if tabManager.tabs.isEmpty {
                    Text("点击右上方 + 创建工作区")
                        .font(AppFont.ui(size: 11))
                        .foregroundColor(palette.textFaint)
                        .padding(.horizontal, 8)
                }
            }

            // 手机端 section
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("手机端 · \(ws.phoneCount) 在线", palette: palette)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                if deviceManager.devices.isEmpty {
                    Text("暂无绑定设备")
                        .font(AppFont.ui(size: 11))
                        .foregroundColor(palette.textFaint)
                        .padding(.horizontal, 8)
                } else {
                    ForEach(deviceManager.devices.filter { $0.online }) { d in
                        HStack(spacing: 8) {
                            PulseDot(color: palette.success, size: 6, pulse: false)
                            Text(d.deviceName)
                                .font(AppFont.ui(size: 11.5))
                                .foregroundColor(palette.textMuted)
                                .lineLimit(1)
                            Spacer()
                            if let ms = d.latencyMs {
                                Text("\(ms)ms")
                                    .font(AppFont.mono(size: 10))
                                    .foregroundColor(palette.textFaint)
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                    }
                }
            }

            Spacer()

            serverHealthCard(palette: palette)
            statsCard(palette: palette)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .frame(width: 220, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [palette.bgInset, palette.bg.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(
            Rectangle().fill(palette.line).frame(width: 1),
            alignment: .trailing
        )
    }

    // MARK: - Actions

    private func createTab() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "选择项目文件夹"
        panel.prompt = "打开"
        panel.message = "选择一个文件夹以创建新的工作区"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let name = url.lastPathComponent
                let tab = try tabManager.createTab(folder: url, name: name)
                processHost.startProcess(for: tab)
                tabManager.selectedTabId = tab.id
            } catch {
                let alert = NSAlert()
                alert.messageText = "无法创建工作区"
                alert.informativeText = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "确定")
                alert.runModal()
            }
        }
    }

    private func confirmAndClose(_ tab: Tab) {
        let alert = NSAlert()
        alert.messageText = "关闭工作区"
        alert.informativeText = "关闭后 Claude Code 进程将退出（对话历史已自动保存）。确定关闭 \(tab.name)？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "关闭")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            processHost.stopProcess(for: tab.id)
            try? tabManager.removeTab(tab.id)
        }
    }

    // MARK: - Server Health (从右侧 ActivityPanel 搬来)

    private func serverHealthCard(palette: ColorPalette) -> some View {
        let history = ws.latencyHistoryMs
        let latest = history.last
        let isConnected: Bool = {
            if case .connected = ws.state { return true } else { return false }
        }()
        let dotColor: Color = isConnected ? palette.success
            : (history.isEmpty ? palette.textFaint : palette.warn)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                PulseDot(color: dotColor, size: 6, pulse: isConnected)
                Text("Server 健康")
                    .font(AppFont.ui(size: 11, weight: .semibold))
                    .foregroundColor(palette.text)
                Spacer()
                Text(latest.map { "\($0)ms" } ?? "—")
                    .font(AppFont.mono(size: 10))
                    .foregroundColor(palette.textFaint)
            }
            Sparkline(palette: palette, pointsMs: history)
                .frame(height: 24)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(palette.bgInset)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.line, lineWidth: 1))
        )
    }

    // MARK: - Stats

    private func statsCard(palette: ColorPalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11))
                    .foregroundColor(palette.accent)
                Text("本次会话")
                    .font(AppFont.ui(size: 11, weight: .semibold))
                    .foregroundColor(palette.text)
            }
            HStack(spacing: 12) {
                statCell(label: "工作区", value: "\(tabManager.tabs.count)", palette: palette)
                statCell(label: "设备", value: "\(deviceManager.devices.count)", palette: palette)
            }
            HStack(spacing: 12) {
                statCell(label: "在线", value: "\(ws.phoneCount)", palette: palette)
                statCell(label: "状态", value: stateLabel, palette: palette)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(palette.bgInset)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.line, lineWidth: 1))
        )
    }

    private var stateLabel: String {
        switch ws.state {
        case .connected: return "OK"
        case .connecting: return "…"
        case .reconnecting: return "…"
        case .disconnected: return "断开"
        }
    }

    private func statCell(label: String, value: String, palette: ColorPalette) -> some View {
        HStack(spacing: 4) {
            Text(label).font(AppFont.ui(size: 10.5)).foregroundColor(palette.textMuted)
            Text(value).font(AppFont.mono(size: 10.5, weight: .semibold))
                .foregroundColor(palette.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkspaceRow: View {
    let tab: Tab
    let palette: ColorPalette
    let isActive: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            if isActive {
                Capsule()
                    .fill(palette.accent)
                    .frame(width: 3, height: 16)
                    .offset(x: -8)
            }
            HStack(spacing: 8) {
                PulseDot(color: tab.status == .running ? palette.success : palette.textFaint,
                         size: 6, pulse: tab.status == .running && isActive)
                Text(tab.name)
                    .font(AppFont.ui(size: 12, weight: isActive ? .semibold : .medium))
                    .foregroundColor(isActive ? palette.accent : palette.text)
                    .lineLimit(1)
                Spacer()
                if tab.unread > 0 {
                    Text("\(tab.unread)")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(isActive ? palette.accent : palette.textMuted)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isActive ? palette.accentSoft : Color.clear)
            )
        }
    }
}
