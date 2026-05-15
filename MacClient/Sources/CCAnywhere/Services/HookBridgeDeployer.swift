// Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.
//
// HookBridgeDeployer.swift
// 把 Swift Package bundle 内的 `cc-anywhere-hook-bridge.py` 在 Mac App 启动时
// 复制到 `~/Library/Application Support/cc-anywhere/bin/` 并 chmod 0755。
// 升级时通过 SHA-256 校验 bundle 内置版本与已部署版本，不一致则原子覆盖。
//
// 详见 技术实施文档.md §4.1.2 部署位置。
//
// 部署目标路径会被 `~/.claude/settings.json` 中 hook 的 command 字段引用，
// 因此该路径稳定、不依赖 PATH。

import Foundation
import CryptoKit

public enum DeployError: Error {
    /// Swift Package bundle 内未找到 `cc-anywhere-hook-bridge.py` 资源。
    case bundleResourceMissing
    /// 写入 / 重命名 / chmod 阶段失败。
    case writeFailed(String)
}

public final class HookBridgeDeployer {
    private let bundle: Bundle
    private let log: TaggedLogger

    /// 注意：`Bundle.module` 是 SwiftPM 自动生成的 internal 符号，无法作为
    /// public 默认参数值，因此显式传 `nil` 时由 init 内部 fallback 到
    /// `.module`，外部调用方仍可显式传入自定义 bundle（用于单测）。
    public init(
        bundle: Bundle? = nil,
        log: TaggedLogger = AppLogger.shared.tagged("HookBridgeDeployer")
    ) {
        self.bundle = bundle ?? .module
        self.log = log
    }

    // MARK: - Public API

    /// 目标可执行路径：`~/Library/Application Support/cc-anywhere/bin/cc-anywhere-hook-bridge.py`。
    /// `~/.claude/settings.json` 中 hook 的 command 字段必须指向此路径。
    public var deployedScriptURL: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return appSupport
            .appendingPathComponent("cc-anywhere/bin/cc-anywhere-hook-bridge.py")
    }

    /// 检测是否已经部署当前 bundle 内的版本（SHA-256 一致）。
    /// 注意：仅做内容比对，不校验权限位。`deployIfNeeded()` 始终会重置权限位为 0755。
    public func isUpToDate() -> Bool {
        guard let bundleData = try? loadBundleScriptData(),
              let deployedData = try? Data(contentsOf: deployedScriptURL) else {
            return false
        }
        return sha256(bundleData) == sha256(deployedData)
    }

    /// 部署或升级 hook bridge 脚本：
    /// 1. 从 bundle 读取 → 计算 SHA-256
    /// 2. 若目标已存在且 SHA-256 一致，跳过写入
    /// 3. 否则：写临时文件 → 原子替换 → chmod 0755
    /// 幂等。返回是否实际写入了文件。
    @discardableResult
    public func deployIfNeeded() throws -> Bool {
        let bundleData = try loadBundleScriptData()
        let targetURL = deployedScriptURL
        let targetDir = targetURL.deletingLastPathComponent()

        // 父目录不存在则创建。
        do {
            try FileManager.default.createDirectory(
                at: targetDir,
                withIntermediateDirectories: true
            )
        } catch {
            log.error("create dir failed at \(targetDir.path): \(error)")
            throw DeployError.writeFailed("createDirectory: \(error.localizedDescription)")
        }

        let bundleHash = sha256(bundleData)
        let existingHash: String? = (try? Data(contentsOf: targetURL)).map(sha256)

        if existingHash == bundleHash {
            // 内容一致：仅确保权限位正确，不写文件。
            do {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: targetURL.path
                )
            } catch {
                log.warn("chmod on up-to-date script failed: \(error)")
            }
            log.debug("hook bridge already up-to-date at \(targetURL.path) (sha256=\(bundleHash.prefix(12)))")
            return false
        }

        // 内容不一致或目标不存在：写临时文件 → 原子替换。
        let tmpURL = targetDir.appendingPathComponent(
            ".cc-anywhere-hook-bridge.py.tmp-\(UUID().uuidString)"
        )
        do {
            try bundleData.write(to: tmpURL, options: .atomic)
        } catch {
            log.error("write tmp failed at \(tmpURL.path): \(error)")
            throw DeployError.writeFailed("writeTmp: \(error.localizedDescription)")
        }

        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: tmpURL.path
            )
        } catch {
            // chmod 失败不致命，但记录；replaceItemAt 仍尝试。
            log.warn("chmod tmp failed: \(error)")
        }

        do {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                _ = try FileManager.default.replaceItemAt(targetURL, withItemAt: tmpURL)
            } else {
                try FileManager.default.moveItem(at: tmpURL, to: targetURL)
            }
        } catch {
            // 清理临时文件
            try? FileManager.default.removeItem(at: tmpURL)
            log.error("atomic replace failed: \(error)")
            throw DeployError.writeFailed("replaceItemAt: \(error.localizedDescription)")
        }

        // 最终确保目标文件权限位 0755（replaceItemAt 可能保留旧权限）。
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: targetURL.path
            )
        } catch {
            log.error("chmod target failed: \(error)")
            throw DeployError.writeFailed("chmodTarget: \(error.localizedDescription)")
        }

        if existingHash == nil {
            log.info("hook bridge deployed to \(targetURL.path) (sha256=\(bundleHash.prefix(12)))")
        } else {
            log.info("hook bridge upgraded at \(targetURL.path) (sha256 \(existingHash!.prefix(12)) -> \(bundleHash.prefix(12)))")
        }
        return true
    }

    /// 删除已部署的脚本（用户彻底卸载 cc-anywhere 时调用）。
    /// 文件不存在不视为错误。
    public func removeDeployed() throws {
        let url = deployedScriptURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            log.debug("removeDeployed: nothing at \(url.path)")
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
            log.info("hook bridge removed from \(url.path)")
        } catch {
            log.error("remove failed: \(error)")
            throw DeployError.writeFailed("remove: \(error.localizedDescription)")
        }
    }

    // MARK: - Private helpers

    private func loadBundleScriptData() throws -> Data {
        // 优先 Bundle.module（SwiftPM target 自动 bundle）。
        // 若调用方传入了非 .module bundle，仍按相同 resource name 查找。
        if let url = bundle.url(forResource: "cc-anywhere-hook-bridge", withExtension: "py"),
           let data = try? Data(contentsOf: url) {
            return data
        }
        // 兜底：用本类所在 bundle 再尝试一次。
        let fallback = Bundle(for: HookBridgeDeployer.self)
        if fallback !== bundle,
           let url = fallback.url(forResource: "cc-anywhere-hook-bridge", withExtension: "py"),
           let data = try? Data(contentsOf: url) {
            return data
        }
        log.error("bundle resource missing: cc-anywhere-hook-bridge.py")
        throw DeployError.bundleResourceMissing
    }

    private func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
