import Foundation

/// 일 단위 집계
struct DayAgg: Codable {
    var tokens: Int
    var cost: Double
}

struct ClaudeFileAgg: Codable {
    var mtime: Double
    var size: Int
    var days: [String: DayAgg]
}

/// ~/.claude/projects/**/*.jsonl 을 파싱해 토큰/비용을 집계.
/// 파일별 (mtime, size) 캐시로 변경된 파일만 다시 읽음.
final class ClaudeLogParser {
    private var cache: [String: ClaudeFileAgg] = [:]
    private let cacheURL = SnapshotStore.supportDir.appendingPathComponent("cache-claude.json")

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()

    init() {
        if let data = try? Data(contentsOf: cacheURL),
           let c = try? JSONDecoder().decode([String: ClaudeFileAgg].self, from: data) {
            cache = c
        }
    }

    func collect() -> ProviderUsage {
        var usage = ProviderUsage()
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        guard fm.fileExists(atPath: root.path),
              let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            usage.note = "~/.claude/projects 폴더를 찾을 수 없음"
            return usage
        }

        var newCache: [String: ClaudeFileAgg] = [:]
        let today = Self.dayFormatter.string(from: Date())

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let path = url.path
            let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = rv?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = rv?.fileSize ?? 0

            let agg: ClaudeFileAgg
            if let cached = cache[path], cached.mtime == mtime, cached.size == size {
                agg = cached
            } else {
                agg = Self.parse(url: url, mtime: mtime, size: size)
            }
            newCache[path] = agg

            for (day, d) in agg.days {
                usage.totalTokens += d.tokens
                usage.totalCost += d.cost
                if day == today {
                    usage.todayTokens += d.tokens
                    usage.todayCost += d.cost
                }
            }
        }

        cache = newCache
        if let data = try? JSONEncoder().encode(newCache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
        return usage
    }

    private static func parse(url: URL, mtime: Double, size: Int) -> ClaudeFileAgg {
        var days: [String: DayAgg] = [:]
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ClaudeFileAgg(mtime: mtime, size: size, days: [:])
        }

        var seen = Set<String>()
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.contains("\"usage\""), line.contains("assistant") else { continue }
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  (obj["type"] as? String) == "assistant",
                  let msg = obj["message"] as? [String: Any],
                  let u = msg["usage"] as? [String: Any] else { continue }

            // 중복 제거 (같은 응답이 여러 줄에 기록되는 경우)
            let msgId = msg["id"] as? String ?? ""
            let reqId = obj["requestId"] as? String ?? ""
            if !msgId.isEmpty || !reqId.isEmpty {
                let key = msgId + "|" + reqId
                if seen.contains(key) { continue }
                seen.insert(key)
            }

            let input = intVal(u["input_tokens"])
            let output = intVal(u["output_tokens"])
            let cacheW = intVal(u["cache_creation_input_tokens"])
            let cacheR = intVal(u["cache_read_input_tokens"])
            let model = msg["model"] as? String ?? ""
            let p = Pricing.price(for: model)
            let cost = (Double(input) * p.input
                        + Double(output) * p.output
                        + Double(cacheW) * p.cacheWrite
                        + Double(cacheR) * p.cacheRead) / 1_000_000

            var day = "unknown"
            if let ts = obj["timestamp"] as? String, let date = parseISO(ts) {
                day = dayFormatter.string(from: date)
            }
            var d = days[day] ?? DayAgg(tokens: 0, cost: 0)
            d.tokens += input + output + cacheW + cacheR
            d.cost += cost
            days[day] = d
        }
        return ClaudeFileAgg(mtime: mtime, size: size, days: days)
    }

    static func intVal(_ v: Any?) -> Int {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        return 0
    }

    static func parseISO(_ s: String) -> Date? {
        return isoFrac.date(from: s) ?? iso.date(from: s)
    }
}
