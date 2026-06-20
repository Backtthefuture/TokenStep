import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    var historyLimit: Int? = nil

    var body: some View {
        VStack(spacing: 22) {
            TokenCard {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L("近 8 个月活动墙"))
                                .font(.title3.weight(.heavy))
                                .foregroundStyle(Color.tokenInk)
                            Text(L("颜色越深，用量越高；描边是今天"))
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(LFormat("%d 个活跃日", appState.snapshot.totals.activeDays))
                            .font(.callout.weight(.bold))
                            .foregroundStyle(Color.tokenGreenDark)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.tokenMint.opacity(0.28), in: Capsule())
                    }

                    ContributionWallView(
                        rows: Array(appState.snapshot.daily.suffix(238)),
                        goal: appState.settings.dailyGoalTokens
                    )
                }
            }

            TokenCard {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L("全部明细"))
                                .font(.title3.weight(.heavy))
                                .foregroundStyle(Color.tokenInk)
                            Text(historySummaryText)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        TokenToolLegend(tools: historyTools)
                    }

                    LazyVStack(spacing: 0) {
                        header
                        ForEach(historyRows) { row in
                            HistoryRow(row: row, goal: appState.settings.dailyGoalTokens)
                        }
                    }
                }
            }
        }
    }

    private var historyRows: [DailyUsage] {
        let rows = appState.visibleHistoryRows
        guard let historyLimit else { return rows }
        return Array(rows.prefix(historyLimit))
    }

    private var historySummaryText: String {
        if let historyLimit {
            return LFormat("最近 %d 天，适合保存为截图", min(historyLimit, historyRows.count))
        }
        return LFormat("%d 条记录，向下滚动查看完整历史", appState.visibleHistoryRows.count)
    }

    private var historyTools: [String] {
        uniqueToolNames(in: historyRows)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text(L("日期")).frame(width: 118, alignment: .leading)
            Text(L("Token 消耗")).frame(width: 150, alignment: .leading)
            Text(L("消耗金额")).frame(width: 126, alignment: .leading)
            Text(L("主力工具")).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption.weight(.heavy))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.tokenTrack.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct HistoryRow: View {
    var row: DailyUsage
    var goal: Int

    var body: some View {
        HStack(spacing: 16) {
            Text(row.date)
                .frame(width: 118, alignment: .leading)
                .foregroundStyle(Color.tokenInk.opacity(0.72))
            Text(TokenStepFormat.tokens(row.totalTokens))
                .fontWeight(.heavy)
                .foregroundStyle(Color.tokenInk)
                .frame(width: 150, alignment: .leading)
            Text(TokenStepFormat.money(row.cost))
                .frame(width: 126, alignment: .leading)
                .foregroundStyle(Color.tokenInk.opacity(0.72))
            HStack(spacing: 8) {
                Circle()
                    .fill(tokenToolColor(dominantTool))
                    .frame(width: 8, height: 8)
                Text(dominantTool)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color.tokenInk.opacity(0.72))
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.055))
                .frame(height: 1)
        }
    }

    private var dominantTool: String {
        row.tools.max(by: { $0.value < $1.value })?.key ?? L("无")
    }
}
