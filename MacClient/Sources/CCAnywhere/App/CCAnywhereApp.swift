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
                .frame(minWidth: 1200, minHeight: 760)
                .background(WindowAccessor { window in
                    window?.title = "cc-anywhere"
                    window?.titlebarAppearsTransparent = true
                    window?.toolbarStyle = .unified
                })
                .preferredColorScheme(effectiveColorScheme(container.preferences))
                .onAppear {
                    appDelegate.container = container
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建 Tab…") {
                    NotificationCenter.default.post(name: .ccNewTabRequest, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }

        Settings {
            Text("使用 cc-anywhere → 偏好设置… 打开设置")
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
