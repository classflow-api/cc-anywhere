// StatusPill.swift
// Mirrors shared.jsx's StatusPill: a small rounded pill with an optional
// PulseDot and text content.

import SwiftUI

public struct StatusPill<Content: View>: View {
    let palette: ColorPalette
    let dotColor: SwiftUI.Color?
    let accent: Bool
    let content: () -> Content

    public init(palette: ColorPalette,
                dotColor: SwiftUI.Color? = nil,
                accent: Bool = false,
                @ViewBuilder content: @escaping () -> Content) {
        self.palette = palette
        self.dotColor = dotColor
        self.accent = accent
        self.content = content
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let dot = dotColor {
                PulseDot(color: dot, size: 6, pulse: accent)
            }
            content()
                .font(AppFont.ui(size: 11.5, weight: .medium))
                .foregroundColor(palette.textMuted)
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(
            Capsule()
                .fill(palette.bgInset)
                .overlay(Capsule().stroke(palette.line, lineWidth: 1))
        )
    }
}
