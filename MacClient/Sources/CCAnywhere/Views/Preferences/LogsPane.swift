// LogsPane.swift

import SwiftUI
import AppKit

struct LogsPane: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var preferences: PreferencesService

    var body: some View {
        let palette = themeManager.palette
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("日志与诊断").font(AppFont.ui(size: 22, weight: .bold))
                        .foregroundColor(palette.text)
                    Text("查看运行日志，导出问题诊断包")
                        .font(AppFont.ui(size: 12.5))
                        .foregroundColor(palette.textMuted)
                }

                GlassCard(palette: palette) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("日志位置")
                            .font(AppFont.ui(size: 13, weight: .semibold))
                            .foregroundColor(palette.text)
                        Text(AppLogger.shared.currentLogFile.path)
                            .font(AppFont.mono(size: 11))
                            .foregroundColor(palette.textMuted)
                            .textSelection(.enabled)

                        HStack {
                            Button("打开日志窗口") {
                                AppDelegate.shared?.openLogViewer(nil)
                            }
                            Button("在 Finder 中显示") {
                                NSWorkspace.shared.activateFileViewerSelecting([
                                    AppLogger.shared.currentLogFile
                                ])
                            }
                        }
                    }
                }

                GlassCard(palette: palette) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("日志级别")
                            .font(AppFont.ui(size: 13, weight: .semibold))
                            .foregroundColor(palette.text)
                        Picker("", selection: Binding(
                            get: { AppLogger.shared.minLevel },
                            set: { AppLogger.shared.minLevel = $0 }
                        )) {
                            ForEach(LogLevel.allCases, id: \.self) { l in
                                Text(l.label.trimmingCharacters(in: .whitespaces)).tag(l)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .padding(28)
        }
    }
}
