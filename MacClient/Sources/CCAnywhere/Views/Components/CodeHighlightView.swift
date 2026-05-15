// CodeHighlightView.swift
// Highlightr 包到 NSViewRepresentable —— 把代码高亮成 NSAttributedString
// 后放进 NSTextView 显示（带原生滚动 + 文本选择 + 行环绕禁用横向滚动）。
// 比 SwiftUI 自己的 LazyVStack/Text 方案性能好，文件几千行也不卡。

import SwiftUI
import AppKit
import Highlightr
import MarkdownUI

struct CodeHighlightView: NSViewRepresentable {
    let content: String
    let language: String?
    let isDark: Bool
    let fontSize: CGFloat

    init(content: String, language: String?, isDark: Bool, fontSize: CGFloat = 12) {
        self.content = content
        self.language = language
        self.isDark = isDark
        self.fontSize = fontSize
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.allowsUndo = false
        textView.isRichText = true
        textView.usesFontPanel = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = []
        textView.textContainer?.containerSize = NSSize(width: 1_000_000, height: 1_000_000)
        textView.textContainer?.widthTracksTextView = false  // 不自动换行，启用横向滚动
        textView.maxSize = NSSize(width: 1_000_000, height: 1_000_000)

        scrollView.documentView = textView
        applyContent(to: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        applyContent(to: textView)
    }

    private func applyContent(to textView: NSTextView) {
        let highlightr = HighlightrCache.shared
        highlightr?.setTheme(to: isDark ? "atom-one-dark" : "atom-one-light")
        // 强制覆盖字号
        highlightr?.theme.codeFont = NSFont.monospacedSystemFont(
            ofSize: fontSize, weight: .regular
        )
        let attr: NSAttributedString
        if let highlighted = highlightr?.highlight(content, as: language, fastRender: true) {
            attr = highlighted
        } else {
            attr = NSAttributedString(
                string: content,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                    .foregroundColor: isDark ? NSColor.white : NSColor.black
                ]
            )
        }
        textView.textStorage?.setAttributedString(attr)
        textView.backgroundColor = isDark
            ? NSColor(red: 0.04, green: 0.07, blue: 0.10, alpha: 1.0)
            : NSColor.white
    }
}

/// 跨 view 共享 Highlightr 实例：初始化 highlight.js 有 ~50ms 开销，
/// 每次创建新 view 都重建会卡顿。SwiftUI updates 串行在 main thread，
/// 单 instance 无并发访问，所以即使 Highlightr 非线程安全也 OK。
final class HighlightrCache {
    static let shared: Highlightr? = Highlightr()
}

// MARK: - MarkdownUI Code Block 语法高亮适配

/// MarkdownUI 的 `CodeSyntaxHighlighter` 实现：让 Markdown 内 ```lang ``` 代码块也用 highlightr。
public struct HighlightrCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    let isDark: Bool
    let fontSize: CGFloat

    public init(isDark: Bool, fontSize: CGFloat = 12) {
        self.isDark = isDark
        self.fontSize = fontSize
    }

    public func highlightCode(_ content: String, language: String?) -> Text {
        guard let highlightr = HighlightrCache.shared else {
            return Text(content)
                .font(.system(size: fontSize, design: .monospaced))
        }
        highlightr.setTheme(to: isDark ? "atom-one-dark" : "atom-one-light")
        highlightr.theme.codeFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if let ns = highlightr.highlight(content, as: language, fastRender: true) {
            return Text(AttributedString(ns))
        }
        return Text(content)
            .font(.system(size: fontSize, design: .monospaced))
    }
}

public extension CodeSyntaxHighlighter where Self == HighlightrCodeSyntaxHighlighter {
    static func highlightr(isDark: Bool, fontSize: CGFloat = 12) -> Self {
        HighlightrCodeSyntaxHighlighter(isDark: isDark, fontSize: fontSize)
    }
}

/// URL 扩展名 → Highlight.js 语言标识。
/// 列表参考 https://github.com/highlightjs/highlight.js/blob/main/SUPPORTED_LANGUAGES.md
enum CodeLanguageMapper {
    static func language(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        // 特殊文件名
        let name = url.lastPathComponent.lowercased()
        if name == "dockerfile" || name.hasPrefix("dockerfile") { return "dockerfile" }
        if name == "makefile" { return "makefile" }
        if name == "package.json" || name == "tsconfig.json" { return "json" }
        if name.hasSuffix(".gitignore") || name == ".gitignore" { return "bash" }

        switch ext {
        case "swift": return "swift"
        case "m", "mm": return "objectivec"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp", "hxx": return "cpp"
        case "rs": return "rust"
        case "go": return "go"
        case "kt", "kts": return "kotlin"
        case "java": return "java"
        case "dart": return "dart"
        case "py": return "python"
        case "rb": return "ruby"
        case "php": return "php"
        case "ts", "tsx": return "typescript"
        case "js", "jsx", "mjs", "cjs": return "javascript"
        case "vue": return "html"  // hljs 把 vue 当 html 处理（含 <script> + <style>）
        case "html", "htm", "xhtml": return "html"
        case "css": return "css"
        case "scss", "sass": return "scss"
        case "less": return "less"
        case "json", "json5": return "json"
        case "yaml", "yml": return "yaml"
        case "toml": return "toml"
        case "xml", "plist", "xcconfig": return "xml"
        case "sh", "bash", "zsh": return "bash"
        case "fish": return "shell"
        case "ps1": return "powershell"
        case "sql": return "sql"
        case "graphql", "gql": return "graphql"
        case "proto": return "protobuf"
        case "md", "markdown": return "markdown"  // 不用走这里，.md 走 MarkdownUI
        case "ini", "cfg", "conf": return "ini"
        case "lua": return "lua"
        case "scala": return "scala"
        case "ex", "exs": return "elixir"
        case "erl": return "erlang"
        case "clj", "cljs": return "clojure"
        case "elm": return "elm"
        case "fs", "fsx": return "fsharp"
        case "groovy", "gradle": return "groovy"
        case "haml": return "haml"
        case "hs": return "haskell"
        case "jl": return "julia"
        case "nim": return "nim"
        case "ml", "mli": return "ocaml"
        case "pl", "pm": return "perl"
        case "r": return "r"
        case "tex": return "latex"
        case "vim": return "vim"
        case "zig": return "zig"
        case "tf", "tfvars": return "hcl"  // terraform
        case "dockerfile": return "dockerfile"
        case "log": return "accesslog"
        default: return nil  // 让 highlight.js 自动检测
        }
    }
}
