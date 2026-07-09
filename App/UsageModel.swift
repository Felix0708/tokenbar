import Foundation
import WidgetKit

@MainActor
final class UsageModel: ObservableObject {
    @Published var snapshot: UsageSnapshot = SnapshotStore.load() ?? UsageSnapshot()
    @Published var refreshing = false

    private let claudeParser = ClaudeLogParser()
    private let codexParser = CodexLogParser()
    private let oauth = ClaudeOAuthClient()
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var menuTitle: String {
        let c = snapshot.claude.sessionPercent.map { String(format: "%.0f", $0) } ?? "–"
        let x = snapshot.codex.sessionPercent.map { String(format: "%.0f", $0) } ?? "–"
        return "C\(c) X\(x)"
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let claudeParser = self.claudeParser
        let codexParser = self.codexParser
        let oauth = self.oauth

        Task.detached(priority: .utility) {
            var claude = claudeParser.collect()
            let codex = codexParser.collect()

            if let limits = await oauth.fetchLimits() {
                claude.sessionPercent = limits.fiveHour
                claude.sessionResetAt = limits.fiveHourReset
                claude.weekPercent = limits.sevenDay
                claude.weekResetAt = limits.sevenDayReset
            }
            if claude.note == nil { claude.note = oauth.statusNote }

            var snap = UsageSnapshot()
            snap.updatedAt = Date()
            snap.claude = claude
            snap.codex = codex
            SnapshotStore.save(snap)

            await MainActor.run { [snap] in
                self.snapshot = snap
                self.refreshing = false
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
