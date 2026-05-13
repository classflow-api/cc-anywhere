// JSONLWatcher.swift
// Watches ~/.claude/projects/<encoded>/ for *.jsonl line appends and pushes
// parsed messages out (throttled 100ms, uuid-dedup).
//
// See 需求规格说明书 §3.1 M4 + 技术实施文档 §4.3.
// FSEvents is used because polling is forbidden by R-M4-05.

import Foundation
import CoreServices.FSEvents

/// Public observer interface; we keep this side-effect free for testing.
public protocol JSONLWatcherDelegate: AnyObject {
    func watcher(_ watcher: JSONLWatcher, didReceive batch: [ParsedMessage], for tabId: UUID)
}

public final class JSONLWatcher {
    private let log = AppLogger.shared.tagged("JSONLWatcher")
    public weak var delegate: JSONLWatcherDelegate?

    /// Throttle window per Tab (R-M4-02).
    public var throttleInterval: TimeInterval = 0.1

    private let queue = DispatchQueue(label: "cc-anywhere.jsonl-watcher", qos: .userInitiated)
    private var streams: [UUID: WatchStream] = [:]

    public init() {}

    public func watch(tab: Tab) {
        unwatch(tabId: tab.id)
        let dir = Self.claudeProjectsDir(for: tab.folder)
        let stream = WatchStream(
            tabId: tab.id,
            directory: dir,
            throttleInterval: throttleInterval,
            queue: queue,
            log: log,
            onBatch: { [weak self] (id, batch) in
                guard let self = self else { return }
                self.delegate?.watcher(self, didReceive: batch, for: id)
            }
        )
        stream.start()
        streams[tab.id] = stream
        log.info("watching \(dir.path) for tab=\(tab.id)")
    }

    public func unwatch(tabId: UUID) {
        guard let s = streams.removeValue(forKey: tabId) else { return }
        s.stop()
    }

    public func unwatchAll() {
        for s in streams.values { s.stop() }
        streams.removeAll()
    }

    /// Read-only check used by the container.
    public func isWatching(tabId: UUID) -> Bool {
        streams[tabId] != nil
    }

    /// Stop watchers for tabs that are no longer present.
    public func unwatchAllExcept(ids: Set<UUID>) {
        let stale = streams.keys.filter { !ids.contains($0) }
        for id in stale { unwatch(tabId: id) }
    }

    /// Encoded path used by Claude Code: /Users/foo/bar -> -Users-foo-bar.
    public static func encodeFolderPath(_ url: URL) -> String {
        let standardized = url.standardizedFileURL.path
        return standardized.replacingOccurrences(of: "/", with: "-")
    }

    public static func claudeProjectsDir(for folder: URL) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".claude/projects/\(encodeFolderPath(folder))",
                                    isDirectory: true)
    }
}

// MARK: - WatchStream

/// Per-Tab state. NOT MainActor; runs on watcher.queue.
final class WatchStream {
    let tabId: UUID
    let directory: URL
    let throttleInterval: TimeInterval
    let queue: DispatchQueue
    let log: TaggedLogger
    let onBatch: (UUID, [ParsedMessage]) -> Void

    private var stream: FSEventStreamRef?
    private var activeSessionFile: URL?
    private var lastOffset: UInt64 = 0
    private var pendingMessages: [ParsedMessage] = []
    private var throttleWorkItem: DispatchWorkItem?
    private var seenUuids = Set<String>()
    private var seenFallback = Set<String>()

    init(tabId: UUID,
         directory: URL,
         throttleInterval: TimeInterval,
         queue: DispatchQueue,
         log: TaggedLogger,
         onBatch: @escaping (UUID, [ParsedMessage]) -> Void) {
        self.tabId = tabId
        self.directory = directory
        self.throttleInterval = throttleInterval
        self.queue = queue
        self.log = log
        self.onBatch = onBatch
    }

    func start() {
        // Ensure dir exists; if not, still set up FSEvents on parent so we
        // catch its creation (Claude Code creates it lazily on first message).
        let watchPaths: CFArray
        if FileManager.default.fileExists(atPath: directory.path) {
            watchPaths = [directory.path] as CFArray
        } else {
            let parent = directory.deletingLastPathComponent().path
            watchPaths = [parent] as CFArray
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (_, info, count, eventPaths, _, _) in
                guard let info = info else { return }
                let me = Unmanaged<WatchStream>.fromOpaque(info).takeUnretainedValue()
                let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
                me.handleEvent(paths: paths, count: count)
            },
            &context,
            watchPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05,
            flags
        )
        guard let s = s else {
            log.error("FSEventStreamCreate failed for \(directory.path)")
            return
        }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        self.stream = s

        // Initial scan
        identifyActiveSession()
    }

    func stop() {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
        stream = nil
        throttleWorkItem?.cancel()
        throttleWorkItem = nil
    }

    private func handleEvent(paths: [String], count: Int) {
        // Re-identify session in case of rotation (R-M4-07).
        identifyActiveSession()
        if let file = activeSessionFile {
            readNewLines(from: file)
            scheduleThrottle()
        }
    }

    private func identifyActiveSession() {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let jsonls = urls.filter { url in
            let name = url.lastPathComponent
            return name.hasSuffix(".jsonl") && !name.hasPrefix("agent-")
        }
        let latest = jsonls.max { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return l < r
        }
        if let latest = latest, latest != activeSessionFile {
            activeSessionFile = latest
            lastOffset = 0
            log.info("active session => \(latest.lastPathComponent) (tab=\(tabId))")
        }
    }

    private func readNewLines(from file: URL) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: lastOffset)
        let data: Data
        if #available(macOS 10.15.4, *) {
            data = (try? handle.readToEnd()) ?? Data()
        } else {
            data = handle.readDataToEndOfFile()
        }
        guard !data.isEmpty,
              let chunk = String(data: data, encoding: .utf8) else { return }
        lastOffset += UInt64(data.count)

        // Process complete lines only (last line might be incomplete; we
        // accept that — next FSEvent will reprocess from new offset).
        let lines = chunk.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            let raw = String(line)
            if let msg = parseLine(raw) {
                if shouldEmit(msg) {
                    pendingMessages.append(msg)
                }
            } else {
                let rawMsg = ParsedMessage(
                    type: "raw",
                    uuid: nil,
                    sessionId: nil,
                    timestamp: nil,
                    raw: raw,
                    parsed: nil
                )
                pendingMessages.append(rawMsg)
                log.warn("parse-failed line: \(raw.prefix(120))…")
            }
        }
    }

    private func parseLine(_ line: String) -> ParsedMessage? {
        guard let data = line.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        let type = (obj["type"] as? String) ?? "unknown"
        let uuid = obj["uuid"] as? String
        let session = obj["sessionId"] as? String ?? obj["session_id"] as? String
        var timestamp: Date? = nil
        if let ts = obj["timestamp"] as? String {
            timestamp = ISO8601DateFormatter().date(from: ts)
        }
        // We don't need to fully decode parsed object — the raw line is what
        // we forward to the Server. We pass nil here to keep memory lean.
        return ParsedMessage(
            type: type,
            uuid: uuid,
            sessionId: session,
            timestamp: timestamp,
            raw: line,
            parsed: nil
        )
    }

    private func shouldEmit(_ msg: ParsedMessage) -> Bool {
        if let u = msg.uuid {
            if seenUuids.contains(u) { return false }
            seenUuids.insert(u)
            return true
        }
        // No uuid: use (type, session, timestamp) composite key (R-M4-03).
        let stamp = msg.timestamp.map { "\(Int($0.timeIntervalSince1970 * 1000))" } ?? ""
        let key = "\(msg.type)|\(msg.sessionId ?? "")|\(stamp)"
        if seenFallback.contains(key) { return false }
        seenFallback.insert(key)
        return true
    }

    private func scheduleThrottle() {
        throttleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard !self.pendingMessages.isEmpty else { return }
            let batch = self.pendingMessages
            self.pendingMessages.removeAll()
            self.onBatch(self.tabId, batch)
        }
        throttleWorkItem = work
        queue.asyncAfter(deadline: .now() + throttleInterval, execute: work)
    }
}
