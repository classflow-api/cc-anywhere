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
