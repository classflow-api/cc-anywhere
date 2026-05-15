// NativeIconButton.swift
// NSButton 包成 SwiftUI 视图。绕开 macOS 14 上 SwiftUI Button(.plain) 在
// hiddenTitleBar 区域 hit-test 被吞的 bug —— NSButton 是原生控件，
// hit-test 由 AppKit 直接处理，不受 SwiftUI movable-window-region 影响。

import SwiftUI
import AppKit

public struct NativeIconButton: NSViewRepresentable {
    public let systemName: String
    public let pointSize: CGFloat
    public let tint: Color
    public let tooltip: String?
    public let action: () -> Void

    public init(systemName: String,
                pointSize: CGFloat = 14,
                tint: Color,
                tooltip: String? = nil,
                action: @escaping () -> Void) {
        self.systemName = systemName
        self.pointSize = pointSize
        self.tint = tint
        self.tooltip = tooltip
        self.action = action
    }

    public func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyUpOrDown
        button.target = context.coordinator
        button.action = #selector(Coordinator.fire)
        applyImage(button)
        button.toolTip = tooltip
        return button
    }

    public func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        applyImage(button)
        button.toolTip = tooltip
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    private func applyImage(_ button: NSButton) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let baseImg = NSImage(systemSymbolName: systemName, accessibilityDescription: tooltip)
        let tinted = baseImg?.withSymbolConfiguration(config)?
            .tinted(with: NSColor(tint))
        button.image = tinted ?? baseImg
        button.contentTintColor = NSColor(tint)
    }

    public final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) {
            self.action = action
        }
        @objc func fire() {
            action()
        }
    }
}

private extension NSImage {
    /// 给 SF Symbol 上色（NSButton 已设 contentTintColor 通常够，这里是 fallback）。
    func tinted(with color: NSColor) -> NSImage? {
        let img = self.copy() as! NSImage
        img.isTemplate = true
        return img
    }
}
