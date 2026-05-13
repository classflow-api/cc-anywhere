// DotGridBackground.swift
// Mirrors shared.jsx's DotGridBg: tiny dot pattern with a radial-fade mask.
// The slow horizontal drift is implemented with a TimelineView.

import SwiftUI

public struct DotGridBackground: View {
    let color: Color
    var size: CGFloat = 22
    var opacity: Double = 1.0
    var animate: Bool = true

    public init(color: Color, size: CGFloat = 22, opacity: Double = 1.0, animate: Bool = true) {
        self.color = color
        self.size = size
        self.opacity = opacity
        self.animate = animate
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animate)) { ctx in
            canvasView(time: ctx.date.timeIntervalSinceReferenceDate)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func canvasView(time: TimeInterval) -> some View {
        let phase = animate
            ? CGFloat(time.truncatingRemainder(dividingBy: 30) / 30) * size
            : 0
        let drawColor = color
        let cellSize = size
        let drawOpacity = opacity
        Canvas { gctx, size in
            let radius = max(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            gctx.opacity = drawOpacity
            let cols = Int(size.width / cellSize) + 2
            let rows = Int(size.height / cellSize) + 2
            for r in 0..<rows {
                for c in 0..<cols {
                    let x = CGFloat(c) * cellSize + phase - cellSize
                    let y = CGFloat(r) * cellSize
                    let dx = x - center.x, dy = y - center.y
                    let dist = sqrt(dx * dx + dy * dy)
                    let fade = max(0, 1 - (dist / radius))
                    let alpha = fade * fade
                    if alpha < 0.02 { continue }
                    let dot = Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1))
                    gctx.fill(dot, with: .color(drawColor.opacity(alpha)))
                }
            }
        }
    }
}
