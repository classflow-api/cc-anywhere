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

            // Server health card with mock sparkline
            serverHealthCard(palette: palette)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                PulseDot(color: palette.success, size: 6)
                Text("Server 健康")
                    .font(AppFont.ui(size: 11, weight: .semibold))
                    .foregroundColor(palette.text)
                Spacer()
                Text("38ms")
                    .font(AppFont.mono(size: 10))
                    .foregroundColor(palette.textFaint)
            }
            Sparkline(palette: palette)
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

/// Tiny faux sparkline (Server latency placeholder).
private struct Sparkline: View {
    let palette: ColorPalette
    private let points: [Double] = [22, 14, 18, 8, 12, 4, 10, 7, 12, 5, 9]

    var body: some View {
        GeometryReader { geo in
            let step = geo.size.width / CGFloat(points.count - 1)
            let path = Path { p in
                for (i, v) in points.enumerated() {
                    let x = step * CGFloat(i)
                    let y = CGFloat(v)
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            let fill = Path { p in
                p.move(to: CGPoint(x: 0, y: geo.size.height))
                for (i, v) in points.enumerated() {
                    let x = step * CGFloat(i)
                    let y = CGFloat(v)
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
