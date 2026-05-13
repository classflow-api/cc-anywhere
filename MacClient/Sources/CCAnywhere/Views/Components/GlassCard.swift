// GlassCard.swift
// Mirrors shared.jsx's GlassCard: rounded panel with backdrop blur, line
// border, soft shadow. On macOS we use NSVisualEffectView via .ultraThinMaterial.

import SwiftUI

public struct GlassCard<Content: View>: View {
    let padding: CGFloat
    let glow: Bool
    let palette: ColorPalette
    let content: () -> Content

    public init(padding: CGFloat = 16,
                glow: Bool = false,
                palette: ColorPalette,
                @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.glow = glow
        self.palette = palette
        self.content = content
    }

    public var body: some View {
        content()
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(palette.panel)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(palette.line, lineWidth: 1)
            )
            .shadow(
                color: glow ? palette.accent.opacity(0.35) : .black.opacity(0.04),
                radius: glow ? 24 : 4,
                x: 0,
                y: glow ? 12 : 1
            )
    }
}
