import Foundation

/// 한 공급자(Claude 또는 Codex)의 사용량 요약
struct ProviderUsage: Codable {
    var todayTokens: Int = 0
    var totalTokens: Int = 0
    var todayCost: Double = 0
    var totalCost: Double = 0
    /// 5시간 윈도우 사용률 (0~100)
    var sessionPercent: Double? = nil
    /// 주간 윈도우 사용률 (0~100)
    var weekPercent: Double? = nil
    var sessionResetAt: Date? = nil
    var weekResetAt: Date? = nil
    var note: String? = nil
}

struct UsageSnapshot: Codable {
    var updatedAt: Date = Date()
    var claude: ProviderUsage = ProviderUsage()
    var codex: ProviderUsage = ProviderUsage()
}

/// 앱과 위젯이 공유하는 스냅샷 저장소 (~/Library/Application Support/TokenBar/)
enum SnapshotStore {
    /// 샌드박스된 위젯에서도 실제 홈 디렉토리를 가리키도록 passwd 정보 사용
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var supportDir: URL {
        let dir = realHome
            .appendingPathComponent("Library/Application Support/TokenBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var fileURL: URL { supportDir.appendingPathComponent("snapshot.json") }

    static func save(_ snapshot: UsageSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }
}

enum Fmt {
    static func tokens(_ n: Int) -> String {
        let v = Double(n)
        if v >= 1_000_000_000 { return String(format: "%.2fB", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.1fK", v / 1_000) }
        return "\(n)"
    }

    /// 천 단위 콤마가 있는 정확한 숫자 (예: 9,612,345)
    static func exact(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func cost(_ c: Double) -> String {
        if c >= 100 { return String(format: "$%.0f", c) }
        return String(format: "$%.2f", c)
    }

    static func percent(_ p: Double?) -> String {
        guard let p = p else { return "–" }
        return String(format: "%.0f%%", p)
    }

    static func resetTime(_ d: Date?) -> String {
        guard let d = d else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        if Calendar.current.isDateInToday(d) {
            f.dateFormat = "HH:mm"
        } else {
            f.dateFormat = "E HH:mm"
        }
        return f.string(from: d) + " 리셋"
    }
}
