// AppDelegate.swift
// NSApplicationDelegate hookups: terminate confirmation, lifecycle, menu.

import Foundation
import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    /// SwiftUI 用 `@NSApplicationDelegateAdaptor` 注册时，NSApp.delegate 实际上是
    /// SwiftUI.AppDelegate（一层包装），导致 `NSApp.delegate as? CCAnywhere.AppDelegate`
    /// cast 失败。View 通过这个 static shared 直接访问，绕开包装层。
    public static private(set) weak var shared: AppDelegate?

    public var container: DependencyContainer?
    public var preferencesController: NSWindowController?
    public var logViewerController: NSWindowController?
    /// Set this before calling `openPreferences(_:)` to land on a specific tab.
    /// Auto-resets to `.server` after the window opens.
    var initialPrefsTab: PrefsTab = .server
    private var keyMonitor: Any?

    private let log = AppLogger.shared.tagged("AppDelegate")

    public override init() {
        super.init()
        Self.shared = self
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 命令行直接运行裸 binary 时,Launch Services 默认把进程注册为 .accessory(背景进程),
        // 导致 SwiftUI 窗口可见但无法成为 key window,所有 TextField 都收不到键盘事件。
        // 显式声明 Regular,确保无论从 .app Bundle 还是裸 binary 启动行为一致。
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        container?.appDidFinishLaunching()
        // Install our menu
        installMainMenu()
        // Cmd+, 双保险：SwiftTerm 可能 swallow keyboard events 让菜单接不到，
        // 这里用 local monitor 拦截 Cmd+, 直接打开偏好设置。
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers == ","
            {
                Task { @MainActor [weak self] in self?.openPreferences(nil) }
                return nil  // 吃掉事件
            }
            return event
        }
        log.info("application did finish launching")
    }

    public func applicationWillResignActive(_ notification: Notification) {}

    deinit {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let count = container?.processHost.terminalsByTab.count ?? 0
        if count == 0 {
            container?.appWillTerminate()
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = "退出 cc-anywhere"
        alert.informativeText = "退出将关闭 \(count) 个 Tab 中的 Claude Code 进程，确定退出？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "退出")
        alert.addButton(withTitle: "取消")
        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            container?.appWillTerminate()
            return .terminateNow
        }
        return .terminateCancel
    }

    public func applicationWillTerminate(_ notification: Notification) {
        container?.appWillTerminate()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Menu

    private func installMainMenu() {
        let main = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 cc-anywhere",
                        action: #selector(NSApp.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        let prefsItem = NSMenuItem(title: "偏好设置…",
                                   action: #selector(openPreferences(_:)),
                                   keyEquivalent: ",")
        prefsItem.target = self
        appMenu.addItem(prefsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 cc-anywhere",
                        action: #selector(NSApp.terminate(_:)),
                        keyEquivalent: "q")

        // Edit 菜单 — 装好 Cut/Copy/Paste/Select All/Undo,让 Cmd+V 等系统快捷键
        // 走 responder chain 到 SwiftTerm/TextField/SecureField 等,实现粘贴/复制。
        // 缺这个菜单时 macOS 不会自动绑定 Cmd+V,粘贴文本/图片完全失效。
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销",
                         action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "重做",
                              action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切",
                         action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝",
                         action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴",
                         action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选",
                         action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // Help
        let helpItem = NSMenuItem()
        main.addItem(helpItem)
        let helpMenu = NSMenu(title: "帮助")
        helpItem.submenu = helpMenu
        let logItem = NSMenuItem(title: "查看日志…",
                                  action: #selector(openLogViewer(_:)),
                                  keyEquivalent: "l")
        logItem.target = self
        helpMenu.addItem(logItem)

        NSApp.mainMenu = main
    }

    @objc public func openPreferences(_ sender: Any?) {
        guard let container = container else { return }
        let tab = initialPrefsTab
        initialPrefsTab = .server  // reset
        if let pc = preferencesController {
            NotificationCenter.default.post(name: .ccPrefsSelectTab, object: tab)
            pc.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let pc = PreferencesWindowController.make(container: container, initialTab: tab)
        preferencesController = pc
        pc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc public func openLogViewer(_ sender: Any?) {
        if let lv = logViewerController {
            lv.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = LogViewerWindowController.make()
        logViewerController = controller
        controller.window?.makeKeyAndOrderFront(nil)
    }
}
