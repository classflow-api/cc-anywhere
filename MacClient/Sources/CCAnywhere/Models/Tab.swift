// Tab.swift
// Tab data model + persistence shape (tabs.json).
// See 需求规格说明书 §3.5.1 / R-M1-02.

import Foundation

public enum TabStatus: String, Codable, Sendable {
    case idle      // not yet started / starting
    case running
    case error
}

public struct Tab: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var folder: URL
    public var name: String
    public var createdAt: Date

    /// Runtime-only fields (not persisted).
    /// We keep them on the same struct to make SwiftUI binding simpler,
    /// but exclude from Codable.
    public var status: TabStatus = .idle
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
                status: TabStatus = .idle) {
        self.id = id
        self.folder = folder
        self.name = name
        self.createdAt = createdAt
        self.status = status
    }

    // MARK: - Codable (persist only id/folder/name/createdAt)
    private enum CodingKeys: String, CodingKey {
        case id
        case folder
        case name
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        let folderStr = try c.decode(String.self, forKey: .folder)
        self.folder = URL(fileURLWithPath: folderStr)
        self.name = try c.decode(String.self, forKey: .name)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.status = .idle
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(folder.path, forKey: .folder)
        try c.encode(name, forKey: .name)
        try c.encode(createdAt, forKey: .createdAt)
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
