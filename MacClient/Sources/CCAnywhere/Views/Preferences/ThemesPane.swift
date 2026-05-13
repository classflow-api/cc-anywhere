// ThemesPane.swift
// Mirrors design's preferences > 终端主题 pane with 6 preset cards.

import SwiftUI

struct ThemesPane: View {
    @EnvironmentObject var preferences: PreferencesService
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        let palette = themeManager.palette
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("终端主题")
                            .font(AppFont.ui(size: 22, weight: .bold))
                            .foregroundColor(palette.text)
                        Text("给 Claude Code 选一身合身的衣裳 · 切换实时生效")
                            .font(AppFont.ui(size: 12.5))
                            .foregroundColor(palette.textMuted)
                    }
                    Spacer()
                    StatusPill(palette: palette) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                                .foregroundColor(palette.accent)
                            Text(themeManager.terminalTheme.name)
                                .foregroundColor(palette.text)
                                .font(AppFont.ui(size: 11.5, weight: .semibold))
                            Text("当前").foregroundColor(palette.textMuted)
                        }
                    }
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    spacing: 14
                ) {
                    ForEach(TerminalThemes.all) { t in
                        ThemeCard(theme: t,
                                  palette: palette,
                                  isSelected: t.id == preferences.terminalThemeId,
                                  onPick: { preferences.terminalThemeId = t.id })
                    }
                }

                // Misc controls
                GlassCard(padding: 18, palette: palette) {
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("跟随系统外观")
                                .font(AppFont.ui(size: 13, weight: .semibold))
                                .foregroundColor(palette.text)
                            Text("白天浅色主题, 夜晚自动切换到深色")
                                .font(AppFont.ui(size: 11.5))
                                .foregroundColor(palette.textMuted)
                        }
                        Spacer()
                        Toggle("", isOn: $preferences.followSystemAppearance)
                            .toggleStyle(.switch).labelsHidden()
                        Rectangle().fill(palette.line).frame(width: 1, height: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("字号").font(AppFont.ui(size: 13, weight: .semibold))
                                .foregroundColor(palette.text)
                            Text("JetBrains Mono · \(preferences.terminalFontSize)pt")
                                .font(AppFont.ui(size: 11.5))
                                .foregroundColor(palette.textMuted)
                        }
                        HStack(spacing: 8) {
                            ForEach([11, 12, 13, 14, 16], id: \.self) { s in
                                Button {
                                    preferences.terminalFontSize = s
                                } label: {
                                    Text("\(s)")
                                        .font(AppFont.ui(size: 11, weight: .semibold))
                                        .frame(width: 26, height: 26)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(s == preferences.terminalFontSize ? palette.accent : palette.bgInset)
                                        )
                                        .foregroundColor(s == preferences.terminalFontSize ? palette.accentFg : palette.textMuted)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
    }
}

// MARK: - Theme card

private struct ThemeCard: View {
    let theme: TerminalTheme
    let palette: ColorPalette
    let isSelected: Bool
    let onPick: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Preview pane
            ZStack(alignment: .topLeading) {
                Rectangle().fill(theme.bgSwiftUI)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle().fill(Color(hex: 0xFF5F57)).frame(width: 6, height: 6).opacity(0.6)
                        Circle().fill(Color(hex: 0xFEBC2E)).frame(width: 6, height: 6).opacity(0.6)
                        Circle().fill(Color(hex: 0x28C840)).frame(width: 6, height: 6).opacity(0.6)
                    }.padding(.bottom, 4)
                    Text("● Claude")
                        .font(AppFont.mono(size: 9.5, weight: .semibold))
                        .foregroundColor(theme.accent2SwiftUI)
                    Text("读取 scheduler.ts")
                        .font(AppFont.mono(size: 9.5))
                        .foregroundColor(theme.dimSwiftUI)
                    HStack(spacing: 4) {
                        Text("const").foregroundColor(theme.accent4SwiftUI)
                        Text("queue").foregroundColor(theme.accent1SwiftUI)
                        Text("= new").foregroundColor(theme.accent4SwiftUI)
                        Text("MinHeap();").foregroundColor(theme.accent2SwiftUI)
                    }.font(AppFont.mono(size: 9.5))
                    HStack(spacing: 2) {
                        Text("❯").foregroundColor(theme.accent3SwiftUI)
                        Text("继续").foregroundColor(theme.fgSwiftUI)
                        Rectangle().fill(theme.cursorSwiftUI)
                            .frame(width: 4, height: 9)
                    }.font(AppFont.mono(size: 9.5))
                }
                .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))

                // color swatches at bottom
                let swatches: [NSColor] = [
                    theme.accent1, theme.accent2, theme.accent3,
                    theme.accent4, theme.cursor
                ]
                VStack {
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(swatches.indices, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(swatches[i]))
                                .frame(height: 6)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
            .frame(height: 150)

            // meta row
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.name)
                        .font(AppFont.ui(size: 13, weight: .semibold))
                        .foregroundColor(palette.text)
                    Text(theme.subtitle)
                        .font(AppFont.ui(size: 10.5))
                        .foregroundColor(palette.textFaint)
                }
                Spacer()
                if isSelected {
                    ZStack {
                        Circle().fill(palette.accent).frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(palette.accentFg)
                    }
                }
            }
            .padding(10)
            .background(palette.bgElev)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? palette.accent : palette.line,
                        lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: isSelected ? palette.accent.opacity(0.4) : .clear,
                radius: isSelected ? 24 : 0, y: isSelected ? 12 : 0)
        .offset(y: isSelected ? -2 : 0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .onTapGesture(perform: onPick)
    }
}

// NSColor already conforms to Hashable in AppKit; we don't need to extend it.
// The previous `ForEach` over [NSColor] uses `.self`, which requires
// Hashable/Identifiable. We address this in-line in the ForEach above.
