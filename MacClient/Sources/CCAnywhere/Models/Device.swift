// Device.swift
// Mobile device record displayed in PreferencesPane -> Devices.

import Foundation

public struct Device: Identifiable, Codable, Hashable, Sendable {
    public var id: String           // sub_token id
    public var deviceName: String
    public var deviceModel: String?
    public var osVersion: String?
    public var boundAt: Date
    public var lastSeenAt: Date?
    public var online: Bool
    public var latencyMs: Int?

    public init(id: String,
                deviceName: String,
                deviceModel: String? = nil,
                osVersion: String? = nil,
                boundAt: Date,
                lastSeenAt: Date? = nil,
                online: Bool = false,
                latencyMs: Int? = nil) {
        self.id = id
        self.deviceName = deviceName
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.boundAt = boundAt
        self.lastSeenAt = lastSeenAt
        self.online = online
        self.latencyMs = latencyMs
    }

    /// Format the "last seen" label per R-M6-05.
    public var lastSeenLabel: String {
        guard let t = lastSeenAt else { return "未知" }
        let interval = Date().timeIntervalSince(t)
        if interval < 60 {
            return "刚刚在线"
        } else if interval < 3600 {
            return "\(Int(interval / 60)) 分钟前"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.string(from: t)
        }
    }
}
