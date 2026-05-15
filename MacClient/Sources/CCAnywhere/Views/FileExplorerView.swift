// FileExplorerView.swift
// 工作区文件树。固定 220pt 宽，位于 Sidebar 和终端之间。
// 节点按需展开（点击 chevron 才读盘），右键菜单：在 Finder 中显示 / 用 VSCode 打开 / 复制路径。

import SwiftUI
import AppKit

struct FileExplorerView: View {
    let rootURL: URL
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var root: FileNode

    init(rootURL: URL) {
        self.rootURL = rootURL
        _root = StateObject(wrappedValue: FileNode(url: rootURL))
    }

    var body: some View {
        let palette = themeManager.palette
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundColor(palette.accent)
                Text(root.name)
                    .font(AppFont.ui(size: 11.5, weight: .semibold))
                    .foregroundColor(palette.text)
                    .lineLimit(1)
                Spacer()
                Button {
                    root.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundColor(palette.textMuted)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("刷新")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(palette.bgInset.opacity(0.5))
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.line).frame(height: 1)
            }

            // Tree
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(root.children) { child in
                        FileNodeRow(node: child, depth: 0, palette: palette)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(width: 220, alignment: .topLeading)
        .background(palette.bg.opacity(0.4))
        .overlay(
            Rectangle().fill(palette.line).frame(width: 1),
            alignment: .trailing
        )
        .onAppear {
            root.loadChildrenIfNeeded()
        }
    }
}

// MARK: - Row

private struct FileNodeRow: View {
    @ObservedObject var node: FileNode
    let depth: Int
    let palette: ColorPalette
    @EnvironmentObject var fileViewerState: FileViewerState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
                .contextMenu { contextMenu }
            if node.isExpanded {
                ForEach(node.children) { child in
                    FileNodeRow(node: child, depth: depth + 1, palette: palette)
                }
            }
        }
    }

    private var isOpenInViewer: Bool {
        fileViewerState.openFile == node.url
    }

    private var row: some View {
        HStack(spacing: 4) {
            if node.isDirectory {
                Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(palette.textFaint)
                    .frame(width: 12)
            } else {
                Color.clear.frame(width: 12)
            }
            Image(systemName: nodeIcon)
                .font(.system(size: 11))
                .foregroundColor(node.isDirectory ? palette.accent : palette.textMuted)
                .frame(width: 16)
            Text(node.name)
                .font(AppFont.ui(size: 11.5))
                .foregroundColor(palette.text)
                .lineLimit(1)
            Spacer()
        }
        .padding(.leading, CGFloat(depth * 12) + 8)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .background(isOpenInViewer ? palette.accentSoft : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if node.isDirectory {
                node.loadChildrenIfNeeded()
                withAnimation(.easeInOut(duration: 0.12)) {
                    node.isExpanded.toggle()
                }
            } else {
                // 单击文件：在右侧 FileViewerPanel 打开
                fileViewerState.open(node.url)
            }
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("在 Finder 中显示") {
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        }
        Button("用 VSCode 打开") {
            openInVSCode(node.url)
        }
        Divider()
        Button("复制路径") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.url.path, forType: .string)
        }
        if node.isDirectory {
            Divider()
            Button("刷新") { node.reload() }
        }
    }

    private func openInVSCode(_ url: URL) {
        // 通过 `open -a` 让 Launch Services 找 VSCode，比 hardcoded 路径更可靠
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Visual Studio Code", url.path]
        do {
            try process.run()
        } catch {
            // VSCode 未安装时友好提示
            let alert = NSAlert()
            alert.messageText = "无法打开 VSCode"
            alert.informativeText = "请确认已安装 Visual Studio Code（/Applications/Visual Studio Code.app）。\n错误：\(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }

    private var nodeIcon: String {
        if node.isDirectory {
            return node.isExpanded ? "folder.fill" : "folder"
        }
        let ext = (node.name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift", "ts", "tsx", "js", "jsx", "py", "go", "rs", "rb",
             "java", "kt", "dart", "c", "cpp", "h", "hpp", "m", "mm":
            return "doc.text"
        case "md", "markdown", "rst", "txt":
            return "doc.richtext"
        case "json", "yaml", "yml", "toml", "xml", "plist":
            return "list.bullet.indent"
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "icns":
            return "photo"
        case "mp4", "mov", "avi", "mkv":
            return "play.rectangle"
        case "pdf":
            return "doc.richtext.fill"
        case "zip", "tar", "gz", "bz2", "7z":
            return "archivebox"
        case "html", "htm", "css", "scss":
            return "globe"
        case "sh", "bash", "zsh":
            return "terminal"
        case "lock", "resolved":
            return "lock.doc"
        default:
            return "doc"
        }
    }
}
