import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 22) {
            TokenCard {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("近 8 个月活动墙")
                                .font(.title3.weight(.heavy))
                                .foregroundStyle(Color.tokenInk)
                            Text("颜色越深，越接近或超过每日目标")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(appState.snapshot.totals.activeDays) 个活跃日")
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
                            Text("全部明细")
                                .font(.title3.weight(.heavy))
                                .foregroundStyle(Color.tokenInk)
                            Text("\(appState.visibleHistoryRows.count) 条记录，向下滚动查看完整历史")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    LazyVStack(spacing: 0) {
                        header
                        ForEach(appState.visibleHistoryRows) { row in
                            HistoryRow(row: row, goal: appState.settings.dailyGoalTokens)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text("日期").frame(width: 118, alignment: .leading)
            Text("AI 步数").frame(width: 126, alignment: .leading)
            Text("圈数").frame(width: 110, alignment: .leading)
            Text("消耗金额").frame(width: 112, alignment: .leading)
            Text("主力工具").frame(maxWidth: .infinity, alignment: .leading)
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
    private var lap: TokenStepLapProgress {
        TokenStepLapProgress(tokens: row.totalTokens, goal: goal)
    }

    var body: some View {
        HStack(spacing: 16) {
            Text(row.date)
                .frame(width: 118, alignment: .leading)
                .foregroundStyle(Color.tokenInk.opacity(0.72))
            Text(TokenStepFormat.tokens(row.totalTokens))
                .fontWeight(.heavy)
                .foregroundStyle(Color.tokenInk)
                .frame(width: 126, alignment: .leading)
            Text(lapText)
                .fontWeight(.heavy)
                .foregroundStyle(row.totalTokens >= goal ? lap.color : .secondary)
                .frame(width: 110, alignment: .leading)
            Text(TokenStepFormat.money(row.cost))
                .frame(width: 112, alignment: .leading)
                .foregroundStyle(Color.tokenInk.opacity(0.72))
            HStack(spacing: 8) {
                Circle()
                    .fill(contributionColor(tokens: row.totalTokens, goal: goal))
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
        row.tools.max(by: { $0.value < $1.value })?.key ?? "无"
    }

    private var lapText: String {
        if row.totalTokens >= max(goal, 1) {
            return "\(lap.lapTitle) \(lap.lapPercentText)"
        }
        return TokenStepFormat.percent(lap.rawProgress * 100)
    }
}
