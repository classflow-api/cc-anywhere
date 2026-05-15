// FileViewerState.swift
// 跨 view 共享的"当前打开文件"状态。FileExplorer 点击文件 → 设置 openFile；
// MainWindow 监听 openFile 决定是否渲染 FileViewerPanel。

import Foundation
import SwiftUI

@MainActor
public final class FileViewerState: ObservableObject {
    @Published public var openFile: URL?
    @Published public var panelWidth: CGFloat = 480

    public init() {}

    public func open(_ url: URL) {
        openFile = url
    }

    public func close() {
        openFile = nil
    }
}
