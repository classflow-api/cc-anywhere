// SlashCommandBridge.swift
// 监听 ws inbound 的 `slash.list.request`,扫描本机 Claude Code 可用的 slash commands
// (内置 + 用户级 + 项目级 + plugin),返回 `slash.list.response` 给手机端。

import Foundation
import Combine

@MainActor
public final class SlashCommandBridge {
    private let log = AppLogger.shared.tagged("SlashCommandBridge")
    private weak var ws: WSClient?
    private weak var tabManager: TabManager?
    private var cancellables = Set<AnyCancellable>()

    /// Claude Code 内置 slash commands(CLI 自带,无法通过文件系统扫描)。
    /// 保持与 https://docs.claude.com/en/docs/claude-code/cli-reference 同步。
    private static let builtinCommands: [(String, String)] = [
        ("clear", "清空当前会话上下文"),
        ("compact", "压缩当前对话历史(节省上下文)"),
        ("cost", "查看本次会话累计 token 用量"),
        ("help", "查看所有可用命令"),
        ("quit", "退出 Claude Code"),
        ("exit", "退出 Claude Code"),
        ("init", "为当前项目生成 CLAUDE.md"),
        ("model", "切换模型(Opus/Sonnet/Haiku)"),
        ("login", "登录 Anthropic 账号"),
        ("logout", "退出登录"),
        ("add-dir", "把另一个目录加入 Claude 可访问范围"),
        ("memory", "查看/编辑长期记忆"),
        ("pr_comments", "查看当前 PR 评论"),
        ("bug", "上报 bug 给 Anthropic"),
        ("review", "对当前分支做代码审查"),
    ]

    public init(ws: WSClient, tabManager: TabManager) {
        self.ws = ws
        self.tabManager = tabManager
        ws.inbound
            .filter { $0.type == "slash.list.request" }
            .sink { [weak self] msg in
                guard let self = self else { return }
                Task { await self.handleRequest(msg) }
            }
            .store(in: &cancellables)
    }

    private func handleRequest(_ msg: ProtocolMessage) async {
        guard let ws = ws else { return }
        let tabId = (msg.data?.dictValue?["tab_id"] as? String) ?? ""
        let commands = collectCommands(forTabId: tabId)
        log.info("collected \(commands.count) slash commands for tab=\(tabId)")
        let payload: [String: Any] = [
            "tab_id": tabId,
            "commands": commands.map { [
                "name": $0.name,
                "description": $0.description,
                "source": $0.source,
            ] },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let anyJson = try? JSONDecoder().decode(AnyJSON.self, from: data) else { return }
        await ws.send(ProtocolMessage(type: "slash.list.response", data: anyJson))
    }

    private struct CommandEntry {
        let name: String
        let description: String
        let source: String
    }

    private func collectCommands(forTabId tabId: String) -> [CommandEntry] {
        var result: [CommandEntry] = []
        var seen = Set<String>()

        for (name, desc) in Self.builtinCommands {
            if seen.insert(name).inserted {
                result.append(CommandEntry(name: name, description: desc, source: "builtin"))
            }
        }

        // 用户级:~/.claude/commands/
        let home = FileManager.default.homeDirectoryForCurrentUser
        result.append(contentsOf: scanCommandsDir(
            home.appendingPathComponent(".claude/commands"),
            source: "user",
            seen: &seen
        ))

        // 项目级:<workDir>/.claude/commands/  — workDir 来自 tab 的 folder(URL 类型)
        if let tab = tabManager?.tabs.first(where: { $0.id.uuidString == tabId }) {
            let projectURL = tab.folder.appendingPathComponent(".claude/commands")
            result.append(contentsOf: scanCommandsDir(projectURL, source: "project", seen: &seen))
        }

        // Plugin:~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/commands/*.md
        let pluginsCache = home.appendingPathComponent(".claude/plugins/cache")
        if let marketplaces = try? FileManager.default.contentsOfDirectory(at: pluginsCache, includingPropertiesForKeys: nil) {
            for mp in marketplaces {
                guard let plugins = try? FileManager.default.contentsOfDirectory(at: mp, includingPropertiesForKeys: nil) else { continue }
                for plugin in plugins {
                    guard let versions = try? FileManager.default.contentsOfDirectory(at: plugin, includingPropertiesForKeys: nil) else { continue }
                    // 取最新一个 version(简化:取目录列表第一个,通常只一个)
                    for v in versions {
                        let cmdDir = v.appendingPathComponent("commands")
                        result.append(contentsOf: scanCommandsDir(
                            cmdDir,
                            source: "plugin:\(plugin.lastPathComponent)",
                            seen: &seen
                        ))
                    }
                }
            }
        }

        return result.sorted { $0.name < $1.name }
    }

    private func scanCommandsDir(_ dir: URL, source: String, seen: inout Set<String>) -> [CommandEntry] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        var out: [CommandEntry] = []
        for url in entries where url.pathExtension == "md" {
            let name = url.deletingPathExtension().lastPathComponent
            if !seen.insert(name).inserted { continue }
            let desc = readDescriptionFromFrontmatter(url) ?? ""
            out.append(CommandEntry(name: name, description: desc, source: source))
        }
        return out
    }

    /// 从 .md 文件 frontmatter 读 `description:` 字段(yaml 兼容简单解析,只读前 50 行)。
    private func readDescriptionFromFrontmatter(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n").prefix(50)
        var inFrontmatter = false
        for line in lines {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s == "---" {
                if inFrontmatter { return nil }
                inFrontmatter = true
                continue
            }
            if inFrontmatter, s.hasPrefix("description:") {
                let v = s.dropFirst("description:".count).trimmingCharacters(in: .whitespaces)
                return v.replacingOccurrences(of: "\"", with: "")
            }
        }
        return nil
    }
}

// MARK: - AnyJSON helper

private extension AnyJSON {
    var dictValue: [String: Any]? {
        guard let data = try? JSONEncoder().encode(self),
              let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return any
    }
}
