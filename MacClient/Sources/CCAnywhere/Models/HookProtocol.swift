// Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.
//
// HookProtocol.swift
// hook bridge ↔ Mac App 的 Unix socket 协议数据模型。
//
// 详见 技术实施文档.md §6.2.1（请求 schema）与 §6.2.2（响应 schema）。
//
// 协议 framing：一行 JSON + `\n`，UTF-8 编码；socket 双向均按行分帧。

import Foundation

// MARK: - 进入方向：hook bridge → Mac App

/// hook bridge 通过 Unix socket 发给 Mac App 的请求。
///
/// `kind` 字段决定语义：
/// - `"ask"`：阻塞型，等待 Mac App 回写 answers / approval / error
/// - `"progress_pre"`：fire-and-forget，PreToolUse Bash/Write/Edit progress
/// - `"progress_post"`：fire-and-forget，PostToolUse 任意工具 progress
/// - `"notification"`：fire-and-forget，Claude Notification 事件
public struct HookIpcRequest: Codable, Sendable {
    public let kind: String
    public let tabId: String
    public let sessionId: String?
    public let toolUseId: String?
    public let toolName: String?
    public let toolInput: AnyJSON?
    /// 仅 `progress_post` 有值。
    public let toolResponse: AnyJSON?
    /// 仅 `notification` 有值。
    public let notification: String?
    public let title: String?
    public let notificationType: String?

    public init(kind: String,
                tabId: String,
                sessionId: String? = nil,
                toolUseId: String? = nil,
                toolName: String? = nil,
                toolInput: AnyJSON? = nil,
                toolResponse: AnyJSON? = nil,
                notification: String? = nil,
                title: String? = nil,
                notificationType: String? = nil) {
        self.kind = kind
        self.tabId = tabId
        self.sessionId = sessionId
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolResponse = toolResponse
        self.notification = notification
        self.title = title
        self.notificationType = notificationType
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case tabId = "tab_id"
        case sessionId = "session_id"
        case toolUseId = "tool_use_id"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolResponse = "tool_response"
        case notification, title
        case notificationType = "notification_type"
    }
}

// MARK: - 出方向：Mac App → hook bridge

/// 对 `kind == "ask"` 的响应。
///
/// 互斥三种 case（由字段存在性区分）：
/// - **user_question 成功**：仅 `answers` 有值
/// - **tool_approval 成功**：`askKind == "tool_approval"` + `decision` + 可选 `reason`
/// - **失败**：仅 `error` 有值（如 `"timeout"` / `"unknown tab_id"`）
public struct HookIpcResponseAsk: Codable, Sendable {
    public let answers: [String: String]?
    public let askKind: String?
    public let decision: String?
    public let reason: String?
    public let error: String?

    public init(answers: [String: String]? = nil,
                askKind: String? = nil,
                decision: String? = nil,
                reason: String? = nil,
                error: String? = nil) {
        self.answers = answers
        self.askKind = askKind
        self.decision = decision
        self.reason = reason
        self.error = error
    }

    /// 构造 user_question 成功响应。
    public static func userQuestion(answers: [String: String]) -> HookIpcResponseAsk {
        HookIpcResponseAsk(answers: answers)
    }

    /// 构造 tool_approval 成功响应。
    public static func toolApproval(decision: String, reason: String?) -> HookIpcResponseAsk {
        HookIpcResponseAsk(askKind: "tool_approval", decision: decision, reason: reason)
    }

    /// 构造失败响应。
    public static func failure(error: String) -> HookIpcResponseAsk {
        HookIpcResponseAsk(error: error)
    }

    private enum CodingKeys: String, CodingKey {
        case answers, decision, reason, error
        case askKind = "ask_kind"
    }
}

/// 对 `progress_pre` / `progress_post` / `notification` 的响应（恒为 `{}`）。
public struct HookIpcResponseEmpty: Codable, Sendable {
    public init() {}
}

// MARK: - HookIpcServer 对外协作的抽象接口

/// HookIpcServer 用来向 WSClient 推协议消息的窄接口。
/// 抽象的目的：单测可注入 mock；wiring 时由真实 WSClient 适配。
@MainActor
public protocol HookIpcWsSink: AnyObject {
    func sendAskQuestionPending(_ payload: AskQuestionPendingPayload)
    func sendAskQuestionAnswered(_ payload: AskQuestionAnsweredPayload)
    func sendAskQuestionTimeout(_ payload: AskQuestionTimeoutPayload)
    func sendToolProgressPre(_ payload: ToolProgressPrePayload)
    func sendToolProgressPost(_ payload: ToolProgressPostPayload)
    func sendNotification(_ payload: NotificationPayload)
    func sendTabActivity(_ payload: TabActivityPayload)
}

/// HookIpcServer 用来上报 Tab 活动状态变化（working / waiting）的窄接口。
/// 由 DependencyContainer 实现，把变化路由到 TabManager + ws 推送。
@MainActor
public protocol HookIpcActivitySink: AnyObject {
    /// 报告某 tab 的 Claude 活动状态。如果状态变化了 → 推 phone；不变则无操作。
    func setActivity(tabId: UUID, activity: String)
}

/// HookIpcServer 用来校验 / 解析 tab_id 的窄接口。R-F1-006。
public protocol HookIpcTabRouter: AnyObject, Sendable {
    /// 该 tab id 字符串是否对应当前活跃 tab。
    func isActive(tabIdString: String) -> Bool
    /// 把 hook bridge 传来的 string 转回 UUID（无效返回 nil）。
    func uuid(forTabIdString: String) -> UUID?
    /// 返回该 tab 当前的 Claude permission mode rawValue（"default" / "bypassPermissions" 等）。
    /// 未知 tab 返回 nil。HookIpcServer 在 actor 内部同步调用，所以必须线程安全且非 isolated。
    func permissionMode(forTabIdString: String) -> String?
}

/// HookIpcServer 用来通知 Mac 端 AskQuestionCard UI 的窄接口。
@MainActor
public protocol HookIpcCardSink: AnyObject {
    func show(request: AskCardRequestData) async
    func dismiss(requestId: String, reason: AskDismissReason, by: String?) async
}

/// HookIpcServer 用来通知 JSONLWatcher 去重的窄接口。
public protocol HookIpcJsonlSink: AnyObject, Sendable {
    func markHookPushed(toolUseId: String)
    /// R-F5-001 / R-F5-004：按 hook stdin 的 sessionId 反查子 agent meta，
    /// HookIpcServer 在 actor 内同步调用（必须线程安全且非 isolated）。
    /// 返回 nil 表示该 sessionId 不属于任何已索引的子 agent（= 主 session
    /// 直调工具的常规情况）。
    func findSubAgent(tabId: UUID, sessionId: String) -> SubAgentMetaProtocol?
}

/// 协议层透出的子 agent meta 投影（避免 HookProtocol 模块直接依赖
/// JSONLWatcher 中的具体类型；与具体实现的 SubAgentMeta 字段对齐）。
public protocol SubAgentMetaProtocol: Sendable {
    var parentToolUseId: String? { get }
    var agentId: String { get }
    var agentSessionId: String { get }
    var promptSummary: String { get }
}

/// 传给 Mac AskQuestionCardController 的请求数据载体。
public struct AskCardRequestData: Sendable {
    public let requestId: String
    public let tabId: UUID
    public let toolUseId: String
    /// `"user_question"` | `"tool_approval"`
    public let askKind: String
    public let questions: [AskQuestionItem]?
    public let toolName: String?
    public let toolInput: AnyJSON?

    public init(requestId: String,
                tabId: UUID,
                toolUseId: String,
                askKind: String,
                questions: [AskQuestionItem]? = nil,
                toolName: String? = nil,
                toolInput: AnyJSON? = nil) {
        self.requestId = requestId
        self.tabId = tabId
        self.toolUseId = toolUseId
        self.askKind = askKind
        self.questions = questions
        self.toolName = toolName
        self.toolInput = toolInput
    }
}

/// 卡片被关闭的原因。
public enum AskDismissReason: Sendable {
    case answered
    case timeout
    case cancelled
}
