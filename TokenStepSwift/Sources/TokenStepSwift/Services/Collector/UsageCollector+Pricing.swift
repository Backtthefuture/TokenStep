import Foundation

extension UsageCollector {
    /// How one family of models is billed, in USD per million tokens.
    enum PriceScheme {
        /// OpenAI style: cached input is a discounted subset of input.
        case openAI(input: Double, cachedInput: Double, output: Double)
        /// Anthropic style: cache writes and reads are priced separately from input.
        case anthropic(input: Double, output: Double, cacheCreation: Double, cacheRead: Double)
        /// One rate for every token when no breakdown is priced.
        case flat(Double)
    }

    struct PriceRule {
        /// Restricts the rule to one client; nil matches any client.
        var tool: String?
        /// Case-insensitive substring of the model name; nil matches any model.
        var modelFragment: String?
        var scheme: PriceScheme
    }

    /// Rough list prices for the local spend estimate. It is not a bill.
    /// Rules are checked in order and the first match wins, so keep specific
    /// models above broader families and fallbacks last.
    static let priceRules: [PriceRule] = [
        PriceRule(tool: "Codex", modelFragment: "gpt-5.5", scheme: .openAI(input: 5, cachedInput: 0.5, output: 30)),
        PriceRule(tool: "Codex", modelFragment: "gpt-5.4", scheme: .openAI(input: 2.5, cachedInput: 0.25, output: 15)),
        PriceRule(tool: nil, modelFragment: "opus", scheme: .anthropic(input: 5, output: 25, cacheCreation: 6.25, cacheRead: 0.5)),
        PriceRule(tool: nil, modelFragment: "sonnet", scheme: .anthropic(input: 3, output: 15, cacheCreation: 3.75, cacheRead: 0.3)),
        PriceRule(tool: "Claude Code", modelFragment: nil, scheme: .flat(3)),
        PriceRule(tool: nil, modelFragment: nil, scheme: .flat(1))
    ]

    static func estimateCost(usage: TokenUsageCounts, tool: String, model: String) -> Double {
        let lower = model.lowercased()
        let rule = priceRules.first { rule in
            (rule.tool == nil || rule.tool == tool)
                && (rule.modelFragment.map { lower.contains($0) } ?? true)
        }
        switch rule?.scheme ?? .flat(1) {
        case let .openAI(input, cachedInput, output):
            return openAICostByParts(usage: usage, input: input, cachedInput: cachedInput, output: output)
        case let .anthropic(input, output, cacheCreation, cacheRead):
            return costByParts(usage: usage, input: input, output: output, cacheCreation: cacheCreation, cacheRead: cacheRead)
        case let .flat(perMillion):
            return Double(usage.totalTokens) / 1_000_000 * perMillion
        }
    }

    static func openAICostByParts(
        usage: TokenUsageCounts,
        input: Double,
        cachedInput: Double,
        output: Double
    ) -> Double {
        let cached = max(0, usage.cacheReadInputTokens)
        let cacheCreation = max(0, usage.cacheCreationInputTokens)
        let uncachedInput = max(0, usage.inputTokens - cached - cacheCreation)
        if uncachedInput == 0,
           cached == 0,
           cacheCreation == 0,
           usage.outputTokens == 0,
           usage.totalTokens > 0 {
            return Double(usage.totalTokens) / 1_000_000 * input
        }
        return Double(uncachedInput + cacheCreation) / 1_000_000 * input
            + Double(cached) / 1_000_000 * cachedInput
            + Double(usage.outputTokens) / 1_000_000 * output
    }

    static func costByParts(
        usage: TokenUsageCounts,
        input: Double,
        output: Double,
        cacheCreation: Double,
        cacheRead: Double
    ) -> Double {
        let uncachedInput = max(
            0,
            usage.inputTokens - usage.cacheCreationInputTokens - usage.cacheReadInputTokens
        )
        return Double(uncachedInput) / 1_000_000 * input
            + Double(usage.outputTokens) / 1_000_000 * output
            + Double(usage.cacheCreationInputTokens) / 1_000_000 * cacheCreation
            + Double(usage.cacheReadInputTokens) / 1_000_000 * cacheRead
    }
}
