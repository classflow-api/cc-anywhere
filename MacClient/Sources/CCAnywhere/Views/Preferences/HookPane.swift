// HookPane.swift
// 偏好面板"远程 Hook"页：管理两个开关——
//   1. 启用远程 hook（M1-M3）—— 主开关，写 ~/.claude/settings.json
//   2. 启用工具批准远程化（M4）—— 子开关，依赖主开关
//
// 业务规则映射（见 需求规格说明书 §3.1 F6）：
//   R-F6-001：首次启动 OFF→ON 弹许可弹窗；"暂不启用"会回滚 + 置标志位
//   R-F6-002：主开关 ON→OFF 会 uninstall 并自动把 M4 关闭
//   R-F6-003：主开关 OFF 时 M4 toggle 禁用 + 灰显
//   R-F6-004：状态持久化由 HookPreferencesService 负责（UserDefaults plist）

import SwiftUI
import AppKit

struct HookPane: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var hookPrefs: HookPreferencesService
    @EnvironmentObject var container: DependencyContainer

    /// 当 toggle 内部因业务规则强制回滚时，避免再次触发 onChange 形成回环。
    @State private var suppressMainOnChange = false
    @State private var suppressM4OnChange = false

    /// 最近一次写盘错误，向用户展示。
    @State private var lastError: String? = nil

    var body: some View {
        let palette = themeManager.palette
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(palette: palette)
                mainToggleCard(palette: palette)
                m4ToggleCard(palette: palette)
                infoCard(palette: palette)
                if let err = lastError {
                    errorCard(err, palette: palette)
                }
            }
            .padding(28)
        }
    }

    // MARK: - Sections

    private func header(palette: ColorPalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("远程 Hook").font(AppFont.ui(size: 22, weight: .bold))
                .foregroundColor(palette.text)
            Text("控制 Claude 的提问与工具批准是否远程化到手机端")
                .font(AppFont.ui(size: 12.5))
                .foregroundColor(palette.textMuted)
        }
    }

    private func mainToggleCard(palette: ColorPalette) -> some View {
        GlassCard(palette: palette) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("启用远程 hook（M1-M3）",
                       isOn: $hookPrefs.enableRemoteHook)
                    .toggleStyle(.switch)
                    .foregroundColor(palette.text)
                    .onChange(of: hookPrefs.enableRemoteHook) { _, newValue in
                        guard !suppressMainOnChange else { return }
                        handleMainToggleChange(newValue: newValue)
                    }
                Text("开启后 cc-anywhere 会在 ~/.claude/settings.json 中注册 PreToolUse / PostToolUse / Notification hook，把 Claude 的提问与活动事件实时推送到手机端。关闭即卸载所有 cc-anywhere 写入的条目。")
                    .font(AppFont.ui(size: 11.5))
                    .foregroundColor(palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func m4ToggleCard(palette: ColorPalette) -> some View {
        let disabled = !hookPrefs.enableRemoteHook
        return GlassCard(palette: palette) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("启用工具批准远程化（M4）",
                       isOn: $hookPrefs.enableToolApprovalRemote)
                    .toggleStyle(.switch)
                    .foregroundColor(palette.text)
                    .disabled(disabled)
                    .onChange(of: hookPrefs.enableToolApprovalRemote) { _, newValue in
                        guard !suppressM4OnChange else { return }
                        handleM4ToggleChange(newValue: newValue)
                    }
                Text("开启后，Claude 对 Bash / Write / Edit 工具的调用将走远程批准流程（手机端弹卡片「批准 / 拒绝」）。仅当主开关 ON 时可启用。")
                    .font(AppFont.ui(size: 11.5))
                    .foregroundColor(disabled ? palette.textMuted.opacity(0.6) : palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(disabled ? 0.55 : 1.0)
    }

    private func infoCard(palette: ColorPalette) -> some View {
        GlassCard(palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                Text("说明")
                    .font(AppFont.ui(size: 13, weight: .semibold))
                    .foregroundColor(palette.text)
                Text("cc-anywhere 仅追加自己的 hook 条目，不会修改你已有的其他 hook 配置；每次写入前会自动备份 settings.json 到 ~/Library/Application Support/cc-anywhere/backups/（保留最近 5 份）。")
                    .font(AppFont.ui(size: 11.5))
                    .foregroundColor(palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func errorCard(_ message: String, palette: ColorPalette) -> some View {
        GlassCard(palette: palette) {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(palette.danger).frame(width: 7, height: 7).padding(.top, 5)
                VStack(alignment: .leading, spacing: 4) {
                    Text("操作失败")
                        .font(AppFont.ui(size: 12.5, weight: .semibold))
                        .foregroundColor(palette.danger)
                    Text(message)
                        .font(AppFont.mono(size: 11.5))
                        .foregroundColor(palette.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("清除") { lastError = nil }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Toggle handlers

    /// 主开关变化：
    ///   OFF→ON 且未弹过许可：弹 NSAlert
    ///     - 允许：调 installM1M3() + 置 didShowHookInstallAlert = true
    ///     - 暂不：回滚 toggle 到 OFF + 置 didShowHookInstallAlert = true
    ///   OFF→ON 且已弹过：直接 install
    ///   ON→OFF：弹简单确认 → 确认后 uninstall + 自动把 M4 也关掉
    private func handleMainToggleChange(newValue: Bool) {
        guard let installer = currentInstaller() else {
            // 未注入 installer（理论上 T11 wiring 后不会发生），回滚并提示
            lastError = "Hook installer 未就绪，请稍后再试或重启 App。"
            rollbackMain(to: !newValue)
            return
        }

        if newValue {
            // OFF → ON
            if hookPrefs.didShowHookInstallAlert {
                performInstall(installer: installer)
            } else {
                presentFirstTimeAlert(installer: installer)
            }
        } else {
            // ON → OFF
            presentDisableConfirm(installer: installer)
        }
    }

    /// M4 开关变化：直接调 enableM4 / disableM4。
    /// 仅当主开关 ON 时可达（toggle disabled 时 UI 不会触发 onChange）。
    private func handleM4ToggleChange(newValue: Bool) {
        guard let installer = currentInstaller() else {
            lastError = "Hook installer 未就绪。"
            rollbackM4(to: !newValue)
            return
        }
        do {
            if newValue {
                try installer.enableM4()
            } else {
                try installer.disableM4()
            }
            lastError = nil
        } catch {
            lastError = "M4 切换失败：\(error)"
            rollbackM4(to: !newValue)
        }
    }

    // MARK: - Alerts

    private func presentFirstTimeAlert(installer: HookInstaller) {
        let alert = NSAlert()
        alert.messageText = "cc-anywhere 需要修改 Claude 配置"
        alert.informativeText = """
        为了让 Claude 的提问能实时推到您的手机，cc-anywhere 需要在 ~/.claude/settings.json 中注册一组 PreToolUse / PostToolUse / Notification hook。这些 hook 不会修改您已有的其他 hook 配置。您可以随时在偏好里关闭此功能。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "允许并启用")
        alert.addButton(withTitle: "暂不启用")

        let response = alert.runModal()
        // 无论选哪个都标记"已弹过"
        hookPrefs.didShowHookInstallAlert = true

        if response == .alertFirstButtonReturn {
            performInstall(installer: installer)
        } else {
            // "暂不启用" → 回滚主开关到 OFF
            rollbackMain(to: false)
        }
    }

    private func presentDisableConfirm(installer: HookInstaller) {
        let alert = NSAlert()
        alert.messageText = "将禁用远程 hook"
        alert.informativeText = "禁用后 Claude TUI 恢复内置弹窗，手机端将不再接收提问推送。是否确认？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确认禁用")
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            performUninstall(installer: installer)
        } else {
            // 取消 → 把主开关回滚到 ON
            rollbackMain(to: true)
        }
    }

    // MARK: - Install / Uninstall execution

    private func performInstall(installer: HookInstaller) {
        do {
            try installer.installM1M3()
            lastError = nil
        } catch {
            lastError = "安装 hook 失败：\(error)"
            rollbackMain(to: false)
        }
    }

    private func performUninstall(installer: HookInstaller) {
        do {
            try installer.uninstall()
            // R-F6-002：主开关关闭即 M4 也跟着关闭
            if hookPrefs.enableToolApprovalRemote {
                suppressM4OnChange = true
                hookPrefs.enableToolApprovalRemote = false
                suppressM4OnChange = false
            }
            lastError = nil
        } catch {
            lastError = "卸载 hook 失败：\(error)"
            // 卸载失败 → 主开关回滚到 ON（实际状态未变）
            rollbackMain(to: true)
        }
    }

    // MARK: - Rollback helpers

    private func rollbackMain(to value: Bool) {
        suppressMainOnChange = true
        hookPrefs.enableRemoteHook = value
        suppressMainOnChange = false
    }

    private func rollbackM4(to value: Bool) {
        suppressM4OnChange = true
        hookPrefs.enableToolApprovalRemote = value
        suppressM4OnChange = false
    }

    // MARK: - Installer lookup

    /// 通过 DependencyContainer 获取 SettingsJsonInstaller 实例。
    /// 容器尚未注入时返回 nil（T11 wiring 完成前的过渡态）。
    private func currentInstaller() -> HookInstaller? {
        return container.settingsJsonInstaller
    }
}
