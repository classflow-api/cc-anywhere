// NoMoveBackdrop.swift
// NSViewRepresentable + NSView subclass，强制 mouseDownCanMoveWindow=false。
// 解决 macOS 14 之前 SwiftUI Button(.plain) / onTapGesture 在 hiddenTitleBar
// titlebar 区域（顶部 ~28pt）不可点的问题——系统会把这块识别为
// movable-window region，吞掉鼠标点击。
//
// 用法：
//   HStack { ... }.background(NoMoveBackdrop(color: palette.bgElev))
//
// 该背景 view 覆盖整个 HStack 区域并声明自己不可触发 window move，
// SwiftUI 按钮的 hit-test 可以正常传到上层。

import SwiftUI
import AppKit

private final class NoMoveNSView: NSView {
    /// 任何在本 view 上的 mouseDown 都不会移动窗口。
    override var mouseDownCanMoveWindow: Bool { false }
    /// 让 inactive 窗口也接受第一下点击（避免 click-to-focus 吞事件）。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

public struct NoMoveBackdrop: NSViewRepresentable {
    public let color: Color

    public init(color: Color) {
        self.color = color
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NoMoveNSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(color).cgColor
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer?.backgroundColor = NSColor(color).cgColor
    }
}
