// QRDisplaySheet.swift
// Reusable modal sheet showing the QR for new device binding. Currently
// DevicesPane embeds the QR view in-line; this file is kept for future use
// when we want a modal preview, e.g. when triggered from the sidebar.

import SwiftUI

struct QRDisplaySheet: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var preferences: PreferencesService
    @Binding var isPresented: Bool

    var body: some View {
        let palette = themeManager.palette
        VStack(spacing: 12) {
            HStack {
                Text("绑定新设备")
                    .font(AppFont.ui(size: 16, weight: .bold))
                    .foregroundColor(palette.text)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .foregroundColor(palette.textMuted)
                }.buttonStyle(.plain)
            }
            QRView(payload: deviceManager.qrPayload(), palette: palette, accent: palette.accent)
                .frame(width: 280, height: 280)
            Text("打开手机端 cc-anywhere 扫码即可绑定")
                .font(AppFont.ui(size: 11.5))
                .foregroundColor(palette.textMuted)
        }
        .padding(20)
        .background(palette.bgElev)
        .frame(width: 340)
        .onAppear {
            if deviceManager.pendingSubToken == nil {
                Task { await deviceManager.requestNewSubToken() }
            }
        }
    }
}
