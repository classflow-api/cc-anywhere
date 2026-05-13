// SecurityPane.swift

import SwiftUI

struct SecurityPane: View {
    @EnvironmentObject var preferences: PreferencesService
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        let palette = themeManager.palette
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("安全").font(AppFont.ui(size: 22, weight: .bold))
                        .foregroundColor(palette.text)
                    Text("证书信任、Token 与日志脱敏")
                        .font(AppFont.ui(size: 12.5))
                        .foregroundColor(palette.textMuted)
                }

                GlassCard(palette: palette) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("信任自签证书（仅限 Owner 自有 VPS）",
                               isOn: $preferences.serverConfig.trustSelfSigned)
                            .toggleStyle(.switch)
                            .foregroundColor(palette.text)
                        Text("开启后将信任 Server 提供的自签 TLS 证书。仅在你完全信任目标 VPS 时启用。")
                            .font(AppFont.ui(size: 11.5))
                            .foregroundColor(palette.textMuted)
                    }
                }

                GlassCard(palette: palette) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("日志脱敏")
                            .font(AppFont.ui(size: 13, weight: .semibold))
                            .foregroundColor(palette.text)
                        Text("日志中所有 token、sub_token、QR payload 均自动脱敏（前 6 字符 + *** + 后 4 字符）。")
                            .font(AppFont.ui(size: 11.5))
                            .foregroundColor(palette.textMuted)
                    }
                }

                GlassCard(palette: palette) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("文件权限")
                            .font(AppFont.ui(size: 13, weight: .semibold))
                            .foregroundColor(palette.text)
                        Text("所有配置文件 (tabs.json / server-config.json / last-pids.json) 写入 ~/Library/Application Support/cc-anywhere/，权限 0600。")
                            .font(AppFont.ui(size: 11.5))
                            .foregroundColor(palette.textMuted)
                    }
                }
            }
            .padding(28)
        }
    }
}
