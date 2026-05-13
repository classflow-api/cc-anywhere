// ServerConfig.swift
// See 需求规格说明书 §3.5.1.

import Foundation

public struct ServerConfig: Codable, Equatable, Sendable {
    public var server: String
    public var port: Int
    public var masterToken: String
    public var trustSelfSigned: Bool

    public init(server: String = "",
                port: Int = 8443,
                masterToken: String = "",
                trustSelfSigned: Bool = false) {
        self.server = server
        self.port = port
        self.masterToken = masterToken
        self.trustSelfSigned = trustSelfSigned
    }

    private enum CodingKeys: String, CodingKey {
        case server
        case port
        case masterToken = "master_token"
        case trustSelfSigned = "trust_self_signed"
    }

    public var isUsable: Bool {
        !server.isEmpty
            && port >= 1 && port <= 65535
            && !masterToken.isEmpty
    }

    public var wsURL: URL? {
        URL(string: "wss://\(server):\(port)/")
    }
}
