import Foundation
import Security

struct ClaudeLimits: Codable {
    var fiveHour: Double?
    var fiveHourReset: Date?
    var sevenDay: Double?
    var sevenDayReset: Date?
    /// 모델별 주간 창 등 추가 한도 (예: "주간(Sonnet)")
    var extras: [ExtraLimit] = []
    var fetchedAt: Date? = nil
}

/// Anthropic OAuth usage API로 남은 한도(5시간/주간/모델별 %)를 조회.
/// 토큰은 macOS 키체인("Claude Code-credentials") 또는 ~/.claude/.credentials.json 에서 읽음.
/// 응답은 15분 캐시, 429 발생 시 Retry-After(최소 30분) 백오프.
final class ClaudeOAuthClient {
    private var cached: ClaudeLimits?
    private var lastFetch: Date?
    private var backoffUntil: Date?
    private(set) var statusNote: String?
    private var cachedPlanLabel: String?

    private let cacheInterval: TimeInterval = 900
    private let minBackoff: TimeInterval = 1800
    private let limitsCacheURL = SnapshotStore.supportDir.appendingPathComponent("claude-limits-v1.json")
    private let userAgent = "claude-code/2.1.206"

    init() {
        if let data = try? Data(contentsOf: limitsCacheURL),
           let limits = try? JSONDecoder().decode(ClaudeLimits.self, from: data) {
            cached = limits
        }
    }

    func fetchLimits() async -> ClaudeLimits? {
        if let last = lastFetch, Date().timeIntervalSince(last) < cacheInterval, cached != nil {
            return cached
        }
        if let until = backoffUntil, Date() < until {
            return cached
        }
        guard let token = readAccessToken() else {
            statusNote = staleNote("Claude Code 로그인 정보 없음 — 터미널에서 claude auth login 실행")
            return cached
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            if status == 429 {
                var wait = minBackoff
                if let ra = http?.value(forHTTPHeaderField: "Retry-After"), let s = Double(ra), s > 0 {
                    wait = max(s, minBackoff)
                }
                backoffUntil = Date().addingTimeInterval(wait)
                let mins = Int(wait / 60)
                statusNote = staleNote("Anthropic이 조회 차단 중 — \(mins)분 뒤 재시도")
                return cached
            }
            if status == 401 || status == 403 {
                statusNote = staleNote("토큰 만료 — 터미널에서 claude 한 번 실행하면 갱신됨")
                return cached
            }
            guard status == 200,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                statusNote = staleNote("한도 API 응답 오류 (\(status))")
                return cached
            }

            var limits = ClaudeLimits()
            if let five = obj["five_hour"] as? [String: Any] {
                limits.fiveHour = numVal(five["utilization"])
                limits.fiveHourReset = dateVal(five["resets_at"])
            }
            if let seven = obj["seven_day"] as? [String: Any] {
                limits.sevenDay = numVal(seven["utilization"])
                limits.sevenDayReset = dateVal(seven["resets_at"])
            }
            // 모델별 주간 창: "seven_day_sonnet", "seven_day_opus" 등
            for (key, value) in obj {
                guard key.hasPrefix("seven_day_"),
                      let dict = value as? [String: Any],
                      let pct = numVal(dict["utilization"]) else { continue }
                let model = String(key.dropFirst("seven_day_".count)).capitalized
                limits.extras.append(ExtraLimit(
                    label: "주간(\(model))",
                    percent: pct,
                    resetAt: dateVal(dict["resets_at"])
                ))
            }
            limits.extras.sort { $0.label < $1.label }
            limits.fetchedAt = Date()
            cached = limits
            lastFetch = Date()
            if let data = try? JSONEncoder().encode(limits) {
                try? data.write(to: limitsCacheURL, options: .atomic)
            }
            statusNote = nil
            return limits
        } catch {
            statusNote = staleNote("네트워크 오류")
            return cached
        }
    }

    /// Claude CLI가 확인한 현재 구독 플랜. 토큰/비밀번호는 읽지 않고 상태 JSON만 사용한다.
    func subscriptionLabel() async -> String? {
        if let cachedPlanLabel { return cachedPlanLabel }
        let candidates = cliCandidates()
        for path in candidates {
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["auth", "status", "--json"]
            process.standardOutput = output
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { continue }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      (obj["loggedIn"] as? Bool) == true,
                      let raw = obj["subscriptionType"] as? String,
                      !raw.isEmpty else { continue }
                let label = raw
                    .replacingOccurrences(of: "_", with: " ")
                    .split(separator: " ")
                    .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                    .joined(separator: " ")
                cachedPlanLabel = label
                return label
            } catch {
                continue
            }
        }
        return nil
    }

    private func cliCandidates() -> [String] {
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) }
        return pathEntries.map { "\($0)/claude" } + [
            SnapshotStore.realHome.appendingPathComponent(".local/bin/claude").path,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude"
        ]
    }

    private func numVal(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        return nil
    }

    private func dateVal(_ v: Any?) -> Date? {
        if let s = v as? String { return ClaudeLogParser.parseISO(s) }
        if let d = numVal(v) { return Date(timeIntervalSince1970: d) }
        return nil
    }

    private func readAccessToken() -> String? {
        // 1) 키체인
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let token = extractToken(from: data) {
            return token
        }
        // 2) 파일 폴백
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: url), let token = extractToken(from: data) {
            return token
        }
        return nil
    }

    private func extractToken(from data: Data) -> String? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        return token
    }

    private func staleNote(_ reason: String) -> String {
        guard let fetchedAt = cached?.fetchedAt else {
            return "\(reason) — 한도 조회 불가"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        formatter.locale = Locale(identifier: "ko_KR")
        return "\(reason) — 마지막 성공값 \(formatter.string(from: fetchedAt)) 기준"
    }
}
