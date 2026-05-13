// HistoryBridge.swift
// Replies to phone-originated `msg.history.request` envelopes by reading the
// active JSONL file for that Tab and returning the last N messages (optionally
// filtered to lines before a given timestamp).
//
// See 需求规格说明书 §3.4 4.4 / R-A3-* (loadHistory).

import Foundation
import Combine

@MainActor
public final class HistoryBridge {
    private let log = AppLogger.shared.tagged("HistoryBridge")
    private weak var ws: WSClient?
    private weak var tabManager: TabManager?
    private var cancellables = Set<AnyCancellable>()

    /// Hard cap so a misbehaving phone cannot force us to read the entire file.
    private let maxLimit = 200
    private let defaultLimit = 50

    public init(ws: WSClient, tabManager: TabManager) {
        self.ws = ws
        self.tabManager = tabManager
        ws.inbound
            .filter { $0.type == "msg.history.request" }
            .sink { [weak self] msg in
                guard let self = self else { return }
                Task { await self.handle(msg) }
            }
            .store(in: &cancellables)
    }

    private func handle(_ msg: ProtocolMessage) async {
        guard let data = msg.data,
              let req = decode(data, MsgHistoryRequestPayload.self) else {
            log.warn("malformed msg.history.request")
            return
        }
        guard let tabUUID = UUID(uuidString: req.tabId),
              let tab = tabManager?.tab(by: tabUUID) else {
            await sendResponse(tabId: req.tabId, messages: [], hasMore: false)
            return
        }
        let limit = min(max(1, req.limit ?? defaultLimit), maxLimit)
        let beforeDate: Date? = req.before.flatMap {
            ISO8601DateFormatter().date(from: $0)
        }
        let (messages, hasMore) = await Self.readHistory(
            folder: tab.folder, limit: limit, before: beforeDate
        )
        await sendResponse(tabId: req.tabId, messages: messages, hasMore: hasMore)
    }

    private func sendResponse(tabId: String, messages: [AnyJSON], hasMore: Bool) async {
        let payload = MsgHistoryResponsePayload(tabId: tabId, messages: messages, hasMore: hasMore)
        let any: AnyJSON? = {
            guard let data = try? JSONEncoder().encode(payload) else { return nil }
            return try? JSONDecoder().decode(AnyJSON.self, from: data)
        }()
        await ws?.send(ProtocolMessage(type: "msg.history.response", data: any))
        log.info("sent msg.history.response tab=\(tabId) count=\(messages.count) hasMore=\(hasMore)")
    }

    // MARK: - File IO (off main actor would be nicer, but JSONL files are
    // tiny and we already pay for I/O in the watcher loop; keep this simple).

    /// Reads the latest non-agent JSONL file for the given Tab folder and
    /// returns at most `limit` parsed lines whose `timestamp` is < `before`
    /// (if provided). Lines are returned in chronological order (oldest first)
    /// so the phone can prepend them.
    nonisolated public static func readHistory(
        folder: URL,
        limit: Int,
        before: Date?
    ) async -> (messages: [AnyJSON], hasMore: Bool) {
        let dir = JSONLWatcher.claudeProjectsDir(for: folder)
        guard let activeFile = latestSessionFile(in: dir) else {
            return ([], false)
        }
        guard let data = try? Data(contentsOf: activeFile),
              let text = String(data: data, encoding: .utf8) else {
            return ([], false)
        }
        // Split into trimmed non-empty lines.
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        // Parse each line; keep (timestamp, AnyJSON) pairs.
        var parsed: [(Date?, AnyJSON)] = []
        parsed.reserveCapacity(lines.count)
        let iso = ISO8601DateFormatter()
        for line in lines {
            guard let lineData = line.data(using: .utf8) else { continue }
            // Try to decode to AnyJSON; if it fails skip.
            guard let any = try? JSONDecoder().decode(AnyJSON.self, from: lineData) else {
                continue
            }
            // Extract timestamp if available.
            var ts: Date? = nil
            if case .object(let dict) = any,
               case .string(let tsStr) = dict["timestamp"] ?? .null {
                ts = iso.date(from: tsStr)
            }
            parsed.append((ts, any))
        }
        // Filter by `before` if provided. A row without a timestamp is kept
        // (we can't prove it's after `before`).
        let filtered: [(Date?, AnyJSON)] = {
            guard let before = before else { return parsed }
            return parsed.filter { ($0.0 ?? .distantPast) < before }
        }()
        // Take last `limit` (most recent before).
        let tailStart = max(0, filtered.count - limit)
        let tail = filtered[tailStart...]
        let hasMore = tailStart > 0
        return (tail.map { $0.1 }, hasMore)
    }

    nonisolated private static func latestSessionFile(in dir: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: dir.path) else { return nil }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let jsonls = urls.filter { url in
            let name = url.lastPathComponent
            return name.hasSuffix(".jsonl") && !name.hasPrefix("agent-")
        }
        return jsonls.max { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return l < r
        }
    }
}
