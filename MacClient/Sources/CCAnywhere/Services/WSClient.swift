// WSClient.swift
// WebSocket client over URLSessionWebSocketTask.
// See 需求规格说明书 §3.1 M5 / M8 + 技术实施文档 §4.4.

import Foundation
import SwiftUI
import Combine

@MainActor
public final class WSClient: NSObject, ObservableObject {
    private let log = AppLogger.shared.tagged("WSClient")

    public enum State: Equatable {
        case disconnected(reason: String?)
        case connecting
        case connected
        case reconnecting(attempt: Int)

        public var displayLabel: String {
            switch self {
            case .disconnected(let r):
                return r.map { "未连接 - \($0)" } ?? "未连接"
            case .connecting: return "连接中…"
            case .connected: return "已连接"
            case .reconnecting(let n): return "重连中（第 \(n) 次）…"
            }
        }
    }

    @Published public private(set) var state: State = .disconnected(reason: nil)
    @Published public private(set) var phoneCount: Int = 0
    @Published public private(set) var phoneNames: [String] = []
    @Published public private(set) var lastError: String? = nil

    /// Hot stream of inbound messages — UI / services subscribe.
    public let inbound = PassthroughSubject<ProtocolMessage, Never>()

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var currentConfig: ServerConfig?
    private var reconnectAttempt = 0
    private let backoffSeconds: [Int] = [1, 3, 10, 30]
    private var manualDisconnect = false
    /// 主动 cancel(.goingAway/.normalClosure) 时置 true,didCloseWith 看到后直接忽略,
    /// 避免触发 handleDisconnect 又安排一轮 reconnect,与 connect() 已经发起的新连接形成风暴。
    private var intentionalCancel = false
    private var heartbeatTimer: Timer?

    public override init() { super.init() }

    // MARK: - API

    public func connect(config: ServerConfig) {
        currentConfig = config
        manualDisconnect = false
        guard config.isUsable, let url = config.wsURL else {
            state = .disconnected(reason: "配置不完整")
            log.warn("connect skipped: incomplete config")
            return
        }
        // Tear down any previous task
        if task != nil {
            intentionalCancel = true
            task?.cancel(with: .goingAway, reason: nil)
            task = nil
        }

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: .main)
        state = .connecting
        log.info("connecting to \(url.absoluteString)")
        var req = URLRequest(url: url)
        req.setValue("cc-anywhere/0.1 mac", forHTTPHeaderField: "User-Agent")
        let t = session!.webSocketTask(with: req)
        task = t
        t.resume()
        // Pump receive loop
        startReceive()
        // Bind
        Task { await sendBind(token: config.masterToken) }
        startHeartbeat()
    }

    public func disconnect() {
        manualDisconnect = true
        stopHeartbeat()
        if task != nil {
            intentionalCancel = true
            task?.cancel(with: .normalClosure, reason: nil)
            task = nil
        }
        state = .disconnected(reason: "已停止")
    }

    public func reconnect() {
        guard let cfg = currentConfig else { return }
        manualDisconnect = false
        connect(config: cfg)
    }

    public func send(_ message: ProtocolMessage) async {
        // Allow sending during .connecting too — bind handshake runs before state becomes .connected.
        // task is nil only when .disconnected/.reconnecting, so this guard covers both.
        guard let t = task else {
            log.warn("send dropped (no task): \(message.type)")
            return
        }
        do {
            let data = try JSONEncoder.pretty.encode(message)
            if let str = String(data: data, encoding: .utf8) {
                try await t.send(.string(str))
            }
        } catch {
            log.error("send \(message.type) failed: \(error)")
        }
    }

    public func sendRaw(type: String, payload: AnyJSON?) async {
        await send(ProtocolMessage(type: type, data: payload))
    }

    // MARK: - Heartbeat (5s) + RTT 测量

    /// 最近 N 次 ping/pong 的往返时间（毫秒）。供 ActivityPanel sparkline 使用。
    @Published public private(set) var latencyHistoryMs: [Int] = []

    private var lastPingSentAt: Date?
    private let latencyHistoryCap = 30
    /// 连续多少次 ping 没收到 pong → 视为连接已死,主动 reconnect。
    /// 5s * 3 = 15s 内没回 pong,即触发重连。
    private let pongMissedThreshold = 3
    private var pongMissedCount = 0

    private func startHeartbeat() {
        stopHeartbeat()
        pongMissedCount = 0
        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: 5, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                // 上一轮 ping 还没收到 pong → 计数 +1
                if self.lastPingSentAt != nil {
                    self.pongMissedCount += 1
                    if self.pongMissedCount >= self.pongMissedThreshold {
                        self.log.warn("pong missed \(self.pongMissedCount) consecutive — forcing reconnect")
                        self.lastPingSentAt = nil
                        self.pongMissedCount = 0
                        // socket 可能 ESTABLISHED 但 server 端已断,本地 didClose/receive 没触发。
                        // 主动走 handleDisconnect 流程触发 backoff reconnect。
                        self.handleDisconnect(reason: "心跳超时")
                        return
                    }
                }
                self.lastPingSentAt = Date()
                await self.send(ProtocolMessage(type: "ping"))
            }
        }
    }

    /// 收到 pong 时调用：用 lastPingSentAt 估算 RTT，append 到 history。
    /// 简化版：不按 id 关联（5s 心跳间隔远大于 RTT，单 ping pending OK）。
    fileprivate func handlePong() {
        guard let sentAt = lastPingSentAt else { return }
        pongMissedCount = 0
        let rtt = max(1, Int(Date().timeIntervalSince(sentAt) * 1000))
        var hist = latencyHistoryMs
        hist.append(rtt)
        if hist.count > latencyHistoryCap {
            hist.removeFirst(hist.count - latencyHistoryCap)
        }
        latencyHistoryMs = hist
        lastPingSentAt = nil
    }
    private func stopHeartbeat() {
        heartbeatTimer?.invalidate(); heartbeatTimer = nil
    }

    // MARK: - Bind

    private func sendBind(token: String) async {
        let payload = BindMacRequest(token: token)
        guard let data = try? JSONEncoder.pretty.encode(payload),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let json = dictToAnyJSON(dict) else { return }
        await send(ProtocolMessage(type: "bind", data: json))
    }

    // MARK: - Receive loop

    private func startReceive() {
        guard let t = task else { return }
        t.receive { [weak self, weak t] result in
            Task { @MainActor [weak self, weak t] in
                guard let self = self else { return }
                // 旧 task 的回调:已经被 connect()/disconnect() 主动 cancel,
                // 此刻 self.task 已指向新 task(或为 nil),忽略以避免 reconnect 风暴。
                guard let t = t, t === self.task else {
                    self.log.debug("receive callback ignored (stale task)")
                    return
                }
                switch result {
                case .success(let message):
                    self.handleIncoming(message)
                    self.startReceive() // continue
                case .failure(let error):
                    self.log.warn("receive error: \(error.localizedDescription)")
                    self.handleDisconnect(reason: error.localizedDescription)
                }
            }
        }
    }

    private func handleIncoming(_ message: URLSessionWebSocketTask.Message) {
        let raw: String
        switch message {
        case .string(let s): raw = s
        case .data(let d):   raw = String(data: d, encoding: .utf8) ?? ""
        @unknown default:    return
        }
        guard let data = raw.data(using: .utf8),
              let msg = try? JSONDecoder().decode(ProtocolMessage.self, from: data) else {
            log.warn("malformed inbound: \(raw.prefix(120))")
            return
        }
        log.debug("recv type=\(msg.type)")
        switch msg.type {
        case "bind.ack":
            state = .connected
            reconnectAttempt = 0
            lastError = nil
        case "bind.error":
            if let data = msg.data {
                let err = decode(data, ErrorPayload.self)
                lastError = err?.message
                state = .disconnected(reason: err?.message ?? "鉴权失败")
            }
        case "pong":
            handlePong()
        case "presence.phone_count":
            if let data = msg.data {
                let p = decode(data, PhoneCountPayload.self)
                self.phoneCount = p?.count ?? 0
                self.phoneNames = p?.names ?? []
            }
        case "force_disconnect":
            manualDisconnect = true
            state = .disconnected(reason: "Server 强制断开")
            stopHeartbeat()
        default:
            // Bubble up everything else for services to consume.
            inbound.send(msg)
        }
    }

    private func handleDisconnect(reason: String?) {
        stopHeartbeat()
        if manualDisconnect {
            state = .disconnected(reason: reason)
            return
        }
        // 防重入：URLSession receive error + WebSocketDelegate.didCloseWith
        // 经常成对触发同一次断开，必须去重避免 reconnect 风暴。
        if case .reconnecting = state {
            log.debug("disconnect ignored (already reconnecting): \(reason ?? "?")")
            return
        }
        let attempt = reconnectAttempt + 1
        let delay = backoffSeconds[min(reconnectAttempt, backoffSeconds.count - 1)]
        reconnectAttempt += 1
        state = .reconnecting(attempt: attempt)
        log.warn("disconnected (\(reason ?? "?")), reconnect in \(delay)s")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            guard let self = self, let cfg = self.currentConfig else { return }
            await MainActor.run {
                self.connect(config: cfg)
            }
        }
    }
}

// MARK: - Self-signed cert trust + TLS

extension WSClient: URLSessionDelegate, URLSessionWebSocketDelegate {
    public nonisolated func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                                       completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let trust = challenge.protectionSpace.serverTrust
        let trustSelfSigned = MainActor.assumeIsolated { self.currentConfig?.trustSelfSigned ?? false }
        if trustSelfSigned, let trust = trust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    public nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                                       didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            self.log.info("ws opened protocol=\(`protocol` ?? "-")")
        }
    }

    public nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                                       didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            self.log.info("ws closed code=\(closeCode.rawValue)")
            if self.intentionalCancel {
                self.intentionalCancel = false
                self.log.debug("ws close ignored (intentional cancel)")
                return
            }
            self.handleDisconnect(reason: "已关闭(\(closeCode.rawValue))")
        }
    }
}

// MARK: - Helpers

private func dictToAnyJSON(_ obj: Any) -> AnyJSON? {
    if let data = try? JSONSerialization.data(withJSONObject: obj, options: []) {
        return try? JSONDecoder().decode(AnyJSON.self, from: data)
    }
    return nil
}

func decode<T: Decodable>(_ json: AnyJSON, _ : T.Type) -> T? {
    guard let data = try? JSONEncoder().encode(json) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
}
