// CCAnywhereApp.swift
// SwiftUI @main entry. The DependencyContainer is held here and bridged
// into the AppDelegate.

import SwiftUI
import AppKit

@main
struct CCAnywhereApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var container = DependencyContainer()

    var body: some Scene {
        WindowGroup("cc-anywhere") {
            MainWindowView()
                .environmentObject(container)
                .environmentObject(container.preferences)
                .environmentObject(container.themeManager)
                .environmentObject(container.tabManager)
                .environmentObject(container.wsClient)
                .environmentObject(container.processHost)
                .environmentObject(container.deviceManager)
                .environmentObject(container.fileViewerState)
                .frame(minWidth: 1200, minHeight: 760)
                .background(WindowAccessor { window in
                    guard let w = window else { return }
                    w.title = "遥指"
                    // 关键：使用 macOS native titlebar（不透明 + 可见 title），
                    // SwiftUI 内容真正在 titlebar 下方独立绘制，
                    // 按钮绝对在 SwiftUI 内容区，hit-test 一定能 work。
                    w.titleVisibility = .visible
                    w.titlebarAppearsTransparent = false
                    w.toolbarStyle = .unified
                })
                .preferredColorScheme(effectiveColorScheme(container.preferences))
                .onAppear {
                    appDelegate.container = container
                }
        }
        // .titleBar：使用 macOS 原生 titlebar（28pt 高，含 traffic lights + 标题文字）。
        // SwiftUI 内容（ChromeBar 等）严格在 titlebar 下方独立绘制。
        // 按钮位置完全脱离 titlebar movable-region，hit-test 一定能 work。
        // 视觉代价：顶部有两条 bar（系统 titlebar + 我们的 ChromeBar），
        // 但比"按钮点不开"重要得多。
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建工作区…") {
                    NotificationCenter.default.post(name: .ccNewTabRequest, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(replacing: .appSettings) {
                Button("偏好设置…") {
                    AppDelegate.shared?.openPreferences(nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }

    private func effectiveColorScheme(_ pref: PreferencesService) -> ColorScheme? {
        switch pref.appearance {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

extension Notification.Name {
    public static let ccNewTabRequest = Notification.Name("cc.newTabRequest")
    public static let ccTabCloseRequest = Notification.Name("cc.tabCloseRequest")
}

// MARK: - WindowAccessor

/// Tiny SwiftUI helper that gives us access to the NSWindow once attached.
struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { [weak v] in callback(v?.window) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
