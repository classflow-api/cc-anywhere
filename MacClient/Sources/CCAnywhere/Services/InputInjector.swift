// InputInjector.swift
// Consumes input.* / tool_use.* messages from the Server and writes them
// into the right Tab's PTY.
// See 需求规格说明书 §3.1 M7 + 技术实施文档 §4.5.

import Foundation
import Combine

@MainActor
public final class InputInjector {
    private let log = AppLogger.shared.tagged("InputInjector")
    private weak var processHost: ProcessHost?
    private weak var ws: WSClient?
    private var cancellables = Set<AnyCancellable>()

    public init(processHost: ProcessHost, ws: WSClient) {
        self.processHost = processHost
        self.ws = ws
        ws.inbound
            .sink { [weak self] msg in
                guard let self = self else { return }
                Task { await self.handle(msg) }
            }
            .store(in: &cancellables)
    }

    private func handle(_ msg: ProtocolMessage) async {
        switch msg.type {
        case "input.text":
            await handleText(msg)
        case "input.image":
            await handleImage(msg)
        case "tool_use.approve":
            handleApprove(msg)
        default:
            break
        }
    }

    private func handleText(_ msg: ProtocolMessage) async {
        guard let data = msg.data, let p = decode(data, InputTextPayload.self) else { return }
        guard let tabId = UUID(uuidString: p.tabId) else { return }
        let payload = p.text + "\r"
        if processHost?.terminalsByTab[tabId] == nil {
            await reportInjectError(tabId: p.tabId, message: "Tab 进程已退出，输入未生效")
            return
        }
        processHost?.write(to: tabId, string: payload)
        log.info("injected text \(p.text.count) chars to tab=\(p.tabId)")
    }

    private func handleImage(_ msg: ProtocolMessage) async {
        guard let data = msg.data, let p = decode(data, InputImagePayload.self) else { return }
        guard let tabId = UUID(uuidString: p.tabId),
              let url = URL(string: p.imageUrl) else { return }
        log.info("image to tab=\(p.tabId) url=\(p.imageUrl)")
        // 用 upload_id + 原扩展名 作为本地落盘文件名,避免用户连发同名图(iOS 截图常见
        // 默认 Screenshot.png / IMG_xxxx.jpg)时覆盖前一张 — 这是端到端 dedup 的关键统一 key:
        // phone 端 message.dart 解析 `@<inbox-path>` 提到的 filename = upload_id+ext,
        // phone 端本地 echo 上传成功后也把 attachment.filename 改成同形式,匹配 100% 命中。
        let ext = (p.filename as NSString).pathExtension
        let safeFilename = ext.isEmpty ? p.uploadId : "\(p.uploadId).\(ext)"
        let local = await ImageDownloader.shared.download(
            url: url,
            filename: safeFilename,
            expectedSha256: p.sha256
        )
        guard let localURL = local else {
            await reportInjectError(tabId: p.tabId, message: "图片下载或校验失败")
            return
        }
        // Notify Server it can delete inbox file. Server keys on upload_id.
        await ws?.send(ProtocolMessage(type: "image.fetched",
                                       data: try? AnyJSON(encoding: ["upload_id": p.uploadId])))
        // Claude Code 的 file mention 流程:
        //   1) 输入 `@<path>\r` → 路径被转成 file pill,光标停在输入框等待
        //   2) 再按一次 `\r`  → 真正发送消息(file pill 作为附件)
        // 单次 `@<path>\r` 只完成第一步,消息不会送给 Claude。
        // 注入两次回车,中间留 200ms 让 TUI 完成 file pill 解析。
        processHost?.write(to: tabId, string: "@\(localURL.path)\r")
        try? await Task.sleep(nanoseconds: 200_000_000)
        processHost?.write(to: tabId, string: "\r")
        log.info("injected image @\(localURL.lastPathComponent) + send to tab=\(p.tabId)")
    }

    private func handleApprove(_ msg: ProtocolMessage) {
        guard let data = msg.data, let p = decode(data, ToolUseApprovePayload.self) else { return }
        guard let tabId = UUID(uuidString: p.tabId) else { return }
        let key: String
        switch p.action {
        case "approve": key = "1\r"
        case "reject": key = "2\r"
        case "always_approve": key = "3\r"
        default:
            log.warn("unknown tool_use.approve action: \(p.action)")
            return
        }
        processHost?.write(to: tabId, string: key)
        log.info("approve \(p.action) injected to tab=\(p.tabId)")
    }

    private func reportInjectError(tabId: String, message: String) async {
        let payload: [String: Any] = ["tab_id": tabId, "message": message]
        let json: AnyJSON? = {
            if let d = try? JSONSerialization.data(withJSONObject: payload, options: []) {
                return try? JSONDecoder().decode(AnyJSON.self, from: d)
            }
            return nil
        }()
        await ws?.send(ProtocolMessage(type: "input.error", data: json))
        log.error("inject error tab=\(tabId): \(message)")
    }
}

// MARK: - Helpers

private extension AnyJSON {
    init?(encoding dict: [String: Any]) throws {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []) else {
            return nil
        }
        self = try JSONDecoder().decode(AnyJSON.self, from: data)
    }
}
