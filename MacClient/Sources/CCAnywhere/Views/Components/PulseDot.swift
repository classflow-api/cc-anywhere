// PulseDot.swift
// Mirrors shared.jsx's PulseDot: a small filled dot with an outward "pulse"
// halo. Used everywhere status is shown.

import SwiftUI

public struct PulseDot: View {
    public let color: Color
    public var size: CGFloat = 8
    public var pulse: Bool = true

    @State private var animateScale: CGFloat = 1.0
    @State private var animateOpacity: Double = 0.4

    public init(color: Color, size: CGFloat = 8, pulse: Bool = true) {
        self.color = color
        self.size = size
        self.pulse = pulse
    }

    public var body: some View {
        ZStack {
            if pulse {
                Circle()
                    .fill(color)
                    .frame(width: size + 4, height: size + 4)
                    .scaleEffect(animateScale)
                    .opacity(animateOpacity)
                    .onAppear {
                        withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                            animateScale = 1.9
                            animateOpacity = 0
                        }
                    }
            }
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.7), radius: 4)
        }
        .frame(width: size + 4, height: size + 4)
    }
}
