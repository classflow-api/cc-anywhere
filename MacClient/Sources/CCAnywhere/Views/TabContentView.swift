// TabContentView.swift
// The view shown inside a Tab: SwiftTerm view (or an empty-state /
// process-exit banner) + the bottom command crumb mirror of the design.

import SwiftUI
import AppKit
import SwiftTerm

/// AppKit wrapper that lets us embed a LocalProcessTerminalView created by
/// ProcessHost. We resolve the view from the host at make-time so reuse is
/// stable across selection changes.
struct SwiftTermHost: NSViewRepresentable {
    let tabId: UUID
    let theme: TerminalTheme
    let fontSize: Int
    @EnvironmentObject var processHost: ProcessHost

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        attach(in: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        attach(in: container)
        applyTheme(container)
    }

    private func attach(in container: NSView) {
        // Wipe any previous subviews.
        for sub in container.subviews { sub.removeFromSuperview() }
        if let term = processHost.terminalsByTab[tabId] {
            term.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(term)
            NSLayoutConstraint.activate([
                term.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                term.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                term.topAnchor.constraint(equalTo: container.topAnchor),
                term.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
            applyTheme(container)
        }
    }

    private func applyTheme(_ container: NSView) {
        guard let term = container.subviews.first as? LocalProcessTerminalView else { return }
        // Background
        container.layer?.backgroundColor = theme.bg.cgColor
        term.nativeBackgroundColor = theme.bg
        term.nativeForegroundColor = theme.fg
        term.caretColor = theme.cursor
        term.selectedTextBackgroundColor = theme.selection
        term.font = AppFont.monoNSFont(size: CGFloat(fontSize))
        // Per-Tab 8-color ANSI palette is left at SwiftTerm defaults; the
        // theme's accent colors are honored implicitly because Claude Code
        // outputs explicit RGB sequences for highlighted spans.
        term.needsDisplay = true
    }
}

struct TabContentView: View {
    let tab: Tab
    @EnvironmentObject var processHost: ProcessHost
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var preferences: PreferencesService

    var body: some View {
        let palette = themeManager.palette
        let theme = themeManager.terminalTheme

        VStack(spacing: 10) {
            // Path crumb / status row
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .foregroundColor(palette.textMuted)
                        .font(.system(size: 11))
                    Text(humanPath(tab.folder.path))
                        .font(AppFont.mono(size: 12))
                        .foregroundColor(palette.textMuted)
                }
                Spacer()
                StatusPill(palette: palette, dotColor: dotColor(palette), accent: tab.status == .running) {
                    HStack(spacing: 4) {
                        Text("session").font(AppFont.ui(size: 11.5, weight: .semibold)).foregroundColor(palette.text)
                        Text("·").foregroundColor(palette.textFaint)
                        Text(tab.id.uuidString.prefix(8))
                            .font(AppFont.mono(size: 11.5))
                            .foregroundColor(palette.textMuted)
                    }
                }
                StatusPill(palette: palette) {
                    HStack(spacing: 4) {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 11))
                            .foregroundColor(palette.textMuted)
                        Text(theme.name)
                            .foregroundColor(palette.textMuted)
                    }
                }
            }
            .padding(.horizontal, 4)

            // Process error banner (M2)
            if tab.status == .error {
                processErrorBanner(palette: palette)
            }

            // SwiftTerm host
            SwiftTermHost(tabId: tab.id, theme: theme, fontSize: preferences.terminalFontSize)
                .background(theme.bgSwiftUI)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(palette.line, lineWidth: 1)
                )

            // Command crumb (mock prompt line per design's design)
            commandBar(palette: palette)
        }
        .padding(14)
        .background(palette.bg)
    }

    private func dotColor(_ palette: ColorPalette) -> SwiftUI.Color {
        switch tab.status {
        case .running: return palette.success
        case .error:   return palette.danger
        case .idle:    return palette.textFaint
        }
    }

    private func humanPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func processErrorBanner(palette: ColorPalette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(palette.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Code 进程已退出").font(AppFont.ui(size: 12, weight: .semibold))
                    .foregroundColor(palette.text)
                Text("退出码 \(tab.exitCode.map(String.init) ?? "?")")
                    .font(AppFont.ui(size: 11)).foregroundColor(palette.textMuted)
            }
            Spacer()
            Button(action: restart) {
                Text("重启").font(AppFont.ui(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(palette.accent)
                    .foregroundColor(palette.accentFg)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(palette.warn.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(palette.warn.opacity(0.30), lineWidth: 1)
                )
        )
    }

    private func commandBar(palette: ColorPalette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundColor(palette.accent)
            HStack(spacing: 4) {
                Text("❯").foregroundColor(palette.accent).font(AppFont.mono(size: 12))
                Text("点击终端窗口直接输入指令")
                    .font(AppFont.mono(size: 12))
                    .foregroundColor(palette.textMuted)
            }
            Spacer()
            Text("⌘K")
                .font(AppFont.ui(size: 11)).foregroundColor(palette.textFaint)
            Text("⌘↵")
                .font(AppFont.ui(size: 11)).foregroundColor(palette.textFaint)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.bgElev)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(palette.line, lineWidth: 1)
                )
        )
    }

    private func restart() {
        processHost.stopProcess(for: tab.id)
        processHost.startProcess(for: tab)
    }
}
