// Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.
//
// SettingsJsonInstaller.swift
// 安全 install / uninstall ~/.claude/settings.json 中的 cc-anywhere hooks。
//
// 关键设计（详见 需求规格说明书 §3.1 R-F1-008..011、技术实施文档 §4.3）：
//   - backup-before-write：每次写入前先 backup 到 backupDir，仅保留最近 5 份（R-F1-008）
//   - tmp + atomic rename：禁止 truncate + write；统一走 FileManager.replaceItemAt（R-F1-009）
//   - idempotent install：先扫描，已存在前缀匹配条目则跳过 append（R-F1-010）
//   - 精准识别：仅按 hookBridgePath.path 前缀匹配 command，避免误删其他 plugin（R-F1-011）
//   - 含空格路径处理：command 字段中将路径包在双引号内，Claude Code hook 走 sh -c 解析
//   - 写入后重读校验：确认条目状态符合预期
//
// 使用方：MacClient 偏好面板 ON/OFF 切换、首次启动初始化。
// 不依赖第三方库，仅 Foundation JSONSerialization。

import Foundation

public enum InstallError: Error {
    /// settingsPath 不存在且无法创建（仅在父目录写入失败等极端情况触发）。
    case settingsNotFound
    /// settings.json 解析失败（不是合法 JSON 或顶层不是 object）。
    case settingsCorrupted(String)
    /// 写入权限被拒绝。
    case writePermissionDenied
    /// backup 阶段失败。
    case backupFailed(String)
}

/// 当前 ~/.claude/settings.json 中 cc-anywhere hooks 的安装摘要。
/// 用于偏好面板回显，区分 M1-M3 / M4 模式。
public struct InstalledSummary {
    /// PreToolUse 中 matcher=`AskUserQuestion` 的 cc-anywhere 条目存在
    public let hasAsk: Bool
    /// PreToolUse 中 matcher=`Bash|Write|Edit` 的 cc-anywhere 条目存在（子命令为 `progress pre` 或 `ask`）
    public let hasProgressPre: Bool
    /// PostToolUse 中 matcher=`.*` 的 cc-anywhere 条目存在
    public let hasProgressPost: Bool
    /// Notification 中 cc-anywhere 条目存在
    public let hasNotification: Bool
    /// Bash|Write|Edit 的子命令是 `ask` —— M4 启用态
    public let m4Enabled: Bool

    public init(hasAsk: Bool, hasProgressPre: Bool, hasProgressPost: Bool, hasNotification: Bool, m4Enabled: Bool) {
        self.hasAsk = hasAsk
        self.hasProgressPre = hasProgressPre
        self.hasProgressPost = hasProgressPost
        self.hasNotification = hasNotification
        self.m4Enabled = m4Enabled
    }
}

public final class SettingsJsonInstaller {
    private let settingsPath: URL
    private let backupDir: URL
    private let hookBridgePath: URL
    private let log: TaggedLogger

    /// `Bundle.module` 默认参数限制同 HookBridgeDeployer：默认值通过静态属性提供，
    /// 因此 init 直接接受具体 URL。
    public init(
        settingsPath: URL = SettingsJsonInstaller.defaultSettingsPath,
        backupDir: URL = SettingsJsonInstaller.defaultBackupDir,
        hookBridgePath: URL,
        log: TaggedLogger = AppLogger.shared.tagged("SettingsJsonInstaller")
    ) {
        self.settingsPath = settingsPath
        self.backupDir = backupDir
        self.hookBridgePath = hookBridgePath
        self.log = log
    }

    // MARK: - Public defaults

    /// `~/.claude/settings.json`
    public static var defaultSettingsPath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/settings.json")
    }

    /// `~/Library/Application Support/cc-anywhere/backups`
    public static var defaultBackupDir: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return appSupport.appendingPathComponent("cc-anywhere/backups")
    }

    // MARK: - Public API

    /// 是否存在任何 cc-anywhere hook（不分 M1-M3 / M4）。
    public func isInstalled() -> Bool {
        let summary = currentInstalled()
        return summary.hasAsk || summary.hasProgressPre || summary.hasProgressPost || summary.hasNotification
    }

    /// 安装 M1-M3 hooks（AskUserQuestion ask + Bash|Write|Edit progress pre + .* progress post + Notification）。
    /// idempotent：已经安装 cc-anywhere 同类条目则跳过；
    /// 不动其他 plugin 的 hook（精准前缀匹配）。
    public func installM1M3() throws {
        try mutateSettings { root in
            var hooks = (root["hooks"] as? [String: Any]) ?? [:]

            // PreToolUse —— append AskUserQuestion ask + Bash|Write|Edit progress pre
            var pre = (hooks["PreToolUse"] as? [[String: Any]]) ?? []
            if !pre.contains(where: { self.isCCAnywhereEntry($0, matcher: "AskUserQuestion") }) {
                pre.append(self.makeEntry(
                    matcher: "AskUserQuestion",
                    timeout: 1800,
                    subcommand: "ask"
                ))
            }
            if !pre.contains(where: { self.isCCAnywhereEntry($0, matcher: "Bash|Write|Edit") }) {
                pre.append(self.makeEntry(
                    matcher: "Bash|Write|Edit",
                    timeout: 600,
                    subcommand: "progress pre"
                ))
            }
            hooks["PreToolUse"] = pre

            // PostToolUse —— append .* progress post
            var post = (hooks["PostToolUse"] as? [[String: Any]]) ?? []
            if !post.contains(where: { self.isCCAnywhereEntry($0, matcher: ".*") }) {
                post.append(self.makeEntry(
                    matcher: ".*",
                    timeout: nil,
                    subcommand: "progress post"
                ))
            }
            hooks["PostToolUse"] = post

            // Notification —— append（无 matcher）
            var notif = (hooks["Notification"] as? [[String: Any]]) ?? []
            if !notif.contains(where: { self.isCCAnywhereEntry($0, matcher: nil) }) {
                notif.append(self.makeEntry(
                    matcher: nil,
                    timeout: nil,
                    subcommand: "notification"
                ))
            }
            hooks["Notification"] = notif

            root["hooks"] = hooks
            return root
        }

        // 校验：重读 + 解析 + 确认目标条目存在
        let s = currentInstalled()
        guard s.hasAsk, s.hasProgressPre, s.hasProgressPost, s.hasNotification else {
            log.error("installM1M3 verification failed: \(s)")
            throw InstallError.settingsCorrupted("post-install verification failed")
        }
        log.info("installM1M3 ok: ask=\(s.hasAsk) pre=\(s.hasProgressPre) post=\(s.hasProgressPost) notif=\(s.hasNotification)")
    }

    /// 启用 M4：将 PreToolUse 中 matcher=Bash|Write|Edit 的 cc-anywhere 内层 command 子命令从
    /// `progress pre` 改为 `ask`，timeout 从 600 提到 1800。
    /// 前置条件：M1-M3 已安装（否则会先 install 再 enable）。
    public func enableM4() throws {
        if !isInstalled() {
            try installM1M3()
        }
        try mutateSettings { root in
            var hooks = (root["hooks"] as? [String: Any]) ?? [:]
            var pre = (hooks["PreToolUse"] as? [[String: Any]]) ?? []
            for i in pre.indices {
                guard self.isCCAnywhereEntry(pre[i], matcher: "Bash|Write|Edit") else { continue }
                pre[i] = self.makeEntry(
                    matcher: "Bash|Write|Edit",
                    timeout: 1800,
                    subcommand: "ask"
                )
            }
            hooks["PreToolUse"] = pre
            root["hooks"] = hooks
            return root
        }
        let s = currentInstalled()
        guard s.m4Enabled else {
            log.error("enableM4 verification failed: \(s)")
            throw InstallError.settingsCorrupted("post-enableM4 verification failed")
        }
        log.info("enableM4 ok")
    }

    /// 关闭 M4：将 Bash|Write|Edit 子命令从 `ask` 改回 `progress pre`，timeout 1800 → 600。
    public func disableM4() throws {
        try mutateSettings { root in
            var hooks = (root["hooks"] as? [String: Any]) ?? [:]
            var pre = (hooks["PreToolUse"] as? [[String: Any]]) ?? []
            for i in pre.indices {
                guard self.isCCAnywhereEntry(pre[i], matcher: "Bash|Write|Edit") else { continue }
                pre[i] = self.makeEntry(
                    matcher: "Bash|Write|Edit",
                    timeout: 600,
                    subcommand: "progress pre"
                )
            }
            hooks["PreToolUse"] = pre
            root["hooks"] = hooks
            return root
        }
        let s = currentInstalled()
        guard !s.m4Enabled else {
            log.error("disableM4 verification failed: \(s)")
            throw InstallError.settingsCorrupted("post-disableM4 verification failed")
        }
        log.info("disableM4 ok")
    }

    /// 卸载所有 cc-anywhere hooks（按 command 前缀精准匹配）。
    /// filter 后空数组 → 删 key；hooks object 整体空 → 删 hooks key。
    public func uninstall() throws {
        try mutateSettings { root in
            guard var hooks = root["hooks"] as? [String: Any] else { return root }

            for key in ["PreToolUse", "PostToolUse", "Notification"] {
                guard let arr = hooks[key] as? [[String: Any]] else { continue }
                let filtered = arr.compactMap { entry -> [String: Any]? in
                    var entry = entry
                    if var inner = entry["hooks"] as? [[String: Any]] {
                        inner = inner.filter { !self.commandHasCCPrefix($0) }
                        if inner.isEmpty { return nil }
                        entry["hooks"] = inner
                        return entry
                    }
                    return entry
                }
                if filtered.isEmpty {
                    hooks.removeValue(forKey: key)
                } else {
                    hooks[key] = filtered
                }
            }

            if hooks.isEmpty {
                root.removeValue(forKey: "hooks")
            } else {
                root["hooks"] = hooks
            }
            return root
        }

        let s = currentInstalled()
        guard !s.hasAsk, !s.hasProgressPre, !s.hasProgressPost, !s.hasNotification else {
            log.error("uninstall verification failed: \(s)")
            throw InstallError.settingsCorrupted("post-uninstall verification failed")
        }
        log.info("uninstall ok")
    }

    /// 扫描当前 settings.json 中 cc-anywhere hooks 的状态摘要。
    /// 文件不存在或解析失败均返回全 false（用于偏好面板"未安装"状态）。
    public func currentInstalled() -> InstalledSummary {
        guard let root = try? readSettingsObject() else {
            return InstalledSummary(hasAsk: false, hasProgressPre: false, hasProgressPost: false, hasNotification: false, m4Enabled: false)
        }
        let hooks = (root["hooks"] as? [String: Any]) ?? [:]
        let pre = (hooks["PreToolUse"] as? [[String: Any]]) ?? []
        let post = (hooks["PostToolUse"] as? [[String: Any]]) ?? []
        let notif = (hooks["Notification"] as? [[String: Any]]) ?? []

        let askEntry = pre.first(where: { isCCAnywhereEntry($0, matcher: "AskUserQuestion") })
        let bweEntry = pre.first(where: { isCCAnywhereEntry($0, matcher: "Bash|Write|Edit") })
        let postEntry = post.first(where: { isCCAnywhereEntry($0, matcher: ".*") })
        let notifEntry = notif.first(where: { isCCAnywhereEntry($0, matcher: nil) })

        let m4 = bweEntry.flatMap { entryCommandSubcommand($0) } == "ask"

        return InstalledSummary(
            hasAsk: askEntry != nil,
            hasProgressPre: bweEntry != nil,
            hasProgressPost: postEntry != nil,
            hasNotification: notifEntry != nil,
            m4Enabled: m4
        )
    }

    // MARK: - Private — settings read / write pipeline

    /// 安全的 mutate 流程：read → parse → backup → transform → tmp write → atomic rename。
    private func mutateSettings(_ transform: (inout [String: Any]) -> [String: Any]) throws {
        // 1) read（不存在 → 视为空对象，并保证父目录存在）
        var root = try readSettingsObjectCreatingIfMissing()

        // 2) backup（仅当文件实际存在；首次创建无需 backup）
        if FileManager.default.fileExists(atPath: settingsPath.path) {
            try backupCurrent()
        }

        // 3) transform
        root = transform(&root)

        // 4) serialize（sortedKeys 保证 diff 友好）
        let data: Data
        do {
            data = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
            )
        } catch {
            throw InstallError.settingsCorrupted("serialize: \(error.localizedDescription)")
        }

        // 5) tmp write + atomic rename
        try atomicWrite(data: data, to: settingsPath)
    }

    private func readSettingsObject() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsPath.path) else {
            throw InstallError.settingsNotFound
        }
        let data: Data
        do {
            data = try Data(contentsOf: settingsPath)
        } catch {
            throw InstallError.settingsCorrupted("read: \(error.localizedDescription)")
        }
        if data.isEmpty { return [:] }
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw InstallError.settingsCorrupted("parse: \(error.localizedDescription)")
        }
        guard let root = obj as? [String: Any] else {
            throw InstallError.settingsCorrupted("top-level not an object")
        }
        return root
    }

    /// 不存在时返回空对象并确保父目录存在；其他错误透传。
    private func readSettingsObjectCreatingIfMissing() throws -> [String: Any] {
        if !FileManager.default.fileExists(atPath: settingsPath.path) {
            let parent = settingsPath.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(
                    at: parent,
                    withIntermediateDirectories: true
                )
            } catch {
                log.error("create parent dir failed at \(parent.path): \(error)")
                throw InstallError.settingsNotFound
            }
            return [:]
        }
        return try readSettingsObject()
    }

    /// backup 现有 settings.json 到 backupDir/settings.json.bak.<unix_timestamp>，
    /// 仅保留最近 5 份（按时间戳排序）。
    private func backupCurrent() throws {
        do {
            try FileManager.default.createDirectory(
                at: backupDir,
                withIntermediateDirectories: true
            )
        } catch {
            throw InstallError.backupFailed("createDir: \(error.localizedDescription)")
        }
        let ts = Int(Date().timeIntervalSince1970)
        let dest = backupDir.appendingPathComponent("settings.json.bak.\(ts)")
        do {
            // 若同秒内重复调用，覆盖之（足够罕见，且语义上 backup 不应失败）
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: settingsPath, to: dest)
        } catch {
            throw InstallError.backupFailed("copy: \(error.localizedDescription)")
        }

        // 清理：仅保留最近 5 份
        do {
            let entries = try FileManager.default.contentsOfDirectory(atPath: backupDir.path)
            let prefix = "settings.json.bak."
            let backups = entries
                .filter { $0.hasPrefix(prefix) }
                .compactMap { name -> (URL, Int)? in
                    let suffix = String(name.dropFirst(prefix.count))
                    guard let t = Int(suffix) else { return nil }
                    return (backupDir.appendingPathComponent(name), t)
                }
                .sorted { $0.1 > $1.1 }
            for (url, _) in backups.dropFirst(5) {
                try? FileManager.default.removeItem(at: url)
            }
        } catch {
            // 清理失败不致命，仅记录
            log.warn("backup pruning failed: \(error)")
        }
    }

    /// 写入临时文件后用 `replaceItemAt` 原子替换；不存在则直接 move。
    /// 不使用 truncate + write（违反 R-F1-009）。
    private func atomicWrite(data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        } catch {
            throw InstallError.writePermissionDenied
        }
        let tmpURL = dir.appendingPathComponent(
            "\(url.lastPathComponent).tmp.\(getpid()).\(UUID().uuidString.prefix(8))"
        )
        do {
            try data.write(to: tmpURL, options: .atomic)
        } catch {
            log.error("tmp write failed at \(tmpURL.path): \(error)")
            throw InstallError.writePermissionDenied
        }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
            } else {
                try FileManager.default.moveItem(at: tmpURL, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            log.error("atomic rename failed: \(error)")
            throw InstallError.writePermissionDenied
        }
    }

    // MARK: - Private — entry helpers

    /// 构造一个 cc-anywhere hook 条目。
    /// matcher 为 nil 时不写 matcher 字段（用于 Notification）。
    /// timeout 为 nil 时不写 timeout 字段。
    private func makeEntry(matcher: String?, timeout: Int?, subcommand: String) -> [String: Any] {
        var entry: [String: Any] = [:]
        if let matcher { entry["matcher"] = matcher }
        if let timeout { entry["timeout"] = timeout }
        entry["hooks"] = [[
            "type": "command",
            "command": makeCommandString(subcommand: subcommand)
        ]]
        return entry
    }

    /// 构造 command 字符串：路径用双引号包裹以兼容含空格的 `~/Library/Application Support/...`。
    /// Claude Code hook 通过 `sh -c` 解析命令行，双引号是稳健写法。
    private func makeCommandString(subcommand: String) -> String {
        return "\"\(hookBridgePath.path)\" \(subcommand)"
    }

    /// 一个外层 hook entry 是否是 cc-anywhere 的（按 matcher + 内层 command 前缀双重判定）。
    /// matcher 参数为 nil 时只比对 command 前缀（用于 Notification 这种无 matcher 的事件）。
    private func isCCAnywhereEntry(_ entry: [String: Any], matcher: String?) -> Bool {
        if let want = matcher {
            guard (entry["matcher"] as? String) == want else { return false }
        } else {
            // 无 matcher 的事件：要求条目本身也无 matcher 字段
            if entry["matcher"] != nil { return false }
        }
        return commandHasCCPrefix(entry)
    }

    /// entry.hooks[*].command 中是否存在以 hookBridgePath.path 开头的命令。
    /// 注意：command 字符串可能用双引号包裹路径（含空格情况），需要在比对前剥离首引号。
    private func commandHasCCPrefix(_ entry: [String: Any]) -> Bool {
        guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
        for item in inner {
            guard let cmd = item["command"] as? String else { continue }
            if commandStringMatchesBridgePath(cmd) { return true }
        }
        return false
    }

    /// 解析 command 字段，判断其第一个 token（剥离可选首尾双引号）是否等于 / hasPrefix hookBridgePath.path。
    /// 严格匹配 path 自身或 path+空格（避免误删 path 同前缀的其他脚本，如 `bridge.py.bak` 这种）。
    private func commandStringMatchesBridgePath(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        let stripped: String
        if trimmed.hasPrefix("\"") {
            // 取首段引号内内容
            let afterQuote = trimmed.dropFirst()
            if let endQuoteIdx = afterQuote.firstIndex(of: "\"") {
                stripped = String(afterQuote[afterQuote.startIndex..<endQuoteIdx])
            } else {
                stripped = String(afterQuote)
            }
        } else {
            // 第一个空白前的 token
            if let spaceIdx = trimmed.firstIndex(where: { $0.isWhitespace }) {
                stripped = String(trimmed[trimmed.startIndex..<spaceIdx])
            } else {
                stripped = trimmed
            }
        }
        return stripped == hookBridgePath.path
    }

    /// 从一个 cc-anywhere entry 中提取子命令（例如 "ask" / "progress pre" / "progress post" / "notification"）。
    /// 仅看第一条内层 hook。
    private func entryCommandSubcommand(_ entry: [String: Any]) -> String? {
        guard let inner = entry["hooks"] as? [[String: Any]],
              let first = inner.first,
              let cmd = first["command"] as? String else { return nil }
        let trimmed = cmd.trimmingCharacters(in: .whitespaces)
        // 跳过首段 "<path>"
        let rest: String
        if trimmed.hasPrefix("\"") {
            let afterQuote = trimmed.dropFirst()
            if let endQuoteIdx = afterQuote.firstIndex(of: "\"") {
                let afterClose = afterQuote.index(after: endQuoteIdx)
                rest = String(afterQuote[afterClose...])
            } else {
                rest = String(afterQuote)
            }
        } else {
            if let spaceIdx = trimmed.firstIndex(where: { $0.isWhitespace }) {
                rest = String(trimmed[trimmed.index(after: spaceIdx)...])
            } else {
                rest = ""
            }
        }
        return rest.trimmingCharacters(in: .whitespaces)
    }
}
