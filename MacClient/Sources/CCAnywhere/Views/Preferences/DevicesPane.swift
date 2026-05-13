// DevicesPane.swift
// Mirrors design's preferences > Devices pane:
//   - left: list of bound phones
//   - right: QR card with countdown

import SwiftUI
import AppKit

struct DevicesPane: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var preferences: PreferencesService

    @State private var showQR = false

    var body: some View {
        let palette = themeManager.palette
        HStack(alignment: .top, spacing: 24) {
            // Devices list
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("设备管理").font(AppFont.ui(size: 22, weight: .bold))
                        .foregroundColor(palette.text)
                    Text("管理已绑定的手机端 · 每个 sub_token 可独立撤销")
                        .font(AppFont.ui(size: 12.5))
                        .foregroundColor(palette.textMuted)
                }

                HStack {
                    Button(action: refresh) {
                        Label("刷新", systemImage: "arrow.clockwise")
                            .font(AppFont.ui(size: 12, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(palette.bgInset)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.line))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain).foregroundColor(palette.text)
                    Spacer()
                    Button(action: { showQR = true; Task { await deviceManager.requestNewSubToken() } }) {
                        Label("生成绑定 QR", systemImage: "qrcode")
                            .font(AppFont.ui(size: 12, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(palette.accent)
                            .foregroundColor(palette.accentFg)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)
                }

                ScrollView {
                    VStack(spacing: 8) {
                        if deviceManager.devices.isEmpty {
                            Text("尚未绑定设备。点击右上「生成绑定 QR」并用手机端扫码。")
                                .font(AppFont.ui(size: 12))
                                .foregroundColor(palette.textMuted)
                                .frame(maxWidth: .infinity, minHeight: 80)
                        } else {
                            ForEach(deviceManager.devices) { d in
                                DeviceRow(device: d, palette: palette,
                                          onRevoke: { confirmRevoke(d) })
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // QR sidebar
            VStack {
                GlassCard(padding: 20, glow: true, palette: palette) {
                    VStack(spacing: 12) {
                        SectionLabel("新设备绑定", palette: palette)
                        Text("扫一扫即可绑定")
                            .font(AppFont.ui(size: 14, weight: .semibold))
                            .foregroundColor(palette.text)
                        QRView(payload: deviceManager.qrPayload(),
                               palette: palette,
                               accent: palette.accent)
                            .frame(width: 220, height: 220)
                        countdown(palette: palette)
                        Text("wss://\(preferences.serverConfig.server):\(preferences.serverConfig.port)")
                            .font(AppFont.mono(size: 10.5))
                            .foregroundColor(palette.textFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 7).fill(palette.bgInset)
                            )
                    }
                }
                Spacer()
            }
            .frame(width: 290)
        }
        .padding(28)
        .onAppear { Task { await deviceManager.requestDeviceList() } }
    }

    private func refresh() {
        Task { await deviceManager.requestDeviceList() }
    }

    private func confirmRevoke(_ d: Device) {
        let alert = NSAlert()
        alert.messageText = "撤销 \(d.deviceName)"
        alert.informativeText = "撤销后该设备将立即下线，且无法再连接。"
        alert.addButton(withTitle: "撤销")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await deviceManager.revoke(d) }
        }
    }

    private func countdown(palette: ColorPalette) -> some View {
        let remaining = deviceManager.pendingExpiresAt.map { max(0, $0.timeIntervalSinceNow) } ?? 0
        let mm = Int(remaining) / 60
        let ss = Int(remaining) % 60
        let label = String(format: "%02d:%02d", mm, ss)
        return Text("有效期 ")
            .foregroundColor(palette.textMuted)
            .font(AppFont.ui(size: 11.5))
        +
        Text(label).foregroundColor(palette.accent)
            .font(AppFont.mono(size: 11.5, weight: .bold))
    }
}

// MARK: - One row

private struct DeviceRow: View {
    let device: Device
    let palette: ColorPalette
    let onRevoke: () -> Void

    var body: some View {
        GlassCard(padding: 14, palette: palette) {
            HStack(spacing: 14) {
                // tiny phone glyph
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: [palette.accent, Color(hex: 0x9A7BF2)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 42, height: 60)
                        .shadow(color: palette.accent.opacity(0.4), radius: 6, y: 3)
                    Capsule()
                        .fill(.white.opacity(0.4))
                        .frame(width: 14, height: 2)
                        .offset(y: -25)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.black.opacity(0.15))
                        .frame(width: 32, height: 42)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(device.deviceName)
                            .font(AppFont.ui(size: 14, weight: .semibold))
                            .foregroundColor(palette.text)
                        if device.online {
                            StatusPill(palette: palette, dotColor: palette.success, accent: true) {
                                Text("在线 · \(device.latencyMs.map { "\($0)ms" } ?? "")")
                            }
                        } else {
                            StatusPill(palette: palette, dotColor: palette.textFaint) {
                                Text("离线 · \(device.lastSeenLabel)")
                            }
                        }
                    }
                    Text("\(device.deviceModel ?? "") · 绑定于 \(formatDate(device.boundAt)) · \(obfuscate(device.id))")
                        .font(AppFont.mono(size: 11))
                        .foregroundColor(palette.textMuted)
                }
                Spacer()
                Button(action: onRevoke) {
                    Text("撤销")
                        .font(AppFont.ui(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(palette.danger.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.danger.opacity(0.30)))
                        .foregroundColor(palette.danger)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

// MARK: - QR rendering via CoreImage

import CoreImage.CIFilterBuiltins

struct QRView: View {
    let payload: String?
    let palette: ColorPalette
    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: accent.opacity(0.4), radius: 20, y: 8)
            if let image = makeImage() {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(14)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "qrcode")
                        .resizable().frame(width: 120, height: 120)
                        .foregroundColor(.black.opacity(0.15))
                    Text("生成中…")
                        .font(AppFont.ui(size: 11))
                        .foregroundColor(.black.opacity(0.4))
                }
            }
            // Center accent badge
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [accent, Color(hex: 0x9A7BF2)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 40, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white).frame(width: 14, height: 14)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 4)
                )
        }
    }

    private func makeImage() -> NSImage? {
        guard let payload = payload, let data = payload.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(transformed, from: transformed.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: 220, height: 220))
    }
}
