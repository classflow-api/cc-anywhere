// ColorTokens.swift
// Mirrors window.CC_TOKENS from UI design (tokens.js)
//
// `oklch` values from the design are converted to approximate sRGB so we can
// represent them as `Color` in SwiftUI. We picked perceptually close hex
// values; this gives us the same visual hierarchy the prototype used while
// staying within macOS's color management.

import SwiftUI

public enum AppAppearance: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case light
    case dark
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

/// One palette = one mode (light/dark). Values mirror tokens.js keys.
public struct ColorPalette {
    public let bg: Color
    public let bgElev: Color
    public let bgInset: Color
    public let panel: Color
    public let line: Color
    public let lineStrong: Color
    public let text: Color
    public let textMuted: Color
    public let textFaint: Color
    public let accent: Color
    public let accentSoft: Color
    public let accentFg: Color
    public let success: Color
    public let warn: Color
    public let danger: Color
    public let glassTint: Color
    public let dotGrid: Color
    public let isDark: Bool

    // MARK: - presets

    /// Light palette (mirrors window.CC_TOKENS.light).
    public static let light = ColorPalette(
        bg: Color(hex: 0xF4F3EE),
        bgElev: Color(hex: 0xFFFFFF),
        bgInset: Color(hex: 0xECE9E1),
        panel: Color.white.opacity(0.70),
        line: Color(hex: 0x0F172A).opacity(0.08),
        lineStrong: Color(hex: 0x0F172A).opacity(0.14),
        text: Color(hex: 0x0C111C),
        textMuted: Color(hex: 0x4F5666),
        textFaint: Color(hex: 0x8A8F9C),
        // oklch(0.62 0.13 215) ~ a saturated teal-cyan
        accent: Color(hex: 0x1F8DAB),
        // oklch(0.92 0.06 215) ~ very light cyan
        accentSoft: Color(hex: 0xD8EDF3),
        accentFg: Color(hex: 0x0A2433),
        success: Color(hex: 0x4AA871),
        warn: Color(hex: 0xE0A050),
        danger: Color(hex: 0xD75A4A),
        glassTint: Color.white.opacity(0.55),
        dotGrid: Color(hex: 0x0F172A).opacity(0.06),
        isDark: false
    )

    /// Dark palette (mirrors window.CC_TOKENS.dark).
    public static let dark = ColorPalette(
        bg: Color(hex: 0x0B0E14),
        bgElev: Color(hex: 0x11151D),
        bgInset: Color(hex: 0x070910),
        panel: Color(hex: 0x141A24).opacity(0.6),
        line: Color.white.opacity(0.07),
        lineStrong: Color.white.opacity(0.14),
        text: Color(hex: 0xE9EDF5),
        textMuted: Color(hex: 0x9098A8),
        textFaint: Color(hex: 0x5A6172),
        // oklch(0.78 0.13 200) ~ bright cyan
        accent: Color(hex: 0x6FD3E3),
        // oklch(0.30 0.08 200) ~ dim cyan
        accentSoft: Color(hex: 0x1A3942),
        accentFg: Color(hex: 0xE9F7FB),
        success: Color(hex: 0x6BE0A1),
        warn: Color(hex: 0xE9C26C),
        danger: Color(hex: 0xF07868),
        glassTint: Color.white.opacity(0.05),
        dotGrid: Color.white.opacity(0.05),
        isDark: true
    )
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
