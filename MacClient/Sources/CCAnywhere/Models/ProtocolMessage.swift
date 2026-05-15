// ProtocolMessage.swift
// WebSocket protocol message envelopes (see 需求规格说明书 §3.4).
// We model the minimum set the MacClient needs to consume/emit.

import Foundation

/// All messages share this envelope.
public struct ProtocolMessage: Codable, Sendable {
    public let type: String
    public let id: String
    public let data: AnyJSON?

    public init(type: String, id: String = UUID().uuidString, data: AnyJSON? = nil) {
        self.type = type
        self.id = id
        self.data = data
    }
}

// MARK: - Outbound payloads

public struct BindMacRequest: Codable, Sendable {
    public let type: String     // "mac"
    public let token: String

    public init(token: String) {
        self.type = "mac"
        self.token = token
    }
}

public struct TabListPayload: Codable, Sendable {
    public let tabs: [TabSummary]
    public init(tabs: [TabSummary]) { self.tabs = tabs }
}

public struct MsgHistoryRequestPayload: Codable, Sendable {
    public let tabId: String
    public let limit: Int?
    public let before: String?

    private enum CodingKeys: String, CodingKey {
        case tabId = "tab_id"
        case limit
        case before
    }
}

public struct MsgHistoryResponsePayload: Codable, Sendable {
    public let tabId: String
    public let messages: [AnyJSON]
    public let hasMore: Bool

    public init(tabId: String, messages: [AnyJSON], hasMore: Bool) {
        self.tabId = tabId
        self.messages = messages
        self.hasMore = hasMore
    }

    private enum CodingKeys: String, CodingKey {
        case tabId = "tab_id"
        case messages
        case hasMore = "has_more"
    }
}

public struct TabSummary: Codable, Sendable {
    public let id: String
    public let name: String
    public let folder: String
    public let claudeStatus: String
    public let lastActivityAt: String?

    public init(id: String,
                name: String,
                folder: String,
                claudeStatus: String,
                lastActivityAt: String?) {
        self.id = id
        self.name = name
        self.folder = folder
        self.claudeStatus = claudeStatus
        self.lastActivityAt = lastActivityAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, folder
        case claudeStatus = "claude_status"
        case lastActivityAt = "last_activity_at"
    }
}

public struct TabChangedPayload: Codable, Sendable {
    public let tab: TabSummary
    public let action: String   // "added" | "removed" | "renamed"

    public init(tab: TabSummary, action: String) {
        self.tab = tab
        self.action = action
    }
}

public struct MsgStreamPayload: Codable, Sendable {
    public let tabId: String
    public let messages: [AnyJSON]

    private enum CodingKeys: String, CodingKey {
        case tabId = "tab_id"
        case messages
    }
}

public struct DeviceRevokeRequest: Codable, Sendable {
    public let subTokenId: String
    private enum CodingKeys: String, CodingKey {
        case subTokenId = "sub_token_id"
    }
}

// MARK: - Inbound payloads (subset)

public struct InputTextPayload: Codable, Sendable {
    public let tabId: String
    public let text: String
    private enum CodingKeys: String, CodingKey {
        case tabId = "tab_id"
        case text
    }
}

public struct InputImagePayload: Codable, Sendable {
    public let tabId: String
    public let imageUrl: String
    public let filename: String
    public let sha256: String?
    public let uploadId: String
    private enum CodingKeys: String, CodingKey {
        case tabId = "tab_id"
        case imageUrl = "image_url"
        case filename
        case sha256
        case uploadId = "upload_id"
    }
}

public struct ToolUseApprovePayload: Codable, Sendable {
    public let tabId: String
    public let action: String   // "approve" | "reject" | "always_approve"
    private enum CodingKeys: String, CodingKey {
        case tabId = "tab_id"
        case action
    }
}

public struct BindAckPayload: Codable, Sendable {
    public let agentId: String?
    public let sessionToken: String?
    private enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case sessionToken = "session_token"
    }
}

public struct PhoneCountPayload: Codable, Sendable {
    public let count: Int
    public let names: [String]?
}

public struct DeviceBoundPayload: Codable, Sendable {
    public let subTokenId: String
    public let deviceName: String
    public let deviceModel: String?
    public let osVersion: String?
    public let boundAt: String?
    private enum CodingKeys: String, CodingKey {
        case subTokenId = "sub_token_id"
        case deviceName = "device_name"
        case deviceModel = "device_model"
        case osVersion = "os_version"
        case boundAt = "bound_at"
    }
}

public struct ErrorPayload: Codable, Sendable {
    public let code: String
    public let message: String
}

// MARK: - AskUserQuestion 远程交互 payloads

public struct AskQuestionOption: Codable, Sendable {
    public let label: String
    public let description: String?

    public init(label: String, description: String? = nil) {
        self.label = label
        self.description = description
    }
}

public struct AskQuestionItem: Codable, Sendable {
    public let question: String
    public let header: String
    public let multiSelect: Bool
    public let options: [AskQuestionOption]

    public init(question: String,
                header: String,
                multiSelect: Bool,
                options: [AskQuestionOption]) {
        self.question = question
        self.header = header
        self.multiSelect = multiSelect
        self.options = options
    }

    private enum CodingKeys: String, CodingKey {
        // multiSelect 用 camelCase（保持与 AskUserQuestion 工具原生 schema 一致，
        // 也与三端协议（需求规格说明书 §3.2.1）一致；该字段是 questions 数组元素
        // 内部字段，由 Claude SDK 写入 tool_input，必须保留 camelCase。
        case question
        case header
        case multiSelect
        case options
    }
}

public struct AskQuestionPendingPayload: Codable, Sendable {
    public let requestId: String
    public let tabId: String
    public let toolUseId: String
    public let askKind: String      // "user_question" | "tool_approval"
    public let allowOther: Bool
    public let questions: [AskQuestionItem]?
    public let toolName: String?
    public let toolInput: AnyJSON?

    public init(requestId: String,
                tabId: String,
                toolUseId: String,
                askKind: String,
                allowOther: Bool,
                questions: [AskQuestionItem]? = nil,
                toolName: String? = nil,
                toolInput: AnyJSON? = nil) {
        self.requestId = requestId
        self.tabId = tabId
        self.toolUseId = toolUseId
        self.askKind = askKind
        self.allowOther = allowOther
        self.questions = questions
        self.toolName = toolName
        self.toolInput = toolInput
    }

    private enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case tabId = "tab_id"
        case toolUseId = "tool_use_id"
        case askKind = "ask_kind"
        case allowOther = "allow_other"
        case questions
        case toolName = "tool_name"
        case toolInput = "tool_input"
    }
}

public struct AskQuestionAnswerPayload: Codable, Sendable {
    public let requestId: String
    public let answers: [String: String]

    public init(requestId: String, answers: [String: String]) {
        self.requestId = requestId
        self.answers = answers
    }

    private enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case answers
    }
}

/// Phone → Mac，tool_approval 决策回执（F4 危险工具远程批准）。
///
/// envelope.type = "ask.tool_approval.answer"。Mac 端
/// `DependencyContainer.handleAskToolApprovalInbound` 解析后投递给
/// `HookIpcServer.receiveApprovalFromWs`，进入 winner 锁仲裁。
/// 字段命名与 Server `protocol.AskToolApprovalAnswer` 严格对齐（snake_case）。
public struct AskToolApprovalAnswerPayload: Codable, Sendable {
    public let requestId: String
    /// "allow" | "deny"
    public let decision: String
    /// 用户附加的拒绝原因，可选（R-F4-005）。
    public let reason: String?

    public init(requestId: String, decision: String, reason: String?) {
        self.requestId = requestId
        self.decision = decision
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case decision
        case reason
    }
}

public struct AskQuestionAnsweredPayload: Codable, Sendable {
    public let requestId: String
    public let answeredBy: String
    public let answers: [String: String]

    public init(requestId: String, answeredBy: String, answers: [String: String]) {
        self.requestId = requestId
        self.answeredBy = answeredBy
        self.answers = answers
    }

    private enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case answeredBy = "answered_by"
        case answers
    }
}

public struct AskQuestionTimeoutPayload: Codable, Sendable {
    public let requestId: String
    public let reason: String

    public init(requestId: String, reason: String) {
        self.requestId = requestId
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case reason
    }
}

public struct ToolProgressPrePayload: Codable, Sendable {
    public let tabId: String
    public let toolUseId: String
    public let toolName: String
    public let toolInput: AnyJSON

    public init(tabId: String,
                toolUseId: String,
                toolName: String,
                toolInput: AnyJSON) {
        self.tabId = tabId
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.toolInput = toolInput
    }

    private enum CodingKeys: String, CodingKey {
        case tabId = "tab_id"
        case toolUseId = "tool_use_id"
        case toolName = "tool_name"
        case toolInput = "tool_input"
    }
}

public struct ToolProgressPostPayload: Codable, Sendable {
    public let tabId: String
    public let toolUseId: String
    public let toolName: String
    public let success: Bool
    public let error: String?

    public init(tabId: String,
                toolUseId: String,
                toolName: String,
                success: Bool,
                error: String? = nil) {
        self.tabId = tabId
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.success = success
        self.error = error
    }

    private enum CodingKeys: String, CodingKey {
        case tabId = "tab_id"
        case toolUseId = "tool_use_id"
        case toolName = "tool_name"
        case success
        case error
    }
}

public struct NotificationPayload: Codable, Sendable {
    public let tabId: String
    public let notificationType: String
    public let title: String
    public let message: String

    public init(tabId: String,
                notificationType: String,
                title: String,
                message: String) {
        self.tabId = tabId
        self.notificationType = notificationType
        self.title = title
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case tabId = "tab_id"
        case notificationType = "notification_type"
        case title
        case message
    }
}
