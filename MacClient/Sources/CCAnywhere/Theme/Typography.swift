// Typography.swift
// UI fonts: SF Pro / Inter for chrome; JetBrains Mono fallback for code/mono.

import SwiftUI
import AppKit

public enum AppFont {
    /// Returns a monospaced font, preferring JetBrains Mono if installed
    /// otherwise SF Mono.
    public static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let candidates = ["JetBrains Mono", "JetBrainsMono-Regular", "SF Mono", "Menlo"]
        for name in candidates {
            if NSFont(name: name, size: size) != nil {
                return Font.custom(name, size: size).weight(weight)
            }
        }
        return Font.system(size: size, weight: weight, design: .monospaced)
    }

    /// Returns the UI sans-serif font: SF Pro on macOS.
    public static func ui(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return Font.system(size: size, weight: weight, design: .default)
    }

    /// Monospaced NSFont used by SwiftTerm.
    public static func monoNSFont(size: CGFloat) -> NSFont {
        let candidates = ["JetBrains Mono", "JetBrainsMono-Regular", "SF Mono", "Menlo"]
        for name in candidates {
            if let f = NSFont(name: name, size: size) {
                return f
            }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
