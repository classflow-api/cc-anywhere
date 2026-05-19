// Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.
//
// TabUIHelpers.swift
// 工作区相关的 AppKit 共享对话框（在 SidebarView / TabStripView 间复用，
// 避免重复实现 + 文案分歧）。

import AppKit

@MainActor
public enum TabUIHelpers {
    /// 弹一个 NSAlert + NSPopUpButton 让用户选 Claude Code permission mode。
    /// 返回 nil 表示用户取消；否则返回选中的 mode。
    /// - 默认选中：`.default`
    /// - 显示文本：`PermissionMode.displayName`（中文 + rawValue 提示）
    public static func askPermissionMode(prompt: String,
                                         defaultMode: PermissionMode = .default) -> PermissionMode? {
        let alert = NSAlert()
        alert.messageText = "选择权限模式"
        alert.informativeText = prompt + "\n\n选择后会作为 `--permission-mode` 传给 Claude Code。创建后可右键工作区随时修改。"
        alert.alertStyle = .informational

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        for m in PermissionMode.allCases {
            popup.addItem(withTitle: m.displayName)
        }
        if let idx = PermissionMode.allCases.firstIndex(of: defaultMode) {
            popup.selectItem(at: idx)
        }

        // 容器：popup + 当前选项的 summary 文字（用 NSTextField 不可编辑）
        let summary = NSTextField(labelWithString: defaultMode.summary)
        summary.frame = NSRect(x: 0, y: 0, width: 360, height: 36)
        summary.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        summary.textColor = .secondaryLabelColor
        summary.maximumNumberOfLines = 2
        summary.lineBreakMode = .byWordWrapping

        // popup 变化时同步 summary 文本
        let target = PermissionModePopupTarget(popup: popup, summary: summary)
        popup.target = target
        popup.action = #selector(PermissionModePopupTarget.didChange(_:))

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 70))
        popup.frame = NSRect(x: 0, y: 40, width: 360, height: 26)
        summary.frame = NSRect(x: 2, y: 0, width: 356, height: 34)
        container.addSubview(popup)
        container.addSubview(summary)
        alert.accessoryView = container

        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        // 强引用 target 直到 modal 结束（withExtendedLifetime 保证 ARC 不提前释放）
        let response = withExtendedLifetime(target) { alert.runModal() }
        guard response == .alertFirstButtonReturn else { return nil }
        let idx = popup.indexOfSelectedItem
        guard idx >= 0, idx < PermissionMode.allCases.count else { return defaultMode }
        return PermissionMode.allCases[idx]
    }
}

/// NSPopUpButton 的 Objective-C runtime target（用于响应选项变化、更新 summary 文案）。
/// 必须是 NSObject，且 selector 通过 `@objc` 暴露，否则 AppKit 无法找到。
@MainActor
private final class PermissionModePopupTarget: NSObject {
    weak var popup: NSPopUpButton?
    weak var summary: NSTextField?

    init(popup: NSPopUpButton, summary: NSTextField) {
        self.popup = popup
        self.summary = summary
    }

    @objc func didChange(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < PermissionMode.allCases.count else { return }
        summary?.stringValue = PermissionMode.allCases[idx].summary
    }
}
