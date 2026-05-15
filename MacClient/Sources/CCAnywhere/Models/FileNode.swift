// FileNode.swift
// 文件树节点。支持按需 lazy 加载子节点（点击展开时才读盘），避免一次性
// 递归遍历大项目（如 node_modules）卡 UI。

import Foundation
import SwiftUI

@MainActor
public final class FileNode: ObservableObject, Identifiable {
    public let id: URL
    public let url: URL
    public let isDirectory: Bool
    public let name: String

    @Published public private(set) var children: [FileNode] = []
    @Published public private(set) var isLoaded: Bool = false
    @Published public var isExpanded: Bool = false

    /// 隐藏的目录名（常见构建产物 / IDE 配置 / 系统文件）。
    private static let ignored: Set<String> = [
        ".git", ".DS_Store", "node_modules", ".build", ".swiftpm",
        "Pods", ".idea", ".vscode", "__pycache__", "DerivedData",
        "build", ".gradle", ".dart_tool", "Package.resolved",
        ".next", ".nuxt", "dist", "out", ".turbo", ".cache",
        "target"
    ]

    public init(url: URL) {
        self.id = url
        self.url = url
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        self.isDirectory = isDir
        self.name = url.lastPathComponent
    }

    public func loadChildrenIfNeeded() {
        guard isDirectory, !isLoaded else { return }
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        // 不过滤 .开头文件（用户可能想看 .gitignore / .env.example），
        // 但过滤已知的"大目录 + IDE 噪音"
        let filtered = items.filter { !Self.ignored.contains($0.lastPathComponent) }
        let nodes = filtered.map { FileNode(url: $0) }
        // 文件夹优先 + 名字本地化排序
        children = nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        isLoaded = true
    }

    public func reload() {
        children = []
        isLoaded = false
        loadChildrenIfNeeded()
    }
}
