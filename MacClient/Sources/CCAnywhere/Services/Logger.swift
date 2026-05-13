// Logger.swift
// Unified logging interface.
// Writes to both os.Logger (so Console.app picks them up) and a per-day log
// file under ~/Library/Logs/cc-anywhere/.
//
// Rules from R-M9-04 / R-M9-05:
// - format `[time] [level] [module] message`
// - sensitive prefixes are obfuscated as `xxxxxx***xxxx`

import Foundation
import OSLog

public enum LogLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case debug, info, warn, error

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        let order: [LogLevel] = [.debug, .info, .warn, .error]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }

    public var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info:  return "INFO "
        case .warn:  return "WARN "
        case .error: return "ERROR"
        }
    }
}

/// App-level logger with a per-module tag.
public final class AppLogger: @unchecked Sendable {
    public static let shared = AppLogger()
    private let osLogger = OSLog(subsystem: "com.yoolines.cc-anywhere", category: "app")
    private let queue = DispatchQueue(label: "cc-anywhere.logger", qos: .utility)
    private var fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    public var minLevel: LogLevel = .info

    private init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        self.dateFormatter = formatter
        openTodayFile()
        purgeOldLogs()
    }

    public func tagged(_ module: String) -> TaggedLogger {
        TaggedLogger(module: module, root: self)
    }

    func log(level: LogLevel, module: String, message: String) {
        guard level >= minLevel else { return }
        let stamp = dateFormatter.string(from: Date())
        let line = "[\(stamp)] [\(level.label)] [\(module)] \(message)\n"
        os_log("%{public}@", log: osLogger, type: level.osType, line)
        queue.async { [weak self] in
            guard let self = self else { return }
            self.fileHandle?.write(line.data(using: .utf8) ?? Data())
        }
    }

    // MARK: - File rotation

    public var logDirectory: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Logs/cc-anywhere", isDirectory: true)
    }

    public var currentLogFile: URL {
        logDirectory.appendingPathComponent("cc-anywhere.log")
    }

    private func openTodayFile() {
        let fm = FileManager.default
        try? fm.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: currentLogFile.path) {
            fm.createFile(atPath: currentLogFile.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: currentLogFile)
        _ = try? fileHandle?.seekToEnd()
    }

    private func purgeOldLogs() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: logDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        for url in files where url != currentLogFile {
            if let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               mod < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }

    public func readRecent(lines: Int = 1000) -> String {
        // Simple tail; for prototype we just read full file then take last N
        // lines. Real log volume is low.
        guard let data = try? Data(contentsOf: currentLogFile),
              let str = String(data: data, encoding: .utf8) else {
            return ""
        }
        let allLines = str.split(separator: "\n", omittingEmptySubsequences: false)
        let tail = allLines.suffix(lines)
        return tail.joined(separator: "\n")
    }
}

/// Per-module logger wrapper.
public struct TaggedLogger: Sendable {
    public let module: String
    public let root: AppLogger

    public func debug(_ s: @autoclosure () -> String) { root.log(level: .debug, module: module, message: s()) }
    public func info(_ s: @autoclosure () -> String)  { root.log(level: .info,  module: module, message: s()) }
    public func warn(_ s: @autoclosure () -> String)  { root.log(level: .warn,  module: module, message: s()) }
    public func error(_ s: @autoclosure () -> String) { root.log(level: .error, module: module, message: s()) }
}

extension LogLevel {
    var osType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info:  return .info
        case .warn:  return .default
        case .error: return .error
        }
    }
}

/// Obfuscate sensitive tokens for log output.
public func obfuscate(_ raw: String) -> String {
    if raw.count <= 10 { return "***" }
    let head = raw.prefix(6)
    let tail = raw.suffix(4)
    return "\(head)***\(tail)"
}
