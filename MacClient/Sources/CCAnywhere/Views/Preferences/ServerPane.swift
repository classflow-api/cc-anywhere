// ServerPane.swift
// Mirrors design's preferences > Server connection panel.

import SwiftUI

struct ServerPane: View {
    @EnvironmentObject var preferences: PreferencesService
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var ws: WSClient

    @State private var tokenVisible: Bool = false
    @State private var testResult: TestResult? = nil
    @State private var testing: Bool = false

    enum TestResult { case ok, failed(String) }

    var body: some View {
        let palette = themeManager.palette
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Server 连接").font(AppFont.ui(size: 22, weight: .bold))
                        .foregroundColor(palette.text)
                    Text("配置自建 VPS 的中转服务器地址、端口与主 Token")
                        .font(AppFont.ui(size: 12.5))
                        .foregroundColor(palette.textMuted)
                }

                GlassCard(palette: palette) {
                    VStack(alignment: .leading, spacing: 12) {
                        labeledField("Server 地址", palette: palette) {
                            TextField("cc.example.com", text: $preferences.serverConfig.server)
                                .textFieldStyle(.roundedBorder)
                        }
                        labeledField("端口", palette: palette) {
                            TextField("8443",
                                      value: $preferences.serverConfig.port,
                                      formatter: NumberFormatter())
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }
                        labeledField("主 Token", palette: palette) {
                            HStack(spacing: 6) {
                                Group {
                                    if tokenVisible {
                                        TextField("master_token",
                                                  text: $preferences.serverConfig.masterToken)
                                    } else {
                                        SecureField("master_token",
                                                    text: $preferences.serverConfig.masterToken)
                                    }
                                }
                                .textFieldStyle(.roundedBorder)
                                Button {
                                    tokenVisible.toggle()
                                } label: {
                                    Image(systemName: tokenVisible ? "eye.slash" : "eye")
                                        .foregroundColor(palette.textMuted)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Toggle("信任自签证书", isOn: $preferences.serverConfig.trustSelfSigned)
                            .toggleStyle(.switch)
                            .foregroundColor(palette.text)
                            .font(AppFont.ui(size: 12.5))
                    }
                }

                HStack(spacing: 12) {
                    Button(action: testConnection) {
                        HStack(spacing: 6) {
                            if testing {
                                ProgressView().controlSize(.small)
                            }
                            Text(testing ? "测试中…" : "测试连接")
                                .font(AppFont.ui(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(palette.bgInset)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.line))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button(action: saveAndReconnect) {
                        Text("保存并重连")
                            .font(AppFont.ui(size: 12, weight: .semibold))
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(palette.accent)
                            .foregroundColor(palette.accentFg)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    statusIndicator(palette: palette)
                }

                if let r = testResult {
                    switch r {
                    case .ok:
                        statusBanner("连接成功", icon: "checkmark.circle.fill",
                                     color: palette.success, palette: palette)
                    case .failed(let msg):
                        statusBanner(msg, icon: "exclamationmark.triangle.fill",
                                     color: palette.danger, palette: palette)
                    }
                }
            }
            .padding(28)
        }
    }

    private func labeledField<Content: View>(_ label: String, palette: ColorPalette,
                                             @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(AppFont.ui(size: 12, weight: .medium))
                .foregroundColor(palette.text).frame(width: 100, alignment: .trailing)
            content()
        }
    }

    private func statusIndicator(palette: ColorPalette) -> some View {
        HStack(spacing: 6) {
            PulseDot(color: stateColor(palette), size: 6, pulse: false)
            Text(ws.state.displayLabel)
                .font(AppFont.ui(size: 11.5))
                .foregroundColor(palette.textMuted)
        }
    }

    private func stateColor(_ palette: ColorPalette) -> Color {
        switch ws.state {
        case .connected: return palette.success
        case .connecting, .reconnecting: return palette.warn
        case .disconnected: return palette.danger
        }
    }

    private func statusBanner(_ text: String, icon: String, color: Color, palette: ColorPalette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(color)
            Text(text).foregroundColor(palette.text).font(AppFont.ui(size: 12))
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.30)))
        )
    }

    private func testConnection() {
        guard preferences.serverConfig.isUsable else {
            testResult = .failed("配置不完整：请填写地址 / 端口 / Token")
            return
        }
        testing = true
        testResult = nil
        ws.connect(config: preferences.serverConfig)
        // Allow up to 10 seconds.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            testing = false
            switch ws.state {
            case .connected: testResult = .ok
            case .disconnected(let r): testResult = .failed(r ?? "未连接")
            case .connecting, .reconnecting: testResult = .failed("连接超时")
            }
        }
        // also short-circuit on success
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if case .connected = ws.state {
                testing = false
                testResult = .ok
            }
        }
    }

    private func saveAndReconnect() {
        // PreferencesService persists on didSet; we just trigger a reconnect.
        ws.disconnect()
        ws.connect(config: preferences.serverConfig)
    }
}
