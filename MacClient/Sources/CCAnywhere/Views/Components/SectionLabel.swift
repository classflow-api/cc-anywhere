// SectionLabel.swift
// Mirrors shared.jsx's SectionLabel: small uppercase letter-spaced caption.

import SwiftUI

public struct SectionLabel: View {
    let text: String
    let palette: ColorPalette

    public init(_ text: String, palette: ColorPalette) {
        self.text = text
        self.palette = palette
    }

    public var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1.4)
            .foregroundColor(palette.textFaint)
    }
}
