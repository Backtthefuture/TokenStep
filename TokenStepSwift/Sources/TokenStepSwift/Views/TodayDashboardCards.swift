import SwiftUI

enum TodaySourceRows {
    static func make(tools: [String: Int], maxNamed: Int = 3) -> [TodayBreakdownRow] {
        let total = tools.values.reduce(0, +)
        guard total > 0 else { return [] }
        let ranked = orderedToolEntries(tools)
        let named = Array(ranked.prefix(maxNamed))
        let rest = Array(ranked.dropFirst(maxNamed))
        var rows = named.map { entry in
            TodayBreakdownRow(
                name: entry.name,
                tokens: entry.tokens,
                percent: Double(entry.tokens) * 100 / Double(total),
                color: tokenToolColor(entry.name)
            )
        }
        if !rest.isEmpty {
            let tokens = rest.map(\.tokens).reduce(0, +)
            rows.append(
                TodayBreakdownRow(
                    name: LFormat("其他 %d 个来源", rest.count),
                    tokens: tokens,
                    percent: Double(tokens) * 100 / Double(total),
                    color: Color.tokenInk.opacity(0.35)
                )
            )
        }
        return rows
    }
}

struct TodayModelUsageRow: Identifiable, Equatable {
    var id: String { model }
    var model: String
    var tokens: Int
    var percent: Double
    var estimatedCost: Double?
}

enum TodayModelUsageRows {
    static let maximumVisibleRows = 5
    static let colorSlotCount = 4

    static func allPositiveRows(from usage: DailyUsage) -> [TodayModelUsageRow] {
        guard usage.totalTokens > 0 else { return [] }
        return usage.models
            .filter { $0.value > 0 }
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
            }
            .map { model, tokens in
                TodayModelUsageRow(
                    model: model,
                    tokens: tokens,
                    percent: min(100, max(0, Double(tokens) * 100 / Double(usage.totalTokens))),
                    estimatedCost: usage.modelCosts[model]
                )
            }
    }

    static func make(from usage: DailyUsage) -> [TodayModelUsageRow] {
        let sorted = allPositiveRows(from: usage)
        guard sorted.count > 2 else { return sorted }
        return sorted.enumerated()
            .filter { index, row in index < 2 || row.percent >= 0.1 }
            .map(\.element)
    }

    static func colorSlot(for model: String) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in model.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(colorSlotCount))
    }

    static func hasTokenTotalMismatch(_ usage: DailyUsage) -> Bool {
        guard usage.totalTokens > 0, !usage.models.isEmpty else { return false }
        return usage.models.values.filter { $0 > 0 }.reduce(0, +) != usage.totalTokens
    }
}
