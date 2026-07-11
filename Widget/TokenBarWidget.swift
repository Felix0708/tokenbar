import WidgetKit
import SwiftUI

struct ProviderItem: Identifiable {
    let name: String
    let tint: Color
    let usage: ProviderUsage
    var id: String { name }
}

struct TokenEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct TokenProvider: TimelineProvider {
    func placeholder(in context: Context) -> TokenEntry {
        TokenEntry(date: Date(), snapshot: sampleSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (TokenEntry) -> Void) {
        let snap = SnapshotStore.load() ?? sampleSnapshot()
        completion(TokenEntry(date: Date(), snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenEntry>) -> Void) {
        let snap = SnapshotStore.load() ?? UsageSnapshot()
        let entry = TokenEntry(date: Date(), snapshot: snap)
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func sampleSnapshot() -> UsageSnapshot {
        var s = UsageSnapshot()
        s.claude.sessionPercent = 37
        s.claude.weekPercent = 52
        s.claude.todayTokens = 1_234_000
        s.claude.todayCost = 4.2
        s.codex.sessionPercent = 12
        s.codex.weekPercent = 30
        s.codex.todayTokens = 890_000
        s.codex.todayCost = 1.1
        return s
    }
}

func visibleProviders(_ s: UsageSnapshot) -> [ProviderItem] {
    let en = s.enabled ?? [:]
    var out: [ProviderItem] = []
    if en["claude"] ?? true {
        out.append(ProviderItem(name: "Claude", tint: .orange, usage: s.claude))
    }
    if en["codex"] ?? true {
        out.append(ProviderItem(name: "Codex", tint: .teal, usage: s.codex))
    }
    if en["gemini"] ?? true, let g = s.gemini, g.totalTokens > 0 {
        out.append(ProviderItem(name: "Gemini", tint: .blue, usage: g))
    }
    return out
}

struct TokenBarWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: TokenEntry

    var body: some View {
        let providers = visibleProviders(entry.snapshot)
        Group {
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(providers) { p in
                        CompactRow(item: p)
                        if p.id != providers.last?.id { Divider() }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(providers) { p in
                            DetailColumn(item: p)
                            if p.id != providers.last?.id { Divider() }
                        }
                    }
                    HStack {
                        Spacer()
                        Text("업데이트 \(entry.snapshot.updatedAt, style: .time)")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

/// 소형 위젯: 5시간 바 + 오늘 사용량
struct CompactRow: View {
    let item: ProviderItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Circle().fill(item.tint).frame(width: 7, height: 7)
                Text(item.name).font(.caption.bold())
                Spacer()
                Text(Fmt.percent(item.usage.sessionPercent))
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(WidgetColor.of(item.usage.sessionPercent, tint: item.tint))
            }
            ProgressView(value: min(max(item.usage.sessionPercent ?? 0, 0), 100), total: 100)
                .tint(WidgetColor.of(item.usage.sessionPercent, tint: item.tint))
                .scaleEffect(x: 1, y: 0.7, anchor: .center)
            Text("오늘 \(Fmt.tokens(item.usage.todayTokens))")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

/// 중형 위젯: 5시간·주간 바 + 오늘/누적 토큰·비용
struct DetailColumn: View {
    let item: ProviderItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(item.tint).frame(width: 7, height: 7)
                Text(item.name).font(.caption.bold())
                Spacer()
            }
            barRow(item.usage.sessionLabel ?? "5시간", item.usage.sessionPercent)
            if item.usage.weekLabel != nil || item.usage.weekPercent != nil {
                barRow(item.usage.weekLabel ?? "주간", item.usage.weekPercent)
            }
            Group {
                Text("오늘 \(Fmt.exact(item.usage.todayTokens)) · \(Fmt.cost(item.usage.todayCost))")
                Text("누적 \(Fmt.exact(item.usage.totalTokens))")
                Text("누적 \(Fmt.cost(item.usage.totalCost)) (추정)")
            }
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func barRow(_ label: String, _ percent: Double?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)
            ProgressView(value: min(max(percent ?? 0, 0), 100), total: 100)
                .tint(WidgetColor.of(percent, tint: item.tint))
                .scaleEffect(x: 1, y: 0.6, anchor: .center)
            Text(Fmt.percent(percent))
                .font(.system(size: 9).monospacedDigit().bold())
                .foregroundStyle(WidgetColor.of(percent, tint: item.tint))
                .frame(width: 30, alignment: .trailing)
        }
    }
}

enum WidgetColor {
    static func of(_ p: Double?, tint: Color) -> Color {
        guard let p = p else { return .gray }
        if p >= 90 { return .red }
        if p >= 70 { return .yellow }
        return tint
    }
}

struct TokenBarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TokenBarWidget", provider: TokenProvider()) { entry in
            TokenBarWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude · Codex · Gemini 토큰")
        .description("남은 사용 한도와 오늘 사용량을 보여줍니다.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct TokenBarWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenBarWidget()
    }
}
