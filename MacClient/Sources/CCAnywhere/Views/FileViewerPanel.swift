// FileViewerPanel.swift
// 终端右侧的文件阅读器。点击文件树文件时打开，可关闭，可调宽度。
// 支持：
//   - 文本（.swift/.js/.ts/.vue/.html/.css/.json/.yaml/.py/.go/.java/.kt/.dart/.md/...）：
//     ScrollView + LazyVStack 显示等宽字体 + 行号
//   - Markdown：AttributedString(markdown:) 渲染
//   - 图片（.png/.jpg/.gif/.webp/.svg/.icns）：Image(nsImage:)
//   - 大文件 (>5MB) / 二进制：友好提示，引导去 VSCode 打开

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MarkdownUI

struct FileViewerPanel: View {
    let url: URL
    let onClose: () -> Void
    @EnvironmentObject var themeManager: ThemeManager

    @State private var loadResult: LoadResult = .loading
    @State private var renderMode: RenderMode = .text

    enum RenderMode {
        case text       // 普通源码 / 配置 / 纯文本
        case markdown   // .md
        case image      // 图片
        case unsupported(reason: String)
    }

    enum LoadResult {
        case loading
        case textContent(String)
        case imageContent(NSImage)
        case error(String)
    }

    var body: some View {
        let palette = themeManager.palette
        VStack(spacing: 0) {
            header(palette: palette)
            Divider().background(palette.line)
            content(palette: palette)
        }
        .background(palette.bgElev)
        .onAppear { load() }
        .onChange(of: url) { _, _ in load() }
    }

    // MARK: - Header

    private func header(palette: ColorPalette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 12))
                .foregroundColor(palette.accent)
            Text(url.lastPathComponent)
                .font(AppFont.ui(size: 12.5, weight: .semibold))
                .foregroundColor(palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(url.deletingLastPathComponent().lastPathComponent)
                .font(AppFont.mono(size: 10.5))
                .foregroundColor(palette.textFaint)
                .lineLimit(1)
            Spacer()
            actionButton(systemName: "folder",
                         tooltip: "在 Finder 中显示",
                         palette: palette) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            actionButton(systemName: "arrow.up.right.square",
                         tooltip: "用 VSCode 打开",
                         palette: palette) {
                openInVSCode()
            }
            actionButton(systemName: "xmark",
                         tooltip: "关闭",
                         palette: palette,
                         action: onClose)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(palette.bgInset.opacity(0.6))
    }

    private func actionButton(systemName: String,
                              tooltip: String,
                              palette: ColorPalette,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundColor(palette.textMuted)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    // MARK: - Content

    @ViewBuilder
    private func content(palette: ColorPalette) -> some View {
        switch loadResult {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let msg):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundColor(palette.warn)
                Text(msg)
                    .font(AppFont.ui(size: 12))
                    .foregroundColor(palette.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                Button("用 VSCode 打开") { openInVSCode() }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .textContent(let text):
            switch renderMode {
            case .markdown:
                markdownView(text, palette: palette)
            case .text, .image, .unsupported:
                CodeHighlightView(
                    content: text,
                    language: CodeLanguageMapper.language(for: url),
                    isDark: palette.isDark
                )
            }
        case .imageContent(let img):
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(12)
            }
        }
    }

    // Markdown 渲染：用 swift-markdown-ui，支持 GFM + 代码块（自带语法高亮）+ 表格 + 链接 + 图片
    private func markdownView(_ text: String, palette: ColorPalette) -> some View {
        ScrollView(showsIndicators: true) {
            Markdown(text)
                .markdownTheme(.gitHub)
                .markdownCodeSyntaxHighlighter(.highlightr(isDark: palette.isDark))
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .background(palette.isDark ? Color(red: 0.04, green: 0.07, blue: 0.10) : Color.white)
        .environment(\.colorScheme, palette.isDark ? .dark : .light)
    }

    // MARK: - Load

    private func load() {
        loadResult = .loading
        renderMode = detectMode(for: url)

        // 大小检查（避免一次性吃内存）
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let MAX_SIZE = 5 * 1024 * 1024
        if size > MAX_SIZE {
            loadResult = .error("文件过大（\(size / 1024 / 1024) MB）。\n建议用 VSCode 打开。")
            return
        }

        switch renderMode {
        case .image:
            if let img = NSImage(contentsOf: url) {
                loadResult = .imageContent(img)
            } else {
                loadResult = .error("无法解码图片")
            }
        case .unsupported(let reason):
            loadResult = .error(reason)
        case .text, .markdown:
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                loadResult = .textContent(text)
            } catch {
                // 尝试其他常见编码
                if let data = try? Data(contentsOf: url),
                   let text = String(data: data, encoding: .isoLatin1) {
                    loadResult = .textContent(text)
                } else {
                    loadResult = .error("无法以文本读取：\(error.localizedDescription)\n（可能是二进制文件）")
                }
            }
        }
    }

    private func detectMode(for url: URL) -> RenderMode {
        let ext = url.pathExtension.lowercased()
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "heic", "ico", "icns"]
        if imageExts.contains(ext) {
            return .image
        }
        if ext == "md" || ext == "markdown" {
            return .markdown
        }
        // PDF / 压缩 / 音视频 等不直接预览
        let unsupportedExts: Set<String> = ["pdf", "zip", "tar", "gz", "bz2", "7z", "rar",
                                             "mp4", "mov", "avi", "mkv", "mp3", "wav", "flac",
                                             "framework", "dmg", "pkg", "app", "ipa", "apk"]
        if unsupportedExts.contains(ext) {
            return .unsupported(reason: "此类型不支持内置预览。\n请用 VSCode 或对应工具打开。")
        }
        return .text
    }

    private var iconName: String {
        switch renderMode {
        case .markdown: return "doc.richtext"
        case .image: return "photo"
        case .unsupported: return "doc.questionmark"
        case .text:
            let ext = url.pathExtension.lowercased()
            switch ext {
            case "json", "yaml", "yml", "toml", "xml", "plist":
                return "list.bullet.indent"
            case "sh", "bash", "zsh":
                return "terminal"
            case "html", "css", "scss":
                return "globe"
            default:
                return "doc.text"
            }
        }
    }

    private func openInVSCode() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Visual Studio Code", url.path]
        do {
            try process.run()
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法打开 VSCode"
            alert.informativeText = "请确认已安装 Visual Studio Code。"
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
