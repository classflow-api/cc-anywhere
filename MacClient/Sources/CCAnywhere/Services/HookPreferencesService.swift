// Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.
//
// HookPreferencesService.swift
// 持久化"远程 Hook"两个偏好开关的状态及首次许可弹窗标志。
//
// 关键设计（详见 需求规格说明书 §3.1 F6 / 业务规则 R-F6-001..004）：
//   - enableRemoteHook 默认 false：避免 Mac App 首次启动就强行写 ~/.claude/settings.json
//     （R-F6-001 友好性）。首次启动时由 UI 主动引导用户开启，弹许可弹窗后才真正
//     调 SettingsJsonInstaller.installM1M3() 写入 settings.json。
//   - enableToolApprovalRemote 默认 false：M4 默认关闭，依赖主开关（R-F6-003）。
//   - didShowHookInstallAlert 标志：用户对许可弹窗"暂不启用"后置 true，下次启动
//     不再弹窗（R-F6-001）。
//   - 持久化通道：UserDefaults.standard（macOS 自动落地到
//     `~/Library/Preferences/<bundle id>.plist`，满足 R-F6-004）。
//
// 偏好面板 (HookPane) 绑定本服务的 @Published 字段，并在 toggle onChange 中通过
// `HookInstaller` protocol 调用 SettingsJsonInstaller 的写盘操作。

import Foundation
import SwiftUI

/// 抽象 settings.json 安装/卸载入口，便于偏好面板单测时注入 stub。
/// `SettingsJsonInstaller` 通过扩展自动 conform。
public protocol HookInstaller: AnyObject {
    func installM1M3() throws
    func enableM4() throws
    func disableM4() throws
    func uninstall() throws
}

extension SettingsJsonInstaller: HookInstaller {}

@MainActor
public final class HookPreferencesService: ObservableObject {

    // MARK: - UserDefaults keys

    private static let keyEnableRemoteHook       = "ccanywhere.hook.enableRemoteHook"
    private static let keyEnableToolApproval     = "ccanywhere.hook.enableToolApprovalRemote"
    private static let keyDidShowInstallAlert    = "ccanywhere.hook.didShowHookInstallAlert"

    private let defaults: UserDefaults

    // MARK: - Published state

    /// 主开关：启用远程 hook（M1-M3）。默认 false（首次启动由 UI 引导用户开启）。
    /// onChange 由 HookPane 监听 → 弹许可弹窗 / 调 install / 调 uninstall。
    @Published public var enableRemoteHook: Bool {
        didSet {
            guard oldValue != enableRemoteHook else { return }
            defaults.set(enableRemoteHook, forKey: Self.keyEnableRemoteHook)
        }
    }

    /// 子开关：启用工具批准远程化（M4）。默认 false，依赖主开关（R-F6-003）。
    /// onChange 由 HookPane 监听 → 调 enableM4 / disableM4。
    @Published public var enableToolApprovalRemote: Bool {
        didSet {
            guard oldValue != enableToolApprovalRemote else { return }
            defaults.set(enableToolApprovalRemote, forKey: Self.keyEnableToolApproval)
        }
    }

    /// 是否已展示过首次许可弹窗。一旦弹过（无论"允许"还是"暂不"），下次启动不再弹（R-F6-001）。
    @Published public var didShowHookInstallAlert: Bool {
        didSet {
            guard oldValue != didShowHookInstallAlert else { return }
            defaults.set(didShowHookInstallAlert, forKey: Self.keyDidShowInstallAlert)
        }
    }

    // MARK: - Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 首次启动 enableRemoteHook 默认 false（友好），避免强写 settings.json。
        self.enableRemoteHook = defaults.object(forKey: Self.keyEnableRemoteHook) as? Bool ?? false
        self.enableToolApprovalRemote = defaults.object(forKey: Self.keyEnableToolApproval) as? Bool ?? false
        self.didShowHookInstallAlert = defaults.object(forKey: Self.keyDidShowInstallAlert) as? Bool ?? false
    }
}
