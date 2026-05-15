// ActivityPanelView.swift
// Mirrors MacActivityPanel: small list of recent events plus a Server-health
// sparkline.

import SwiftUI
import Combine

@MainActor
final class ActivityFeed: ObservableObject {
    struct Event: Identifiable {
        enum Kind { case assistant, user, tool, phone }
        let id = UUID()
        let kind: Kind
        let title: String
        let detail: String
        let time: Date
        let fromPhone: Bool
    }

    @Published private(set) var events: [Event] = []
    private var cancellables = Set<AnyCancellable>()
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    init(ws: WSClient) {
        ws.inbound
            .sink { [weak self] msg in self?.observe(msg) }
            .store(in: &cancellables)
    }

    private func observe(_ msg: ProtocolMessage) {
        switch msg.type {
        case "input.text":
            if let data = msg.data, let p = decode(data, InputTextPayload.self) {
                push(.init(kind: .user, title: "Phone",
                           detail: p.text.prefix(80) + "",
                           time: Date(), fromPhone: true))
            }
        case "tool_use.approve":
            if let data = msg.data, let p = decode(data, ToolUseApprovePayload.self) {
                push(.init(kind: .phone, title: "Phone",
                           detail: "tool_use \(p.action)",
                           time: Date(), fromPhone: true))
            }
        default: break
        }
    }

    private func push(_ e: Event) {
        events.insert(e, at: 0)
        if events.count > 50 { events.removeLast() }
    }

    func timeLabel(_ d: Date) -> String { formatter.string(from: d) }
}

struct ActivityPanelView: View {
    @EnvironmentObject var ws: WSClient
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var feed: ActivityFeed

    init(ws: WSClient) {
        _feed = StateObject(wrappedValue: ActivityFeed(ws: ws))
    }

    var body: some View {
        let palette = themeManager.palette
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("实时事件流", palette: palette)
                Text("当前 Tab · \(ws.phoneCount) 设备在线")
                    .font(AppFont.ui(size: 11.5))
                    .foregroundColor(palette.textMuted)
            }

            HStack(spacing: 6) {
                ForEach(["全部", "Tool", "Phone"], id: \.self) { l in
                    Text(l)
                        .font(AppFont.ui(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(l == "全部" ? palette.accent : palette.bgInset)
                        )
                        .foregroundColor(l == "全部" ? palette.accentFg : palette.textMuted)
                }
                Spacer()
                Image(systemName: "pin")
                    .foregroundColor(palette.textFaint)
                    .font(.system(size: 11))
            }

            // events
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if feed.events.isEmpty {
                        Text("等待事件…")
                            .font(AppFont.ui(size: 11))
                            .foregroundColor(palette.textFaint)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    } else {
                        ForEach(feed.events) { e in
                            EventRow(event: e, feed: feed, palette: palette)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            // Server 健康卡已移到左侧 sidebar
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(width: 244, alignment: .topLeading)
        .background(
            LinearGradient(colors: [.clear, palette.bgInset],
                           startPoint: .top, endPoint: .bottom)
        )
        .overlay(
            Rectangle().fill(palette.line).frame(width: 1),
            alignment: .leading
        )
    }

    private func serverHealthCard(palette: ColorPalette) -> some View {
        let history = ws.latencyHistoryMs
        let latest = history.last
        let isConnected: Bool = {
            if case .connected = ws.state { return true } else { return false }
        }()
        let dotColor: Color = isConnected ? palette.success
            : (history.isEmpty ? palette.textFaint : palette.warn)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                PulseDot(color: dotColor, size: 6, pulse: isConnected)
                Text("Server 健康")
                    .font(AppFont.ui(size: 11, weight: .semibold))
                    .foregroundColor(palette.text)
                Spacer()
                Text(latest.map { "\($0)ms" } ?? "—")
                    .font(AppFont.mono(size: 10))
                    .foregroundColor(palette.textFaint)
            }
            Sparkline(palette: palette, pointsMs: history)
                .frame(height: 28)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(palette.bgElev)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.line, lineWidth: 1))
        )
    }
}

private struct EventRow: View {
    let event: ActivityFeed.Event
    let feed: ActivityFeed
    let palette: ColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(eventColor)
                    .frame(width: 5, height: 5)
                Text(event.title.uppercased())
                    .font(AppFont.ui(size: 10.5, weight: .bold))
                    .tracking(0.2)
                    .foregroundColor(palette.text)
                if event.fromPhone {
                    Text("PHONE")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color(hex: 0xB46BE0).opacity(0.15)))
                        .foregroundColor(Color(hex: 0xB46BE0))
                }
                Spacer()
                Text(feed.timeLabel(event.time))
                    .font(AppFont.mono(size: 9.5))
                    .foregroundColor(palette.textFaint)
            }
            Text(event.detail)
                .font(AppFont.ui(size: 11))
                .foregroundColor(palette.textMuted)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .overlay(
            Rectangle().fill(palette.line).frame(height: 1).opacity(0.5),
            alignment: .bottom
        )
    }

    private var eventColor: Color {
        switch event.kind {
        case .assistant: return palette.accent
        case .tool: return palette.warn
        case .user: return palette.success
        case .phone: return Color(hex: 0xB46BE0)
        }
    }
}

/// 真实心跳延迟 sparkline。从 WSClient.latencyHistoryMs 拉数据。
struct Sparkline: View {
    let palette: ColorPalette
    let pointsMs: [Int]
    var minPoints: Int = 6  // 不足时填底，避免空 path 报错

    var body: some View {
        GeometryReader { geo in
            // 兜底空数据
            let raw = pointsMs.isEmpty ? Array(repeating: 0, count: minPoints) : pointsMs
            let values = raw.map { Double($0) }
            // 归一化：min..max 映射到 canvas（保留 6pt 上下边距）
            let lo = values.min() ?? 0
            let hi = max(values.max() ?? 1, lo + 1)
            let topPad: CGFloat = 4
            let botPad: CGFloat = 4
            let h = max(geo.size.height - topPad - botPad, 1)
            let n = values.count
            let step = n > 1 ? geo.size.width / CGFloat(n - 1) : 0

            let path = Path { p in
                for (i, v) in values.enumerated() {
                    let x = step * CGFloat(i)
                    let norm = (v - lo) / (hi - lo)
                    let y = topPad + (1 - CGFloat(norm)) * h
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            let fill = Path { p in
                p.move(to: CGPoint(x: 0, y: geo.size.height))
                for (i, v) in values.enumerated() {
                    let x = step * CGFloat(i)
                    let norm = (v - lo) / (hi - lo)
                    let y = topPad + (1 - CGFloat(norm)) * h
                    p.addLine(to: CGPoint(x: x, y: y))
                }
                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                p.closeSubpath()
            }
            fill.fill(LinearGradient(
                colors: [palette.accent.opacity(0.45), palette.accent.opacity(0)],
                startPoint: .top, endPoint: .bottom
            ))
            path.stroke(palette.accent, lineWidth: 1.5)
        }
    }
}
