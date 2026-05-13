// AppDelegate.swift
// NSApplicationDelegate hookups: terminate confirmation, lifecycle, menu.

import Foundation
import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public var container: DependencyContainer?
    public var preferencesController: NSWindowController?
    public var logViewerController: NSWindowController?

    private let log = AppLogger.shared.tagged("AppDelegate")

    public func applicationDidFinishLaunching(_ notification: Notification) {
        container?.appDidFinishLaunching()
        // Install our menu
        installMainMenu()
        log.info("application did finish launching")
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
        if let pc = preferencesController {
            pc.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let pc = PreferencesWindowController.make(container: container)
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
