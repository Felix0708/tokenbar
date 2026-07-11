import SwiftUI
import ServiceManagement

struct MenuContentView: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.showClaude {
                ProviderSection(name: "Claude", tint: .orange, usage: model.snapshot.claude)
                Divider()
            }
            if model.showCodex {
                ProviderSection(name: "Codex", tint: .teal, usage: model.snapshot.codex)
                Divider()
            }
            if model.showGemini {
                ProviderSection(name: "Gemini", tint: .blue, usage: model.snapshot.gemini ?? ProviderUsage())
                Divider()
            }

            // 표시할 서비스 선택
            HStack(spacing: 10) {
                Text("표시")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Toggle("Claude", isOn: $model.showClaude).toggleStyle(.checkbox).font(.caption)
                Toggle("Codex", isOn: $model.showCodex).toggleStyle(.checkbox).font(.caption)
                Toggle("Gemini", isOn: $model.showGemini).toggleStyle(.checkbox).font(.caption)
                Spacer()
            }

            // Gemini 일일 한도 플랜 선택
            if model.showGemini {
                HStack(spacing: 6) {
                    Text("Gemini 일일 한도")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $model.geminiDailyLimit) {
                        Text("250 (무료 API키)").tag(250)
                        Text("1,000 (무료 계정)").tag(1000)
                        Text("1,500 (AI Pro)").tag(1500)
                        Text("2,000 (AI Ultra)").tag(2000)
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .labelsHidden()
                    .frame(width: 160)
                    Spacer()
                }
            }

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
        .frame(width: 340)
    }
}

struct ProviderSection: View {
    let name: String
    let tint: Color
    let usage: ProviderUsage
    @State private var showModels = false

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

            LimitRow(label: usage.sessionLabel ?? "5시간", percent: usage.sessionPercent, resetAt: usage.sessionResetAt, tint: tint)
            if usage.weekLabel != nil || usage.weekPercent != nil {
                LimitRow(label: usage.weekLabel ?? "주간", percent: usage.weekPercent, resetAt: usage.weekResetAt, tint: tint)
            }
            if let extras = usage.extraLimits {
                ForEach(extras) { e in
                    LimitRow(label: e.label, percent: e.percent, resetAt: e.resetAt, tint: tint)
                }
            }

            // 리셋까지 남은 시간
            if let s = resetSummary(usage) {
                Text(s)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Text("누적 \(Fmt.exact(usage.totalTokens)) 토큰")
                Spacer()
                Text("누적 \(Fmt.cost(usage.totalCost)) (추정)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // 모델별 분해
            if let models = usage.models, !models.isEmpty {
                Button {
                    showModels.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showModels ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8))
                        Text("모델별 보기")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if showModels {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(models.prefix(5))) { m in
                            HStack {
                                Text(m.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                                Spacer()
                                Text("오늘 \(Fmt.tokens(m.todayTokens)) · 누적 \(Fmt.tokens(m.totalTokens)) · \(Fmt.cost(m.totalCost))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.leading, 12)
                }
            }

            if let note = usage.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// "5시간 46분 뒤 리셋 · 주간 3일 뒤 리셋" 형태 요약
    private func resetSummary(_ u: ProviderUsage) -> String? {
        var parts: [String] = []
        if let r = Fmt.rel(u.sessionResetAt) {
            parts.append("\(u.sessionLabel ?? "5시간") \(r)")
        }
        if let r = Fmt.rel(u.weekResetAt) {
            parts.append("\(u.weekLabel ?? "주간") \(r)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
