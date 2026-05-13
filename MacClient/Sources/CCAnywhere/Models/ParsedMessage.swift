// ParsedMessage.swift
// One parsed line from Claude Code's JSONL session file.
// We keep the raw JSON around so the server can forward verbatim if needed.

import Foundation

public struct ParsedMessage: Sendable {
    public let type: String
    public let uuid: String?
    public let sessionId: String?
    public let timestamp: Date?
    public let raw: String              // original JSONL line
    public let parsed: [String: AnyJSON]?

    public init(type: String,
                uuid: String?,
                sessionId: String?,
                timestamp: Date?,
                raw: String,
                parsed: [String: AnyJSON]?) {
        self.type = type
        self.uuid = uuid
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.raw = raw
        self.parsed = parsed
    }
}

/// A type-erased JSON value that supports Codable. Useful because Claude Code
/// session lines can carry arbitrary nested payloads we don't want to model
/// fully.
public indirect enum AnyJSON: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: AnyJSON])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null; return
        }
        if let b = try? c.decode(Bool.self) {
            self = .bool(b); return
        }
        if let n = try? c.decode(Double.self) {
            self = .number(n); return
        }
        if let s = try? c.decode(String.self) {
            self = .string(s); return
        }
        if let a = try? c.decode([AnyJSON].self) {
            self = .array(a); return
        }
        if let o = try? c.decode([String: AnyJSON].self) {
            self = .object(o); return
        }
        throw DecodingError.dataCorruptedError(
            in: c,
            debugDescription: "Unsupported JSON value"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    public var asString: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// Accepts either a JSON string or a JSON number and returns the decimal
    /// string form. Used for id fields that may be serialized either way by
    /// older Server builds.
    public var asIdString: String? {
        switch self {
        case .string(let s):
            return s
        case .number(let n):
            return String(Int64(n))
        default:
            return nil
        }
    }
}
