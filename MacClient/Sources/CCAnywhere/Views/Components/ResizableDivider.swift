// ResizableDivider.swift
// 可拖动的垂直分隔条。鼠标悬停变成左右调整光标，拖动时通过 binding 改 width。

import SwiftUI
import AppKit

struct ResizableDivider: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let palette: ColorPalette
    /// 拖动方向：true = 拖右扩展 width 增大；false = 拖右扩展 width 减小
    /// （取决于分隔条相对面板的位置：面板在右 → false；面板在左 → true）
    let invert: Bool

    init(width: Binding<CGFloat>,
         minWidth: CGFloat = 280,
         maxWidth: CGFloat = 1200,
         palette: ColorPalette,
         invert: Bool = false) {
        self._width = width
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.palette = palette
        self.invert = invert
    }

    var body: some View {
        Rectangle()
            .fill(palette.line)
            .frame(width: 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let delta = invert ? value.translation.width : -value.translation.width
                        let proposed = width + delta
                        width = max(minWidth, min(maxWidth, proposed))
                    }
            )
    }
}
