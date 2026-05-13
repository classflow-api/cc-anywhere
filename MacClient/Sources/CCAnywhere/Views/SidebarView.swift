// SidebarView.swift
// Mirrors MacSidebar in mac-client.jsx: app logo + Workspaces list + Mobile
// list + session stats card.

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var ws: WSClient

    var body: some View {
        let palette = themeManager.palette
        VStack(alignment: .leading, spacing: 14) {
            // Logo + meta
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(LinearGradient(colors: [palette.accent, Color(hex: 0x9A7BF2)],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .frame(width: 26, height: 26)
                        .shadow(color: palette.accent.opacity(0.4), radius: 6, y: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white)
                        .frame(width: 10, height: 10)
                        .opacity(0.95)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("cc-anywhere")
                        .font(AppFont.ui(size: 12, weight: .bold))
                        .foregroundColor(palette.text)
                    Text("v0.1.0 · M3")
                        .font(AppFont.mono(size: 10))
                        .foregroundColor(palette.textFaint)
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            // Workspaces
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("Workspaces", palette: palette)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                ForEach(tabManager.tabs) { tab in
                    WorkspaceRow(
                        tab: tab,
                        palette: palette,
                        isActive: tab.id == tabManager.selectedTabId
                    )
                    .onTapGesture {
                        tabManager.selectedTabId = tab.id
                        tabManager.clearUnread(tab.id)
                    }
                }
                if tabManager.tabs.isEmpty {
                    Text("使用上方 + 创建第一个 Tab")
                        .font(AppFont.ui(size: 11))
                        .foregroundColor(palette.textFaint)
                        .padding(.horizontal, 8)
                }
            }

            // Mobile devices
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("Mobile · \(ws.phoneCount) 在线", palette: palette)
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

            // Session stats placeholder card
            statsCard(palette: palette)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .frame(width: 200, alignment: .topLeading)
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
                statCell(label: "Tabs", value: "\(tabManager.tabs.count)", palette: palette)
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
