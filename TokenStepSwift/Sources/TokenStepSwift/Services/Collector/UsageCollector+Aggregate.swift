import Foundation

extension UsageCollector {
    static func aggregate(records: [UsageRecord], sources: [String: SourceInfo]) -> UsageSnapshot {
        var daily = [String: DailyAccumulator]()
        var rhythms = [String: RhythmAccumulator]()
        var agentWork = [String: AgentWorkAccumulator]()
        var tools = [String: UsageAccumulator]()
        var models = [ModelKey: UsageAccumulator]()

        for record in records {
            let cost = record.costUSD ?? estimateCost(usage: record.usage, tool: record.tool, model: record.model)
            daily[record.date, default: DailyAccumulator(date: record.date)].add(record: record, cost: cost)
            let recordHour = record.timestampEpoch.map(hour(fromEpoch:))
                ?? hour(fromISO: record.timestamp)
            if let hour = recordHour {
                rhythms[record.date, default: RhythmAccumulator(date: record.date)]
                    .add(tokens: record.usage.totalTokens, hour: hour)
            }
            if isAgentWorkRecord(record) {
                agentWork[record.date, default: AgentWorkAccumulator(date: record.date)]
                    .add(record: record, hour: recordHour)
            }
            tools[record.tool, default: UsageAccumulator()].add(record.usage, cost: cost)
            models[ModelKey(tool: record.tool, model: record.model), default: UsageAccumulator()].add(record.usage, cost: cost)
        }

        let totalTokens = tools.values.map(\.usage.totalTokens).reduce(0, +)
        let totalCost = tools.values.map(\.cost).reduce(0, +)

        let dailyRows = daily.values
            .sorted { $0.date < $1.date }
            .map { item in
                DailyUsage(
                    date: item.date,
                    tools: item.tools,
                    models: item.models,
                    modelCosts: item.modelCosts.mapValues { rounded($0, digits: 4) },
                    totalTokens: item.totalTokens,
                    cost: rounded(item.cost, digits: 4)
                )
            }

        let rhythmRows = rhythms.values
            .map(\.dailyRhythm)
            .filter { $0.totalTokens > 0 }
            .sorted { $0.date < $1.date }

        let agentWorkRows = agentWork.values
            .map(\.dailyAgentWork)
            .filter { $0.totalTokens > 0 }
            .sorted { $0.date < $1.date }

        let toolRows = tools
            .sorted { $0.value.usage.totalTokens > $1.value.usage.totalTokens }
            .map { tool, item in
                ToolUsage(
                    tool: tool,
                    tokens: item.usage.totalTokens,
                    percent: percent(item.usage.totalTokens, of: totalTokens)
                )
            }

        let modelRows = models
            .sorted { $0.value.usage.totalTokens > $1.value.usage.totalTokens }
            .map { key, item in
                ModelUsage(
                    model: key.model,
                    tool: key.tool,
                    tokens: item.usage.totalTokens,
                    percent: percent(item.usage.totalTokens, of: totalTokens)
                )
            }

        return UsageSnapshot(
            generatedAt: isoFormatter.string(from: Date()),
            timezone: timezone.identifier,
            totals: UsageTotals(
                tokens: totalTokens,
                cost: rounded(totalCost, digits: 2),
                activeDays: dailyRows.filter { $0.totalTokens > 0 }.count
            ),
            daily: dailyRows,
            rhythms: rhythmRows,
            agentWork: agentWorkRows,
            tools: toolRows,
            models: modelRows,
            sources: sources
        )
    }

    static func isAgentWorkRecord(_ record: UsageRecord) -> Bool {
        switch record.source {
        case .nativeCodex, .nativeCodexSQLite, .nativeClaudeCode, .ccSwitchProxy, .zcode, .hermes, .workbuddy:
            return true
        case .unknown:
            return false
        }
    }

    static func percent(_ value: Int, of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return rounded(Double(value) / Double(total) * 100, digits: 2)
    }

    static func rounded(_ value: Double, digits: Int) -> Double {
        let multiplier = pow(10.0, Double(digits))
        return (value * multiplier).rounded() / multiplier
    }
}
