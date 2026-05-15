// GeneralPane.swift

import SwiftUI
import AppKit

struct GeneralPane: View {
    @EnvironmentObject var preferences: PreferencesService
    @EnvironmentObject var themeManager: ThemeManager

    private static let intFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimum = 0
        f.maximum = 1_000_000_000
        return f
    }()

    var body: some View {
        let palette = themeManager.palette
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("通用").font(AppFont.ui(size: 22, weight: .bold))
                        .foregroundColor(palette.text)
                    Text("App 外观、启动行为等基础设置")
                        .font(AppFont.ui(size: 12.5))
                        .foregroundColor(palette.textMuted)
                }

                GlassCard(palette: palette) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("外观")
                            .font(AppFont.ui(size: 13, weight: .semibold))
                            .foregroundColor(palette.text)
                        Picker("", selection: $preferences.appearance) {
                            ForEach(AppAppearance.allCases) { a in
                                Text(a.displayName).tag(a)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("选「跟随系统」时 App 会随 macOS 外观自动切换；选「浅色」或「深色」则强制锁定。")
                            .font(AppFont.ui(size: 11))
                            .foregroundColor(palette.textMuted)
                    }
                }

                GlassCard(palette: palette) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Claude CLI 路径")
                            .font(AppFont.ui(size: 13, weight: .semibold))
                            .foregroundColor(palette.text)
                        Text("留空时自动搜索常见安装位置；如果 claude 装在非常规路径，可在此手动指定二进制绝对路径。")
                            .font(AppFont.ui(size: 11.5))
                            .foregroundColor(palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            TextField("/usr/local/bin/claude",
                                      text: $preferences.claudePathOverride)
                                .textFieldStyle(.roundedBorder)
                                .font(AppFont.mono(size: 12))
                            Button("浏览…") { chooseClaudeBinary() }
                                .buttonStyle(.bordered)
                        }
                        claudePathStatus(palette: palette)
                    }
                }

                GlassCard(palette: palette) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("路径与文件")
                            .font(AppFont.ui(size: 13, weight: .semibold))
                            .foregroundColor(palette.text)
                        infoRow("配置目录",
                                value: PreferencesService.appSupportDir.path,
                                palette: palette)
                        infoRow("图片 inbox",
                                value: ImageDownloader.inboxDir.path,
                                palette: palette)
                        infoRow("日志目录",
                                value: AppLogger.shared.logDirectory.path,
                                palette: palette)
                    }
                }
            }
            .padding(28)
        }
    }

    /// File-picker for the claude binary. Writes the absolute path back to
    /// `preferences.claudePathOverride`.
    private func chooseClaudeBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "选择 claude 可执行文件"
        if panel.runModal() == .OK, let url = panel.url {
            preferences.claudePathOverride = url.path
        }
    }

    /// Show a small status line indicating whether the configured (or
    /// auto-detected) claude binary is currently resolvable.
    private func claudePathStatus(palette: ColorPalette) -> some View {
        let fm = FileManager.default
        let override = preferences.claudePathOverride.trimmingCharacters(in: .whitespaces)
        let resolved: String?
        let isOverride: Bool
        if !override.isEmpty, fm.isExecutableFile(atPath: override) {
            resolved = override
            isOverride = true
        } else {
            resolved = ProcessHost.findClaudeBinary()
            isOverride = false
        }
        return HStack(spacing: 6) {
            Circle()
                .fill(resolved == nil ? palette.danger : palette.success)
                .frame(width: 7, height: 7)
            if let r = resolved {
                Text("当前使用：\(r)\(isOverride ? "（手动指定）" : "（自动检测）")")
                    .font(AppFont.mono(size: 11))
                    .foregroundColor(palette.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("未找到 claude。请安装 Claude Code CLI 或手动指定路径。")
                    .font(AppFont.ui(size: 11))
                    .foregroundColor(palette.danger)
            }
            Spacer()
        }
    }

    private func infoRow(_ label: String, value: String, palette: ColorPalette) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(AppFont.ui(size: 11.5))
                .foregroundColor(palette.textMuted)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(AppFont.mono(size: 11.5))
                .foregroundColor(palette.text)
                .textSelection(.enabled)
            Spacer()
        }
    }
}
