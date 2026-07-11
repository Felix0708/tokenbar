import SwiftUI
import ServiceManagement
import AppKit

struct MenuContentView: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.showClaude {
                ProviderSection(name: "Claude", tint: .orange, usage: model.snapshot.claude, onClaudeLogin: model.refresh)
                Divider()
            }
            if model.showCodex {
                ProviderSection(name: "Codex", tint: .teal, usage: model.snapshot.codex, onClaudeLogin: {})
                Divider()
            }
            if model.showGemini {
                ProviderSection(name: "Gemini", tint: .blue, usage: model.snapshot.gemini ?? ProviderUsage(), onClaudeLogin: {})
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

            // Gemini 플랜이 실제 quota 정보로 확인되면 하나만 표시하고, 아니면 수동 한도를 제공
            if model.showGemini, let gemini = model.snapshot.gemini,
               gemini.planDetected == true, let plan = gemini.planLabel {
                HStack(spacing: 6) {
                    Text("Gemini 플랜")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(plan + (gemini.dailyLimit.map { " · \($0)/일" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Spacer()
                }
            } else if model.showGemini {
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
    let onClaudeLogin: () -> Void
    @State private var showModels = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(name).font(.headline)
                if let plan = usage.planLabel {
                    Text(plan)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.12), in: Capsule())
                }
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
                        Text("모델별 보기 (\(models.count))")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if showModels {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(models) { m in
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
                        .padding(.trailing, 2)
                    }
                    .frame(height: min(max(CGFloat(models.count) * 18, 18), 180))
                    .padding(.leading, 12)
                }
            }

            if let note = usage.note {
                HStack(spacing: 6) {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if name == "Claude", note.contains("claude auth login") {
                        Button("로그인") {
                            ClaudeLoginLauncher.open()
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 20_000_000_000)
                                onClaudeLogin()
                            }
                        }
                        .font(.caption2)
                        .buttonStyle(.borderless)
                    }
                }
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

enum ClaudeLoginLauncher {
    static func open() {
        let command = "claude auth login"
        let source = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """

        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            script.executeAndReturnError(&error)
            if error == nil { return }
        }

        // Terminal 자동 제어가 막힌 경우에도 한 번의 붙여넣기로 진행할 수 있게 함.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
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
