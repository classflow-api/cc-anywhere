// DeviceManager.swift
// Bridges WSClient device.* messages to the UI's device list & QR flow.
// See 需求规格说明书 §3.1 M6.

import Foundation
import SwiftUI
import Combine

@MainActor
public final class DeviceManager: ObservableObject {
    private let log = AppLogger.shared.tagged("DeviceManager")
    @Published public private(set) var devices: [Device] = []

    /// Pending sub_token for the currently displayed QR. Set after the
    /// Server responds to device.create_subtoken.
    @Published public private(set) var pendingSubToken: String? = nil
    @Published public private(set) var pendingExpiresAt: Date? = nil

    private let ws: WSClient
    private let pref: PreferencesService
    private var cancellables = Set<AnyCancellable>()

    public init(ws: WSClient, pref: PreferencesService) {
        self.ws = ws
        self.pref = pref
        ws.inbound
            .filter { $0.type.hasPrefix("device.") }
            .sink { [weak self] msg in self?.handle(msg) }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    public func requestNewSubToken() async {
        log.info("requesting new sub_token")
        await ws.send(ProtocolMessage(type: "device.create_subtoken", data: nil))
    }

    public func requestDeviceList() async {
        await ws.send(ProtocolMessage(type: "device.list", data: nil))
    }

    public func revoke(_ device: Device) async {
        let payload = DeviceRevokeRequest(subTokenId: device.id)
        let json = try? JSONEncoder().encode(payload)
        let any = json.flatMap { try? JSONDecoder().decode(AnyJSON.self, from: $0) }
        await ws.send(ProtocolMessage(type: "device.revoke", data: any))
    }

    // MARK: - Inbound

    private func handle(_ msg: ProtocolMessage) {
        switch msg.type {
        case "device.subtoken.created":
            if let data = msg.data,
               case .object(let dict) = data,
               case .string(let token) = dict["sub_token"] ?? .null {
                pendingSubToken = token
                pendingExpiresAt = Date().addingTimeInterval(5 * 60)
                log.info("sub_token received: \(obfuscate(token))")
            }
        case "device.bound":
            if let data = msg.data, let p = decode(data, DeviceBoundPayload.self) {
                let dev = Device(
                    id: p.subTokenId,
                    deviceName: p.deviceName,
                    deviceModel: p.deviceModel,
                    osVersion: p.osVersion,
                    boundAt: Date(),
                    online: true
                )
                if let idx = devices.firstIndex(where: { $0.id == dev.id }) {
                    devices[idx] = dev
                } else {
                    devices.append(dev)
                }
                pendingSubToken = nil
            }
        case "device.list.response":
            if let data = msg.data, case .object(let dict) = data,
               case .array(let arr) = dict["devices"] ?? .null {
                devices = arr.compactMap { v -> Device? in
                    guard case .object(let d) = v else { return nil }
                    let id = d["id"]?.asString ?? UUID().uuidString
                    let name = d["device_name"]?.asString ?? "未命名设备"
                    let model = d["device_model"]?.asString
                    let osv = d["os_version"]?.asString
                    let bound: Date = (d["bound_at"]?.asString)
                        .flatMap { ISO8601DateFormatter().date(from: $0) }
                        ?? Date()
                    let online: Bool = {
                        if case .bool(let b) = d["online"] ?? .null { return b }
                        return false
                    }()
                    let latency: Int? = {
                        if case .number(let n) = d["latency_ms"] ?? .null { return Int(n) }
                        return nil
                    }()
                    return Device(id: id, deviceName: name, deviceModel: model,
                                  osVersion: osv, boundAt: bound,
                                  online: online, latencyMs: latency)
                }
            }
        case "device.revoked":
            if let data = msg.data, case .object(let dict) = data,
               let id = dict["sub_token_id"]?.asString {
                devices.removeAll { $0.id == id }
            }
        default:
            break
        }
    }

    /// Build the JSON payload encoded inside a binding QR code.
    public func qrPayload() -> String? {
        guard let token = pendingSubToken else { return nil }
        let cfg = pref.serverConfig
        let dict: [String: Any] = [
            "v": 1,
            "server": cfg.server,
            "port": cfg.port,
            "sub_token": token
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
