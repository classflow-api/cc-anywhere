// ChromeBar.swift
// Mirrors the title-bar status row in mac-client.jsx's MacChrome:
//   [traffic lights]   [connection pill]   [history | bell | settings]
// We rely on the macOS system title bar for traffic lights, so we render
// only the pill row + trailing buttons below it.

import SwiftUI
import AppKit

struct ChromeBar: View {
    @EnvironmentObject var ws: WSClient
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var preferences: PreferencesService

    var body: some View {
        let palette = themeManager.palette
        HStack(spacing: 12) {
            Spacer()
            // Connection pill
            connectionPill(palette: palette)
            Spacer()
            HStack(spacing: 14) {
                Button(action: openHistory) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(palette.textMuted)
                }
                .buttonStyle(.plain)
                .help("查看日志")

                Button(action: {}) {
                    Image(systemName: "bell")
                        .foregroundColor(palette.textMuted)
                }
                .buttonStyle(.plain)

                Button(action: openPreferences) {
                    Image(systemName: "gearshape")
                        .foregroundColor(palette.textMuted)
                }
                .buttonStyle(.plain)
                .help("偏好设置")
                .keyboardShortcut(",", modifiers: .command)
            }
            .font(.system(size: 14))
            .padding(.trailing, 14)
        }
        .frame(height: 36)
        .background(palette.bgElev)
        .overlay(
            Rectangle().fill(palette.line).frame(height: 1),
            alignment: .bottom
        )
    }

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

    private func openPreferences() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.openPreferences(nil)
        }
    }

    private func openHistory() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.openLogViewer(nil)
        }
    }
}
