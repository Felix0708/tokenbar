import Foundation

struct GeminiFileAgg: Codable {
    var mtime: Double
    var size: Int
    /// day(로컬) → model → 집계
    var days: [String: [String: DayAgg]]
    /// day(태평양 시간, 한도 리셋 기준) → 요청 수
    var reqsPT: [String: Int]
}

/// ~/.gemini/tmp/*/chats/*.json(l) 을 파싱해 토큰/비용/요청 수를 집계.
/// Gemini는 한도 %를 제공하지 않으므로 "오늘 요청 수 ÷ 플랜 일일 한도"로 추정.
/// (일일 한도는 태평양 시간 자정에 리셋)
final class GeminiLogParser {
    private var cache: [String: GeminiFileAgg] = [:]
    private let cacheURL = SnapshotStore.supportDir.appendingPathComponent("cache-gemini-v2.json")

    static let ptDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return f
    }()

    init() {
        if let data = try? Data(contentsOf: cacheURL),
           let c = try? JSONDecoder().decode([String: GeminiFileAgg].self, from: data) {
            cache = c
        }
    }

    func collect(dailyLimit: Int) -> ProviderUsage {
        var usage = ProviderUsage()
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/tmp")
        guard fm.fileExists(atPath: root.path),
              let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            usage.note = "~/.gemini/tmp 없음 (Gemini CLI 미사용)"
            return usage
        }

        var newCache: [String: GeminiFileAgg] = [:]
        var modelAgg: [String: ModelUsage] = [:]
        let today = ClaudeLogParser.dayFormatter.string(from: Date())
        let todayPT = Self.ptDayFormatter.string(from: Date())
        var requestsToday = 0

        for case let url as URL in enumerator {
            let ext = url.pathExtension
            guard ext == "json" || ext == "jsonl" else { continue }
            guard url.path.contains("/chats/") else { continue }

            let path = url.path
            let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = rv?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = rv?.fileSize ?? 0

            let agg: GeminiFileAgg
            if let cached = cache[path], cached.mtime == mtime, cached.size == size {
                agg = cached
            } else {
                agg = Self.parse(url: url, mtime: mtime, size: size)
            }
            newCache[path] = agg

            requestsToday += agg.reqsPT[todayPT] ?? 0

            for (day, models) in agg.days {
                for (model, d) in models {
                    usage.totalTokens += d.tokens
                    usage.totalCost += d.cost
                    var m = modelAgg[model] ?? ModelUsage(name: model)
                    m.totalTokens += d.tokens
                    m.totalCost += d.cost
                    if day == today {
                        usage.todayTokens += d.tokens
                        usage.todayCost += d.cost
                        m.todayTokens += d.tokens
                        m.todayCost += d.cost
                    }
                    modelAgg[model] = m
                }
            }
        }

        if newCache.isEmpty {
            usage.note = "Gemini CLI 기록 없음"
        } else {
            // 일일 한도 사용률 추정 (요청 수 기반)
            usage.sessionLabel = "일일"
            usage.sessionPercent = min(100, Double(requestsToday) / Double(max(dailyLimit, 1)) * 100)
            var cal = Calendar(identifier: .gregorian)
            if let pt = TimeZone(identifier: "America/Los_Angeles") { cal.timeZone = pt }
            let startOfDay = cal.startOfDay(for: Date())
            usage.sessionResetAt = cal.date(byAdding: .day, value: 1, to: startOfDay)
            usage.note = "일일 \(requestsToday)/\(dailyLimit)회 · 요청 수 기반 추정"
        }
        usage.models = modelAgg.values
            .filter { $0.totalTokens > 0 }
            .sorted { $0.totalTokens > $1.totalTokens }
        cache = newCache
        if let data = try? JSONEncoder().encode(newCache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
        return usage
    }

    private static func parse(url: URL, mtime: Double, size: Int) -> GeminiFileAgg {
        var days: [String: [String: DayAgg]] = [:]
        var reqsPT: [String: Int] = [:]
        guard let data = try? Data(contentsOf: url) else {
            return GeminiFileAgg(mtime: mtime, size: size, days: [:], reqsPT: [:])
        }

        // 메시지 목록 추출 (json / jsonl 모두 지원, 포맷 변화에 방어적으로)
        var messages: [[String: Any]] = []
        if url.pathExtension == "jsonl" {
            if let content = String(data: data, encoding: .utf8) {
                for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                    if let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] {
                        messages.append(obj)
                    }
                }
            }
        } else if let obj = try? JSONSerialization.jsonObject(with: data) {
            if let dict = obj as? [String: Any] {
                if let msgs = dict["messages"] as? [[String: Any]] {
                    messages = msgs
                } else if let hist = dict["history"] as? [[String: Any]] {
                    messages = hist
                } else {
                    messages = [dict]
                }
            } else if let arr = obj as? [[String: Any]] {
                messages = arr
            }
        }

        let fileDate = Date(timeIntervalSince1970: mtime > 0 ? mtime : Date().timeIntervalSince1970)
        let fallbackDay = ClaudeLogParser.dayFormatter.string(from: fileDate)
        let fallbackDayPT = ptDayFormatter.string(from: fileDate)

        for msg in messages {
            guard let tokens = msg["tokens"] as? [String: Any] else { continue }
            let input = ClaudeLogParser.intVal(tokens["input"])
            let output = ClaudeLogParser.intVal(tokens["output"])
            let cached = ClaudeLogParser.intVal(tokens["cached"])
            let thoughts = ClaudeLogParser.intVal(tokens["thoughts"])
            let tool = ClaudeLogParser.intVal(tokens["tool"])
            let total = ClaudeLogParser.intVal(tokens["total"])
            let sum = total > 0 ? total : (input + output + thoughts + tool)
            guard sum > 0 else { continue }

            let rawModel = (msg["model"] as? String) ?? "gemini"
            let p = Pricing.price(for: rawModel)
            let freshInput = max(0, input - cached)
            let cost = (Double(freshInput) * p.input
                        + Double(cached) * p.cacheRead
                        + Double(output + thoughts + tool) * p.output) / 1_000_000

            var day = fallbackDay
            var dayPT = fallbackDayPT
            if let ts = msg["timestamp"] as? String, let date = ClaudeLogParser.parseISO(ts) {
                day = ClaudeLogParser.dayFormatter.string(from: date)
                dayPT = ptDayFormatter.string(from: date)
            }
            let model = ClaudeLogParser.shortModel(rawModel)
            var d = days[day]?[model] ?? DayAgg(tokens: 0, cost: 0)
            d.tokens += sum
            d.cost += cost
            days[day, default: [:]][model] = d
            reqsPT[dayPT, default: 0] += 1
        }
        return GeminiFileAgg(mtime: mtime, size: size, days: days, reqsPT: reqsPT)
    }
}
