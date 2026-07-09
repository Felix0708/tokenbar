import Foundation
import Security

struct ClaudeLimits {
    var fiveHour: Double?
    var fiveHourReset: Date?
    var sevenDay: Double?
    var sevenDayReset: Date?
}

/// Anthropic OAuth usage API로 남은 한도(5시간/주간 %)를 조회.
/// 토큰은 macOS 키체인("Claude Code-credentials") 또는 ~/.claude/.credentials.json 에서 읽음.
/// 응답은 5분 캐시, 429 발생 시 15분 백오프.
final class ClaudeOAuthClient {
    private var cached: ClaudeLimits?
    private var lastFetch: Date?
    private var backoffUntil: Date?
    private(set) var statusNote: String?

    private let cacheInterval: TimeInterval = 300
    private let backoffInterval: TimeInterval = 900

    func fetchLimits() async -> ClaudeLimits? {
        if let last = lastFetch, Date().timeIntervalSince(last) < cacheInterval, cached != nil {
            return cached
        }
        if let until = backoffUntil, Date() < until {
            return cached
        }
        guard let token = readAccessToken() else {
            statusNote = "Claude Code 로그인 정보 없음 (키체인 접근 허용 필요)"
            return cached
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 429 {
                backoffUntil = Date().addingTimeInterval(backoffInterval)
                statusNote = "한도 API 요청 제한 — 잠시 후 재시도"
                return cached
            }
            if status == 401 || status == 403 {
                statusNote = "토큰 만료 — Claude Code를 한 번 실행하면 갱신됨"
                return cached
            }
            guard status == 200,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                statusNote = "한도 API 응답 오류 (\(status))"
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
            cached = limits
            lastFetch = Date()
            statusNote = nil
            return limits
        } catch {
            statusNote = "네트워크 오류"
            return cached
        }
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
}
