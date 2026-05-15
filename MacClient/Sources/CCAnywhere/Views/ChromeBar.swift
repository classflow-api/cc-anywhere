// ChromeBar.swift
// 顶部自绘 chrome bar，用 .windowStyle(.hiddenTitleBar) 替代系统标题栏：
//   [traffic-lights 占位 76]  [Logo + 遥指 + 版本]  ............  [连接 pill] [历史] [设置]

import SwiftUI
import AppKit

struct ChromeBar: View {
    @EnvironmentObject var ws: WSClient
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var preferences: PreferencesService

    var body: some View {
        let palette = themeManager.palette
        HStack(spacing: 10) {
            // ChromeBar 在 macOS 系统 titlebar 下方独立一行，
            // traffic lights 不在我们的内容区，logo 紧贴最左
            HStack(spacing: 10) {
                LogoMark(size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("遥指")
                        .font(AppFont.ui(size: 13, weight: .bold))
                        .foregroundColor(palette.text)
                        .tracking(0.5)
                    Text("v0.1.0 · M3")
                        .font(AppFont.mono(size: 9.5))
                        .foregroundColor(palette.textFaint)
                }
            }
            .padding(.leading, 14)

            Spacer()

            // 右侧：连接 pill + 历史 + 设置（与 sidebar 的 + 按钮同样 pattern：
            // SwiftUI Button(.plain) + contentShape(Rectangle)。既然 sidebar +
            // 能点，这里也能点。）
            connectionPill(palette: palette)
            chromeIconButton(systemName: "clock.arrow.circlepath",
                             tooltip: "查看日志",
                             palette: palette,
                             action: openHistory)
            chromeIconButton(systemName: "gearshape",
                             tooltip: "偏好设置",
                             palette: palette,
                             action: openPreferences)
                .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.trailing, 14)
        .frame(height: 44)
        // ChromeBar 完全在系统 titlebar 下方，普通 Color background 即可
        .background(palette.bgElev)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.line)
                .frame(height: 1)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Components

    private func connectionPill(palette: ColorPalette) -> some View {
        let (dot, label, host) = pillData(palette: palette)
        return HStack(spacing: 8) {
            PulseDot(color: dot, size: 6, pulse: isPulsing)
            Text(label)
                .font(AppFont.ui(size: 11.5, weight: .semibold))
                .foregroundColor(palette.text)
            Text("·").foregroundColor(palette.textFaint)
            Text(host)
                .font(AppFont.mono(size: 11.5))
                .foregroundColor(palette.textMuted)
            Text("·").foregroundColor(palette.textFaint)
            Image(systemName: "iphone")
                .font(.system(size: 11))
                .foregroundColor(palette.textMuted)
            Text("\(ws.phoneCount)")
                .font(AppFont.mono(size: 11.5, weight: .semibold))
                .foregroundColor(palette.text)
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(
            Capsule().fill(palette.bgInset)
                .overlay(Capsule().stroke(palette.line, lineWidth: 1))
        )
    }

    private func chromeIconButton(systemName: String,
                                  tooltip: String,
                                  palette: ColorPalette,
                                  action: @escaping () -> Void) -> some View {
        Button(action: {
            // 诊断：用 AppLogger 写日志到 ~/Library/Logs/cc-anywhere/cc-anywhere.log
            // 这样能 100% 确认按钮 click 是否触发 action。
            AppLogger.shared.tagged("ChromeBar")
                .info("icon button clicked: \(systemName)")
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .foregroundColor(palette.textMuted)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private var isPulsing: Bool {
        if case .connected = ws.state { return true }
        return false
    }

    private func pillData(palette: ColorPalette) -> (Color, String, String) {
        let cfg = preferences.serverConfig
        let host = cfg.server.isEmpty ? "未配置" : "\(cfg.server):\(cfg.port)"
        switch ws.state {
        case .connected: return (palette.success, "已连接", host)
        case .connecting: return (palette.warn, "连接中…", host)
        case .reconnecting(let n): return (palette.warn, "重连中(\(n))", host)
        case .disconnected(let r): return (palette.danger, r ?? "未连接", host)
        }
    }

    // MARK: - Actions

    private func openPreferences() {
        // 通过 AppDelegate.shared 直接访问，绕开 SwiftUI 包装层
        // （NSApp.delegate 在 @NSApplicationDelegateAdaptor 下是 SwiftUI.AppDelegate，
        // 不能 cast 到我们的 AppDelegate）
        AppDelegate.shared?.openPreferences(nil)
    }

    private func openHistory() {
        AppDelegate.shared?.openLogViewer(nil)
    }
}
