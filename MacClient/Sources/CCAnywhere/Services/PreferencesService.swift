// PreferencesService.swift
// Owns all user-facing preferences:
//   - terminal theme
//   - app appearance (light/dark/system)
//   - terminal font size
//   - Server config
//
// All settings persist to `~/Library/Application Support/cc-anywhere/`.

import Foundation
import SwiftUI

@MainActor
public final class PreferencesService: ObservableObject {
    private let log = AppLogger.shared.tagged("Preferences")

    // MARK: - Storage paths

    public nonisolated static var appSupportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dir = base.appendingPathComponent("cc-anywhere", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var serverConfigURL: URL { Self.appSupportDir.appendingPathComponent("server-config.json") }
    private var generalURL: URL      { Self.appSupportDir.appendingPathComponent("preferences.json") }

    // MARK: - Published state

    @Published public var serverConfig: ServerConfig {
        didSet { persistServer() }
    }

    @Published public var appearance: AppAppearance {
        didSet { persistGeneral() }
    }

    @Published public var followSystemAppearance: Bool {
        didSet { persistGeneral() }
    }

    @Published public var terminalThemeId: String {
        didSet { persistGeneral() }
    }

    @Published public var terminalFontSize: Int {
        didSet { persistGeneral() }
    }

    /// Optional override for the `claude` binary path. When non-empty, takes
    /// precedence over `findClaudeBinary()`'s common-location search. Lets
    /// users on non-standard installs point at the right binary without
    /// relying on PATH being inherited correctly.
    @Published public var claudePathOverride: String {
        didSet { persistGeneral() }
    }

    // MARK: - Init

    public init() {
        // Pre-default
        self.serverConfig = ServerConfig()
        self.appearance = .dark
        self.followSystemAppearance = false
        self.terminalThemeId = TerminalThemes.default.id
        self.terminalFontSize = 13
        self.claudePathOverride = ""

        // Load from disk
        loadServer()
        loadGeneral()
    }

    // MARK: - Read/write

    private func loadServer() {
        guard let data = try? Data(contentsOf: serverConfigURL) else { return }
        do {
            self.serverConfig = try JSONDecoder().decode(ServerConfig.self, from: data)
        } catch {
            log.warn("server-config.json invalid: \(error)")
        }
    }

    private func persistServer() {
        do {
            let data = try JSONEncoder.pretty.encode(serverConfig)
            try data.atomicWrite(to: serverConfigURL, permissions: 0o600)
        } catch {
            log.error("failed to persist server-config: \(error)")
        }
    }

    private struct GeneralPrefs: Codable {
        var appearance: String?
        var followSystem: Bool?
        var terminalThemeId: String?
        var terminalFontSize: Int?
        var claudePathOverride: String?
    }

    private func loadGeneral() {
        guard let data = try? Data(contentsOf: generalURL),
              let prefs = try? JSONDecoder().decode(GeneralPrefs.self, from: data)
        else { return }
        if let a = prefs.appearance, let parsed = AppAppearance(rawValue: a) {
            self.appearance = parsed
        }
        if let fs = prefs.followSystem { self.followSystemAppearance = fs }
        if let id = prefs.terminalThemeId { self.terminalThemeId = id }
        if let sz = prefs.terminalFontSize { self.terminalFontSize = sz }
        if let p = prefs.claudePathOverride { self.claudePathOverride = p }
    }

    private func persistGeneral() {
        let prefs = GeneralPrefs(
            appearance: appearance.rawValue,
            followSystem: followSystemAppearance,
            terminalThemeId: terminalThemeId,
            terminalFontSize: terminalFontSize,
            claudePathOverride: claudePathOverride
        )
        do {
            let data = try JSONEncoder.pretty.encode(prefs)
            try data.atomicWrite(to: generalURL, permissions: 0o600)
        } catch {
            log.error("failed to persist preferences: \(error)")
        }
    }

    // MARK: - Helpers

    public var currentTerminalTheme: TerminalTheme {
        TerminalThemes.byId(terminalThemeId)
    }

    /// The effective palette to apply to the app UI right now.
    public func currentPalette(systemDark: Bool) -> ColorPalette {
        let dark: Bool
        if followSystemAppearance || appearance == .system {
            dark = systemDark
        } else {
            dark = (appearance == .dark)
        }
        return dark ? .dark : .light
    }
}

// MARK: - Helpers

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

extension Data {
    /// Atomic write + chmod
    func atomicWrite(to url: URL, permissions: Int) throws {
        let tmp = url.appendingPathExtension("tmp")
        try self.write(to: tmp, options: .atomic)
        _ = try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: tmp, to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: permissions)],
            ofItemAtPath: url.path
        )
    }
}
