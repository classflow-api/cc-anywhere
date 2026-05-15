// LogoMark.swift
// SwiftUI 版「遥指」logo —— 与 AppIcon.icns 的「Prompt · Beacon」主推方案视觉一致：
// 圆角方块背景径向蓝紫渐变 + chevron + 圆点 + 同心弧 (青→紫线性渐变)

import SwiftUI

public struct LogoMark: View {
    public let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            // 背景：圆角 squircle + 径向渐变（亮蓝顶左 → 深海军底右）
            RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.22, green: 0.40, blue: 0.66),
                            Color(red: 0.04, green: 0.07, blue: 0.17)
                        ],
                        center: UnitPoint(x: 0.30, y: 0.25),
                        startRadius: 0,
                        endRadius: size * 0.95
                    )
                )

            // 前景：chevron + dot + arc，用 Canvas 一次性绘制后 clip + 渐变填充
            Canvas { ctx, canvasSize in
                let s = canvasSize.width / 200.0  // 200×200 设计坐标系

                let fgGradient = Gradient(colors: [
                    Color(red: 0.64, green: 0.92, blue: 1.00),   // 亮青
                    Color(red: 0.61, green: 0.43, blue: 1.00)    // 紫
                ])
                let gradStart = CGPoint(x: 20 * s, y: 40 * s)
                let gradEnd   = CGPoint(x: 180 * s, y: 160 * s)

                // chevron + dot：full opacity
                var solid = Path()
                var chev = Path()
                chev.move(to:    CGPoint(x: 62 * s,  y: 70 * s))
                chev.addLine(to: CGPoint(x: 106 * s, y: 100 * s))
                chev.addLine(to: CGPoint(x: 62 * s,  y: 130 * s))
                solid.addPath(chev.strokedPath(StrokeStyle(
                    lineWidth: 20 * s, lineCap: .round, lineJoin: .round
                )))
                solid.addEllipse(in: CGRect(
                    x: (142 - 12) * s, y: (100 - 12) * s,
                    width: 24 * s, height: 24 * s
                ))
                ctx.fill(solid, with: .linearGradient(
                    fgGradient, startPoint: gradStart, endPoint: gradEnd
                ))

                // arc：opacity 0.6
                var arc = Path()
                arc.move(to: CGPoint(x: 158 * s, y: 88 * s))
                arc.addQuadCurve(
                    to: CGPoint(x: 158 * s, y: 112 * s),
                    control: CGPoint(x: 170 * s, y: 100 * s)
                )
                let strokedArc = arc.strokedPath(StrokeStyle(
                    lineWidth: 5 * s, lineCap: .round, lineJoin: .round
                ))
                ctx.opacity = 0.6
                ctx.fill(strokedArc, with: .linearGradient(
                    fgGradient, startPoint: gradStart, endPoint: gradEnd
                ))
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }
}
