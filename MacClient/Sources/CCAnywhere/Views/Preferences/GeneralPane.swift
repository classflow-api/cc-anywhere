// GeneralPane.swift

import SwiftUI

struct GeneralPane: View {
    @EnvironmentObject var preferences: PreferencesService
    @EnvironmentObject var themeManager: ThemeManager

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
                    VStack(alignment: .leading, spacing: 16) {
                        Text("外观")
                            .font(AppFont.ui(size: 13, weight: .semibold))
                            .foregroundColor(palette.text)
                        Picker("", selection: $preferences.appearance) {
                            ForEach(AppAppearance.allCases) { a in
                                Text(a.displayName).tag(a)
                            }
                        }
                        .pickerStyle(.segmented)
                        Toggle("跟随系统外观自动切换", isOn: $preferences.followSystemAppearance)
                            .toggleStyle(.switch)
                            .foregroundColor(palette.text)
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
