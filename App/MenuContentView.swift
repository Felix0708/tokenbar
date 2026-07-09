import SwiftUI
import ServiceManagement

struct MenuContentView: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProviderSection(name: "Claude", tint: .orange, usage: model.snapshot.claude)
            Divider()
            ProviderSection(name: "Codex", tint: .teal, usage: model.snapshot.codex)
            Divider()
            HStack(spacing: 10) {
                LaunchAtLoginToggle()
                Spacer()
                Text("업데이트 \(model.snapshot.updatedAt, style: .time)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button {
                    model.refresh()
                } label: {
                    if model.refreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .help("새로고침")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help("종료")
            }
        }
        .padding(14)
        .frame(width: 330)
    }
}

struct ProviderSection: View {
    let name: String
    let tint: Color
    let usage: ProviderUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(name).font(.headline)
                Spacer()
                Text("오늘 \(Fmt.exact(usage.todayTokens)) 토큰 · \(Fmt.cost(usage.todayCost))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LimitRow(label: "5시간", percent: usage.sessionPercent, resetAt: usage.sessionResetAt, tint: tint)
            LimitRow(label: "주간", percent: usage.weekPercent, resetAt: usage.weekResetAt, tint: tint)

            HStack {
                Text("누적 \(Fmt.exact(usage.totalTokens)) 토큰")
                Spacer()
                Text("누적 \(Fmt.cost(usage.totalCost)) (추정)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let note = usage.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct LimitRow: View {
    let label: String
    let percent: Double?
    let resetAt: Date?
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 34, alignment: .leading)
            ProgressView(value: min(max(percent ?? 0, 0), 100), total: 100)
                .tint(barColor)
            Text(Fmt.percent(percent))
                .font(.caption.monospacedDigit())
                .frame(width: 38, alignment: .trailing)
        }
        .help(Fmt.resetTime(resetAt))
    }

    private var barColor: Color {
        guard let p = percent else { return .gray }
        if p >= 90 { return .red }
        if p >= 70 { return .yellow }
        return tint
    }
}

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("로그인 시 시작", isOn: Binding(
            get: { enabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {}
                enabled = SMAppService.mainApp.status == .enabled
            }
        ))
        .toggleStyle(.checkbox)
        .font(.caption)
    }
}
