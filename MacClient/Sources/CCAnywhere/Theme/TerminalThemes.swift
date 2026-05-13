// TerminalThemes.swift
// Mirrors window.TERMINAL_THEMES from tokens.js (6 presets).

import SwiftUI
import AppKit

public struct TerminalTheme: Identifiable, @unchecked Sendable, Hashable {
    public let id: String          // 'eyecare' / 'midnight' / ...

    public static func == (lhs: TerminalTheme, rhs: TerminalTheme) -> Bool {
        lhs.id == rhs.id
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public let name: String
    public let subtitle: String
    public let bg: NSColor
    public let fg: NSColor
    public let cursor: NSColor
    public let selection: NSColor
    public let dim: NSColor
    public let accent1: NSColor
    public let accent2: NSColor
    public let accent3: NSColor
    public let accent4: NSColor
    public let chrome: String

    public var bgSwiftUI: Color { Color(bg) }
    public var fgSwiftUI: Color { Color(fg) }
    public var cursorSwiftUI: Color { Color(cursor) }
    public var dimSwiftUI: Color { Color(dim) }
    public var accent1SwiftUI: Color { Color(accent1) }
    public var accent2SwiftUI: Color { Color(accent2) }
    public var accent3SwiftUI: Color { Color(accent3) }
    public var accent4SwiftUI: Color { Color(accent4) }
}

public enum TerminalThemes {
    public static let all: [TerminalTheme] = [
        TerminalTheme(
            id: "eyecare", name: "护眼绿",
            subtitle: "Eye-care · soothing green canvas",
            bg: NSColor(hex: 0xC7EDCC), fg: NSColor(hex: 0x2A3A2D),
            cursor: NSColor(hex: 0x2E7D32),
            selection: NSColor(hex: 0x2E7D32).withAlphaComponent(0.22),
            dim: NSColor(hex: 0x7D9A82),
            accent1: NSColor(hex: 0x1B5E20),
            accent2: NSColor(hex: 0x4A148C),
            accent3: NSColor(hex: 0xBF360C),
            accent4: NSColor(hex: 0x01579B),
            chrome: "sage"
        ),
        TerminalTheme(
            id: "midnight", name: "Midnight",
            subtitle: "暗黑沉浸 · deep ink",
            bg: NSColor(hex: 0x0D1117), fg: NSColor(hex: 0xD1D9E6),
            cursor: NSColor(hex: 0x58A6FF),
            selection: NSColor(hex: 0x58A6FF).withAlphaComponent(0.22),
            dim: NSColor(hex: 0x6E7681),
            accent1: NSColor(hex: 0x7EE787),
            accent2: NSColor(hex: 0x79C0FF),
            accent3: NSColor(hex: 0xFF7B72),
            accent4: NSColor(hex: 0xD2A8FF),
            chrome: "dark"
        ),
        TerminalTheme(
            id: "dracula", name: "Dracula",
            subtitle: "吸血鬼 · violet bloom",
            bg: NSColor(hex: 0x282A36), fg: NSColor(hex: 0xF8F8F2),
            cursor: NSColor(hex: 0xFF79C6),
            selection: NSColor(hex: 0xFF79C6).withAlphaComponent(0.22),
            dim: NSColor(hex: 0x6272A4),
            accent1: NSColor(hex: 0x50FA7B),
            accent2: NSColor(hex: 0x8BE9FD),
            accent3: NSColor(hex: 0xFF5555),
            accent4: NSColor(hex: 0xBD93F9),
            chrome: "dark"
        ),
        TerminalTheme(
            id: "solarized", name: "Solarized Light",
            subtitle: "日光 · warm parchment",
            bg: NSColor(hex: 0xFDF6E3), fg: NSColor(hex: 0x586E75),
            cursor: NSColor(hex: 0x268BD2),
            selection: NSColor(hex: 0x268BD2).withAlphaComponent(0.18),
            dim: NSColor(hex: 0x93A1A1),
            accent1: NSColor(hex: 0x859900),
            accent2: NSColor(hex: 0x268BD2),
            accent3: NSColor(hex: 0xDC322F),
            accent4: NSColor(hex: 0x6C71C4),
            chrome: "cream"
        ),
        TerminalTheme(
            id: "nord", name: "Nord",
            subtitle: "北欧 · arctic ice",
            bg: NSColor(hex: 0x2E3440), fg: NSColor(hex: 0xD8DEE9),
            cursor: NSColor(hex: 0x88C0D0),
            selection: NSColor(hex: 0x88C0D0).withAlphaComponent(0.22),
            dim: NSColor(hex: 0x4C566A),
            accent1: NSColor(hex: 0xA3BE8C),
            accent2: NSColor(hex: 0x88C0D0),
            accent3: NSColor(hex: 0xBF616A),
            accent4: NSColor(hex: 0xB48EAD),
            chrome: "dark"
        ),
        TerminalTheme(
            id: "monokai", name: "Monokai Pro",
            subtitle: "霓虹 · neon citrus",
            bg: NSColor(hex: 0x2D2A2E), fg: NSColor(hex: 0xFCFCFA),
            cursor: NSColor(hex: 0xFFD866),
            selection: NSColor(hex: 0xFFD866).withAlphaComponent(0.22),
            dim: NSColor(hex: 0x727072),
            accent1: NSColor(hex: 0xA9DC76),
            accent2: NSColor(hex: 0x78DCE8),
            accent3: NSColor(hex: 0xFF6188),
            accent4: NSColor(hex: 0xAB9DF2),
            chrome: "dark"
        )
    ]

    public static let `default`: TerminalTheme = all[1] // midnight

    public static func byId(_ id: String) -> TerminalTheme {
        all.first { $0.id == id } ?? Self.default
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
