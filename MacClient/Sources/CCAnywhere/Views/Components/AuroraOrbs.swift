// AuroraOrbs.swift
// Mirrors shared.jsx's AuroraOrbs: 3 large blurred circles drifting slowly.

import SwiftUI

public struct AuroraOrbs: View {
    public enum Tone { case cyan, warm }
    let tone: Tone

    @State private var t1: Double = 0
    @State private var t2: Double = 0
    @State private var t3: Double = 0

    public init(tone: Tone = .cyan) { self.tone = tone }

    public var body: some View {
        let palette: [Color]
        switch tone {
        case .cyan: palette = [
            Color(hex: 0x4FD3E8).opacity(0.5),
            Color(hex: 0x6BE0A1).opacity(0.4),
            Color(hex: 0x68A1F2).opacity(0.4)
        ]
        case .warm: palette = [
            Color(hex: 0xE9C26C).opacity(0.35),
            Color(hex: 0xF07868).opacity(0.30),
            Color(hex: 0x9A7BF2).opacity(0.30)
        ]
        }
        return GeometryReader { geo in
            ZStack {
                orb(color: palette[0], radius: 260, position: CGPoint(x: geo.size.width*0.1, y: geo.size.height*0.1), offset: t1)
                orb(color: palette[1], radius: 230, position: CGPoint(x: geo.size.width*0.9, y: geo.size.height*0.9), offset: t2)
                orb(color: palette[2], radius: 160, position: CGPoint(x: geo.size.width*0.75, y: geo.size.height*0.35), offset: t3)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) { t1 = 1 }
                withAnimation(.easeInOut(duration: 22).repeatForever(autoreverses: true)) { t2 = 1 }
                withAnimation(.easeInOut(duration: 28).repeatForever(autoreverses: true)) { t3 = 1 }
            }
        }
        .allowsHitTesting(false)
    }

    private func orb(color: Color, radius: CGFloat, position: CGPoint, offset: Double) -> some View {
        Circle()
            .fill(color)
            .frame(width: radius*2, height: radius*2)
            .blur(radius: 80)
            .position(
                x: position.x + CGFloat(offset) * 40 - 20,
                y: position.y + CGFloat(offset) * 30 - 15
            )
    }
}
