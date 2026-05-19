// Tab.swift
// Tab data model + persistence shape (tabs.json).
// See 需求规格说明书 §3.5.1 / R-M1-02.

import Foundation

public enum TabStatus: String, Codable, Sendable {
    case idle      // not yet started / starting
    case running
    case error
}

/// Claude 在该 Tab 内的活动状态（独立于 PTY 进程状态）。
/// 由 hook 桥接驱动：PreToolUse / 新 user message → working；
/// Notification {type:"idle"} → waiting。
public enum ClaudeActivity: String, Codable, Sendable {
    case waiting    // Claude 等待用户输入（idle Notification 已收到）
    case working    // Claude 在思考 / 执行工具
}

public struct Tab: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var folder: URL
    public var name: String
    public var createdAt: Date
    /// Claude Code 的 permission mode（传给 claude 子进程的 `--permission-mode` flag）。
    /// 持久化保存；旧版本数据反序列化时该字段缺失则回退到 .default。
    public var permissionMode: PermissionMode = .default

    /// Runtime-only fields (not persisted).
    /// We keep them on the same struct to make SwiftUI binding simpler,
    /// but exclude from Codable.
    public var status: TabStatus = .idle
    public var activity: ClaudeActivity = .waiting
    public var exitCode: Int32? = nil
    /// Human-readable reason populated when status == .error and the cause is
    /// something more specific than just "process exited" — e.g. the claude
    /// binary couldn't be found. Surfaced in TabContentView's error banner.
    public var errorReason: String? = nil
    public var unread: Int = 0
    public var lastActivityAt: Date? = nil

    public init(id: UUID = UUID(),
                folder: URL,
                name: String,
                createdAt: Date = Date(),
                permissionMode: PermissionMode = .default,
                status: TabStatus = .idle) {
        self.id = id
        self.folder = folder
        self.name = name
        self.createdAt = createdAt
        self.permissionMode = permissionMode
        self.status = status
    }

    // MARK: - Codable (persist id/folder/name/createdAt/permissionMode)
    private enum CodingKeys: String, CodingKey {
        case id
        case folder
        case name
        case createdAt = "created_at"
        case permissionMode = "permission_mode"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        let folderStr = try c.decode(String.self, forKey: .folder)
        self.folder = URL(fileURLWithPath: folderStr)
        self.name = try c.decode(String.self, forKey: .name)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        // 兼容旧持久化（缺该字段或值非法都回退到 default）
        if let raw = try c.decodeIfPresent(String.self, forKey: .permissionMode),
           let m = PermissionMode(rawValue: raw) {
            self.permissionMode = m
        } else {
            self.permissionMode = .default
        }
        self.status = .idle
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(folder.path, forKey: .folder)
        try c.encode(name, forKey: .name)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(permissionMode.rawValue, forKey: .permissionMode)
    }
}

public enum TabError: LocalizedError {
    case folderAlreadyOpen(URL)
    case folderNotExists(URL)
    case fileSystem(Error)
    case nameTooLong

    public var errorDescription: String? {
        switch self {
        case .folderAlreadyOpen(let url):
            return "该文件夹已存在一个活动 Tab：\(url.lastPathComponent)。同一文件夹不允许多个并行 Tab。"
        case .folderNotExists(let url):
            return "文件夹不存在：\(url.path)"
        case .fileSystem(let err):
            return "文件系统错误：\(err.localizedDescription)"
        case .nameTooLong:
            return "Tab 名称最长 50 字符"
        }
    }
}
