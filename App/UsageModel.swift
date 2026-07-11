import Foundation
import WidgetKit

@MainActor
final class UsageModel: ObservableObject {
    @Published var snapshot: UsageSnapshot = SnapshotStore.load() ?? UsageSnapshot()
    @Published var refreshing = false

    @Published var showClaude: Bool = UserDefaults.standard.object(forKey: "show.claude") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showClaude, forKey: "show.claude"); pushEnabledFlags() }
    }
    @Published var showCodex: Bool = UserDefaults.standard.object(forKey: "show.codex") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showCodex, forKey: "show.codex"); pushEnabledFlags() }
    }
    @Published var showGemini: Bool = UserDefaults.standard.object(forKey: "show.gemini") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showGemini, forKey: "show.gemini"); pushEnabledFlags() }
    }
    /// Gemini 플랜별 일일 요청 한도 (무료 1000 / AI Pro 1500 / Ultra 2000 / 무료 API키 250)
    @Published var geminiDailyLimit: Int = UserDefaults.standard.object(forKey: "gemini.dailyLimit") as? Int ?? 1000 {
        didSet {
            UserDefaults.standard.set(geminiDailyLimit, forKey: "gemini.dailyLimit")
            Task { @MainActor in self.refresh() }
        }
    }

    private let claudeParser = ClaudeLogParser()
    private let codexParser = CodexLogParser()
    private let geminiParser = GeminiLogParser()
    private let oauth = ClaudeOAuthClient()
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private var enabledFlags: [String: Bool] {
        ["claude": showClaude, "codex": showCodex, "gemini": showGemini]
    }

    /// 토글 변경 즉시 위젯에 반영
    private func pushEnabledFlags() {
        var snap = snapshot
        snap.enabled = enabledFlags
        snapshot = snap
        SnapshotStore.save(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let claudeParser = self.claudeParser
        let codexParser = self.codexParser
        let geminiParser = self.geminiParser
        let oauth = self.oauth
        let prevClaude = snapshot.claude
        let flags = enabledFlags
        let geminiLimit = geminiDailyLimit

        Task.detached(priority: .utility) {
            var claude = claudeParser.collect()
            let codex = codexParser.collect()
            let gemini = geminiParser.collect(dailyLimit: geminiLimit)

            if let limits = await oauth.fetchLimits() {
                claude.sessionPercent = limits.fiveHour
                claude.sessionResetAt = limits.fiveHourReset
                claude.weekPercent = limits.sevenDay
                claude.weekResetAt = limits.sevenDayReset
                claude.extraLimits = limits.extras.isEmpty ? nil : limits.extras
            } else {
                // 조회 실패(429 등) 시 마지막으로 성공한 값을 유지
                claude.sessionPercent = prevClaude.sessionPercent
                claude.sessionResetAt = prevClaude.sessionResetAt
                claude.weekPercent = prevClaude.weekPercent
                claude.weekResetAt = prevClaude.weekResetAt
                claude.extraLimits = prevClaude.extraLimits
            }
            claude.weekLabel = "주간"
            if claude.note == nil { claude.note = oauth.statusNote }

            var snap = UsageSnapshot()
            snap.updatedAt = Date()
            snap.claude = claude
            snap.codex = codex
            snap.gemini = gemini
            snap.enabled = flags
            SnapshotStore.save(snap)

            await MainActor.run { [snap] in
                self.snapshot = snap
                self.refreshing = false
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
