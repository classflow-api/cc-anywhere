// PreferencesWindow.swift
// AppKit window controller that hosts the SwiftUI preferences view, which
// mirrors the design's left-nav + right-body layout.

import SwiftUI
import AppKit

extension Notification.Name {
    public static let ccPrefsSelectTab = Notification.Name("cc.prefs.selectTab")
}

final class PreferencesWindowController: NSWindowController {
    static func make(container: DependencyContainer,
                     initialTab: PrefsTab = .server) -> PreferencesWindowController {
        let view = PreferencesRootView(initialTab: initialTab)
            .environmentObject(container)
            .environmentObject(container.preferences)
            .environmentObject(container.themeManager)
            .environmentObject(container.tabManager)
            .environmentObject(container.wsClient)
            .environmentObject(container.deviceManager)
            .frame(minWidth: 880, minHeight: 600)

        let hosting = NSHostingController(rootView: AnyView(view))
        let window = NSWindow(contentViewController: hosting)
        window.title = "偏好设置"
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 900, height: 620))
        window.center()
        return PreferencesWindowController(window: window)
    }
}

enum PrefsTab: String, CaseIterable, Identifiable {
    case general, server, devices, themes, security, logs
    var id: String { rawValue }
    var label: String {
        switch self {
        case .general: return "通用"
        case .server:  return "Server 连接"
        case .devices: return "设备管理"
        case .themes:  return "终端主题"
        case .security:return "安全"
        case .logs:    return "日志与诊断"
        }
    }
    var icon: String {
        switch self {
        case .general: return "cpu"
        case .server:  return "wifi"
        case .devices: return "iphone"
        case .themes:  return "paintpalette"
        case .security:return "lock"
        case .logs:    return "doc.text"
        }
    }
}

struct PreferencesRootView: View {
    @State var selected: PrefsTab = .server
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var preferences: PreferencesService

    init(initialTab: PrefsTab = .server) {
        _selected = State(initialValue: initialTab)
    }

    var body: some View {
        let palette = themeManager.palette
        HStack(spacing: 0) {
            // Left nav
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("偏好设置", palette: palette)
                    .padding(.horizontal, 8).padding(.vertical, 12)
                ForEach(PrefsTab.allCases) { item in
                    PrefsNavRow(item: item, palette: palette, selected: $selected)
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 192)
            .background(palette.bgInset)
            .overlay(
                Rectangle().fill(palette.line).frame(width: 1),
                alignment: .trailing
            )

            // Body
            Group {
                switch selected {
                case .general: GeneralPane()
                case .server: ServerPane()
                case .devices: DevicesPane()
                case .themes: ThemesPane()
                case .security: SecurityPane()
                case .logs: LogsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.bg)
        }
        .preferredColorScheme(preferences.appearance == .light ? .light :
                              (preferences.appearance == .dark ? .dark : nil))
        .onReceive(NotificationCenter.default.publisher(for: .ccPrefsSelectTab)) { note in
            if let tab = note.object as? PrefsTab { selected = tab }
        }
    }
}

private struct PrefsNavRow: View {
    let item: PrefsTab
    let palette: ColorPalette
    @Binding var selected: PrefsTab

    var body: some View {
        let isActive = (selected == item)
        return HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 12))
                .foregroundColor(isActive ? palette.accent : palette.textMuted)
            Text(item.label)
                .font(AppFont.ui(size: 12.5, weight: isActive ? .semibold : .medium))
                .foregroundColor(isActive ? palette.accent : palette.text)
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isActive ? palette.accentSoft : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { selected = item }
    }
}
