import Foundation

struct CodexFileAgg: Codable {
    var mtime: Double
    var size: Int
    var day: String
    var model: String
    var tokens: Int
    var cost: Double
    var primaryPercent: Double?
    var secondaryPercent: Double?
    var primaryResetAt: Date?
    var secondaryResetAt: Date?
    var lastTimestamp: Date?
    var planType: String?
}

/// ~/.codex/sessions/**/rollout-*.jsonl 을 파싱.
/// token_count 이벤트의 total_token_usage(누적치)와 rate_limits(사용률 %)를 읽음.
final class CodexLogParser {
    private var cache: [String: CodexFileAgg] = [:]
    private let cacheURL = SnapshotStore.supportDir.appendingPathComponent("cache-codex-v2.json")

    init() {
        if let data = try? Data(contentsOf: cacheURL),
           let c = try? JSONDecoder().decode([String: CodexFileAgg].self, from: data) {
            cache = c
        }
    }

    func collect() -> ProviderUsage {
        var usage = ProviderUsage()
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard fm.fileExists(atPath: root.path),
              let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            usage.note = "~/.codex/sessions 폴더를 찾을 수 없음"
            return usage
        }

        var newCache: [String: CodexFileAgg] = [:]
        var modelAgg: [String: ModelUsage] = [:]
        let today = ClaudeLogParser.dayFormatter.string(from: Date())
        var latestLimits: CodexFileAgg? = nil

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let path = url.path
            let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = rv?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = rv?.fileSize ?? 0

            let agg: CodexFileAgg
            if let cached = cache[path], cached.mtime == mtime, cached.size == size {
                agg = cached
            } else {
                agg = Self.parse(url: url, mtime: mtime, size: size)
            }
            newCache[path] = agg

            usage.totalTokens += agg.tokens
            usage.totalCost += agg.cost
            var m = modelAgg[agg.model] ?? ModelUsage(name: agg.model)
            m.totalTokens += agg.tokens
            m.totalCost += agg.cost
            if agg.day == today {
                usage.todayTokens += agg.tokens
                usage.todayCost += agg.cost
                m.todayTokens += agg.tokens
                m.todayCost += agg.cost
            }
            if agg.tokens > 0 { modelAgg[agg.model] = m }

            if agg.primaryPercent != nil || agg.secondaryPercent != nil {
                if let ts = agg.lastTimestamp {
                    if latestLimits == nil || (latestLimits?.lastTimestamp ?? .distantPast) < ts {
                        latestLimits = agg
                    }
                }
            }
        }

        if let l = latestLimits {
            if let plan = l.planType {
                usage.planLabel = Self.planLabel(plan)
                usage.planDetected = true
            }
            usage.sessionPercent = l.primaryPercent
            usage.weekPercent = l.secondaryPercent
            usage.sessionResetAt = l.primaryResetAt
            usage.weekResetAt = l.secondaryResetAt
            // 기록 당시의 리셋 시각이 이미 지났으면 해당 창은 0으로 처리
            if let reset = l.primaryResetAt {
                if Date() > reset { usage.sessionPercent = 0; usage.sessionResetAt = nil }
            } else if let ts = l.lastTimestamp, Date().timeIntervalSince(ts) > 6 * 3600 {
                usage.sessionPercent = 0
            }
            if let reset = l.secondaryResetAt, Date() > reset {
                usage.weekPercent = 0
                usage.weekResetAt = nil
            }
            if let ts = l.lastTimestamp, Date().timeIntervalSince(ts) > 15 * 60 {
                let f = DateFormatter()
                f.dateFormat = "MM/dd HH:mm"
                f.locale = Locale(identifier: "ko_KR")
                usage.note = "한도는 마지막 Codex 세션 기록(\(f.string(from: ts))) 기준"
            }
        }

        usage.weekLabel = "주간"
        usage.models = modelAgg.values
            .filter { $0.totalTokens > 0 }
            .sorted { $0.totalTokens > $1.totalTokens }
        cache = newCache
        if let data = try? JSONEncoder().encode(newCache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
        return usage
    }

    private static func planLabel(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private static func parse(url: URL, mtime: Double, size: Int) -> CodexFileAgg {
        // 경로에서 날짜 추출: .../sessions/YYYY/MM/DD/rollout-*.jsonl
        var day = "unknown"
        let comps = url.pathComponents
        if comps.count >= 4 {
            let n = comps.count
            let y = comps[n - 4], m = comps[n - 3], d = comps[n - 2]
            if y.count == 4, Int(y) != nil, Int(m) != nil, Int(d) != nil {
                day = "\(y)-\(m)-\(d)"
            }
        }

        var agg = CodexFileAgg(mtime: mtime, size: size, day: day, model: "gpt-5", tokens: 0, cost: 0,
                               primaryPercent: nil, secondaryPercent: nil,
                               primaryResetAt: nil, secondaryResetAt: nil, lastTimestamp: nil,
                               planType: nil)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return agg }

        var model = ""
        var lastTotal: [String: Any]? = nil

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let hasTokenCount = line.contains("token_count")
            let hasModel = line.contains("\"model\"")
            guard hasTokenCount || hasModel else { continue }
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any] else { continue }

            if let m = payload["model"] as? String, !m.isEmpty {
                model = m
            }
            guard (payload["type"] as? String) == "token_count" else { continue }

            let ts = (obj["timestamp"] as? String).flatMap { ClaudeLogParser.parseISO($0) }
            if let ts = ts { agg.lastTimestamp = ts }

            if let info = payload["info"] as? [String: Any],
               let total = info["total_token_usage"] as? [String: Any] {
                lastTotal = total
            }
            if let rl = payload["rate_limits"] as? [String: Any] {
                if let plan = rl["plan_type"] as? String, !plan.isEmpty {
                    agg.planType = plan
                }
                let base = ts ?? Date()
                if let p = rl["primary"] as? [String: Any] {
                    agg.primaryPercent = doubleVal(p["used_percent"])
                    agg.primaryResetAt = resetDate(p, base: base)
                }
                if let s = rl["secondary"] as? [String: Any] {
                    agg.secondaryPercent = doubleVal(s["used_percent"])
                    agg.secondaryResetAt = resetDate(s, base: base)
                }
            }
        }

        agg.model = ClaudeLogParser.shortModel(model.isEmpty ? "gpt-5" : model)

        if let total = lastTotal {
            let input = ClaudeLogParser.intVal(total["input_tokens"])
            let cached = ClaudeLogParser.intVal(total["cached_input_tokens"])
            let output = ClaudeLogParser.intVal(total["output_tokens"])
            let totalTokens = ClaudeLogParser.intVal(total["total_tokens"])
            agg.tokens = totalTokens > 0 ? totalTokens : (input + output)

            let p = Pricing.price(for: model.isEmpty ? "gpt-5" : model)
            let freshInput = max(0, input - cached)
            agg.cost = (Double(freshInput) * p.input
                        + Double(cached) * p.cacheRead
                        + Double(output) * p.output) / 1_000_000
        }
        return agg
    }

    private static func doubleVal(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        return nil
    }

    private static func resetDate(_ window: [String: Any], base: Date) -> Date? {
        if let secs = doubleVal(window["resets_in_seconds"]) {
            return base.addingTimeInterval(secs)
        }
        if let s = window["resets_at"] as? String {
            return ClaudeLogParser.parseISO(s)
        }
        if let epoch = doubleVal(window["resets_at"]) {
            return Date(timeIntervalSince1970: epoch)
        }
        return nil
    }
}
