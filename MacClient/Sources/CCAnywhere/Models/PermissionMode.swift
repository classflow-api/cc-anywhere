// Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.
//
// PermissionMode.swift
// Claude Code 的 6 个 permission mode（与 `claude --permission-mode <mode>` 对齐）。
// 创建工作区时由用户选择，传给 claude 子进程；后续可通过右键菜单修改。
// 详见 docs/工作区权限模式/变更说明.md。

import Foundation

public enum PermissionMode: String, CaseIterable, Codable, Sendable {
    case `default`
    case acceptEdits
    case plan
    case auto
    case dontAsk
    case bypassPermissions

    /// UI 显示用的简短标题（中文），下拉框选项主标签
    public var displayName: String {
        switch self {
        case .default:           return "default · 只读"
        case .acceptEdits:       return "acceptEdits · 读 + 编辑文件"
        case .plan:              return "plan · 探索（只读）"
        case .auto:              return "auto · 所有操作 + 后台检查"
        case .dontAsk:           return "dontAsk · 仅预批准的工具"
        case .bypassPermissions: return "bypassPermissions · 所有操作（隔离容器）"
        }
    }

    /// 长说明，对话框副标题用
    public var summary: String {
        switch self {
        case .default:           return "入门、敏感工作。每个工具调用都需要你逐项确认。"
        case .acceptEdits:       return "迭代审查中的代码。允许读、编辑、mkdir/touch/mv/cp 等。"
        case .plan:              return "改代码前先探索。只允许读取，不能写文件。"
        case .auto:              return "长时间任务。所有操作放行，Claude 自带后台安全检查。"
        case .dontAsk:           return "锁定 CI / 脚本场景。仅放行预先批准的工具。"
        case .bypassPermissions: return "仅适合隔离容器 / VM。绕过所有权限检查，慎用。"
        }
    }

    /// 持久化反序列化失败时的安全回退（也是默认 mode）
    public static let fallback: PermissionMode = .default
}
