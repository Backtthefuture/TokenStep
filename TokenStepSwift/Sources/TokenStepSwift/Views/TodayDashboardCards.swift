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

// MARK: - Subscription quotas

/// Quota of every enabled provider, rendered by unit: Trae CN in credits,
/// Trae in dollars, everything else as the historic percent reading.
struct TodayQuotaCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let quotas = appState.dashboardQuotas
        TokenCard {
            VStack(alignment: .leading, spacing: 14) {
                DashboardCardHeader(L("订阅额度")) {
                    if appState.isRefreshingCodexQuota {
                        Text(L("读取中…"))
                    } else if let updated = quotas.compactMap(\.fetchedAt).max() {
                        Text(LFormat("已用 · %@", CompactPopoverStyle.relative(updated)))
                    }
                }
                if quotas.isEmpty {
                    Text(L("在设置里启用额度监控后，这里会显示各订阅的剩余额度。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                } else {
                    ForEach(quotas) { quota in
                        providerBlock(quota)
                    }
                }
            }
        }
    }

    private func providerBlock(_ quota: ProviderQuota) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                QuotaProviderIcon(provider: quota.provider, size: 18)
                Text(quota.provider.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.tokenInk)
                if quota.isAvailable, quota.isLow {
                    Text(L("额度偏低"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CompactPopoverStyle.color(for: .warning))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(CompactPopoverStyle.color(for: .warning).opacity(0.14), in: Capsule())
                }
                Spacer(minLength: 8)
                if let fetchedAt = quota.fetchedAt {
                    Text(CompactPopoverStyle.relative(fetchedAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if quota.isAvailable {
                ForEach(quota.windows) { window in
                    windowRow(window)
                }
            } else {
                Text(QuotaPresentation.unavailableReason(quota, isRefreshing: appState.isRefreshingCodexQuota))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func windowRow(_ window: QuotaWindow) -> some View {
        let row = CompactPopoverModel.windowRow(window, now: Date(), calendar: TokenStepClock.calendar)
        return HStack(spacing: 10) {
            Text(row.title)
                .font(.system(size: 12, weight: row.runsOutEarly ? .semibold : .regular))
                .foregroundStyle(row.runsOutEarly ? CompactPopoverStyle.color(for: .warning) : Color.secondary)
                .frame(width: 72, alignment: .leading)
                .lineLimit(1)
            CompactBar(
                fraction: row.usedPercent / 100,
                color: CompactPopoverStyle.color(for: row.level),
                marker: row.elapsedFraction
            )
            if row.isReset {
                Text("—")
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(CompactPopoverStyle.textColor(for: row.level))
                    .frame(width: 132, alignment: .trailing)
            } else if let credits = row.creditUsageText {
                Text(credits)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(CompactPopoverStyle.textColor(for: row.level))
                    .frame(minWidth: 132, alignment: .trailing)
                    .layoutPriority(1)
            } else {
                Text(CompactPopoverStyle.percent(row.usedPercent))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(CompactPopoverStyle.textColor(for: row.level))
                    .frame(width: 48, alignment: .trailing)
            }
            Text(row.isReset ? L("已重置") : CompactPopoverStyle.resetText(row.resetsAt) ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 80, alignment: .trailing)
        }
        .help(windowHelp(row))
    }

    private func windowHelp(_ row: CompactPopoverModel.QuotaWindowRow) -> String {
        if let usage = row.creditUsageText, let total = row.creditTotalText {
            return LFormat("%@ · %@", usage, total)
        }
        return LFormat("已用 %@", CompactPopoverStyle.percent(row.usedPercent))
    }
}
