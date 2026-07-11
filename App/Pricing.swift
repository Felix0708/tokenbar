import Foundation

/// 100만 토큰당 달러 단가
struct ModelPrice {
    let input: Double
    let cacheWrite: Double
    let cacheRead: Double
    let output: Double
}

enum Pricing {
    /// 모델명으로 단가를 추정. 알 수 없는 모델은 중간급 단가로 대체 (비용은 어디까지나 추정치)
    static func price(for model: String) -> ModelPrice {
        let m = model.lowercased()
        // Anthropic
        if m.contains("opus") {
            return ModelPrice(input: 15, cacheWrite: 18.75, cacheRead: 1.5, output: 75)
        }
        if m.contains("haiku") {
            return ModelPrice(input: 1, cacheWrite: 1.25, cacheRead: 0.1, output: 5)
        }
        if m.contains("sonnet") || m.contains("fable") || m.contains("claude") {
            return ModelPrice(input: 3, cacheWrite: 3.75, cacheRead: 0.3, output: 15)
        }
        // Google
        if m.contains("gemini") {
            if m.contains("pro") {
                return ModelPrice(input: 1.25, cacheWrite: 0, cacheRead: 0.31, output: 10)
            }
            return ModelPrice(input: 0.30, cacheWrite: 0, cacheRead: 0.075, output: 2.5)
        }
        // OpenAI
        if m.contains("gpt-5") || m.contains("codex") || m.contains("o3") || m.contains("o4") {
            return ModelPrice(input: 1.25, cacheWrite: 0, cacheRead: 0.125, output: 10)
        }
        if m.contains("gpt-4") {
            return ModelPrice(input: 2.5, cacheWrite: 0, cacheRead: 1.25, output: 10)
        }
        // 기본값
        return ModelPrice(input: 3, cacheWrite: 3.75, cacheRead: 0.3, output: 15)
    }
}
