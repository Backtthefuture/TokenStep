import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 22) {
            hero
            metricStrip
            TokenCard {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最近 30 天")
                                .font(.title3.weight(.heavy))
                                .foregroundStyle(Color.tokenInk)
                            Text("颜色越深，圈数越高")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("今天 \(TokenStepFormat.tokens(appState.today.totalTokens, compact: true))")
                            .font(.callout.weight(.bold))
                            .foregroundStyle(Color.tokenGreenDark)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.tokenMint.opacity(0.28), in: Capsule())
                    }
                    ActivityBarsView(rows: appState.snapshot.daily, goal: appState.settings.dailyGoalTokens)
                        .frame(height: 96)
                }
            }

            HStack(alignment: .top, spacing: 22) {
                distributionCard(title: "按客户端", rows: appState.snapshot.tools.prefix(5).map {
                    UsageDistributionRow(name: $0.tool, value: $0.tokens, percent: $0.percentValue, color: $0.displayColor)
                })
                distributionCard(title: "主力模型", rows: appState.snapshot.models.prefix(5).map {
                    UsageDistributionRow(name: $0.model, value: $0.tokens, percent: $0.percentValue, color: $0.displayColor)
                })
            }
        }
    }

    private var hero: some View {
        let lap = appState.todayLap
        return TokenCard {
            HStack(alignment: .center, spacing: 34) {
                ZStack {
                    ProgressRingView(progress: lap.currentLapProgress, lineWidth: 20, color: lap.color)
                    VStack(spacing: 6) {
                        Text(TokenStepFormat.tokens(appState.today.totalTokens))
                            .font(.system(size: 42, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.tokenInk)
                            .minimumScaleFactor(0.42)
                            .lineLimit(1)
                        Text("/ \(TokenStepFormat.tokens(appState.settings.dailyGoalTokens, compact: true)) 每圈")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 160)
                }
                .frame(width: 204, height: 204)

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lap.lapStatusText)
                            .font(.system(size: 35, weight: .heavy, design: .rounded))
                            .foregroundStyle(lap.color)
                            .monospacedDigit()
                        Text(lap.completedTokensText)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(lap.perLapGoalText)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("圈数进度")
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(Color.tokenInk)
                        LapProgressChips(lap: lap)
                    }

                    HStack(spacing: 10) {
                        MetricPill(label: "消耗金额", value: TokenStepFormat.money(appState.today.cost))
                        MetricPill(label: "本月均值", value: TokenStepFormat.tokens(appState.monthAverage, compact: true))
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var metricStrip: some View {
        HStack(spacing: 18) {
            CompactMetricCard(label: "累计 AI 步数", value: TokenStepFormat.tokens(appState.snapshot.totals.tokens), detail: "所有本机记录")
            CompactMetricCard(label: "活跃天数", value: "\(appState.snapshot.totals.activeDays) 天", detail: "有 AI 使用的日期")
            CompactMetricCard(label: "达标天数", value: "\(appState.goalDays) 天", detail: "达到每日目标")
        }
    }

    private func distributionCard(title: String, rows: [UsageDistributionRow]) -> some View {
        TokenCard {
            VStack(alignment: .leading, spacing: 17) {
                Text(title)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color.tokenInk)
                if rows.isEmpty {
                    Text("等待下一次同步")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                } else {
                    ForEach(rows) { row in
                        UsageProgressRow(
                            name: row.name,
                            value: "\(TokenStepFormat.tokens(row.value, compact: true)) · \(TokenStepFormat.percent(row.percent))",
                            percent: row.percent,
                            color: row.color
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CompactMetricCard: View {
    var label: String
    var value: String
    var detail: String

    var body: some View {
        TokenCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.tokenInk)
                    .minimumScaleFactor(0.66)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct UsageDistributionRow: Identifiable {
    var id: String { name }
    var name: String
    var value: Int
    var percent: Double
    var color: Color
}

private struct LapProgressChips: View {
    var lap: TokenStepLapProgress

    private var visibleCompletedLaps: [Int] {
        let completed = max(0, lap.completedLaps)
        guard completed > 0 else { return [] }
        if completed <= 2 { return Array(1...completed) }
        return Array(max(1, completed - 1)...completed)
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(visibleCompletedLaps, id: \.self) { item in
                LapChip(title: "\(item)圈完成", detail: TokenStepFormat.tokens(item * lap.safeGoal, compact: true), active: false, color: .tokenGreen)
            }
            LapChip(title: "\(lap.lapTitle)进行中", detail: lap.lapPercentText, active: true, color: lap.color)
        }
    }
}

private struct LapChip: View {
    var title: String
    var detail: String
    var active: Bool
    var color: Color

    var body: some View {
        VStack(spacing: 4) {
            Label(title, systemImage: active ? "arrow.clockwise.circle.fill" : "checkmark.circle.fill")
                .font(.caption.weight(.heavy))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
            Text(detail)
                .font(.caption.weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(active ? color : Color.tokenInk.opacity(0.68))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(active ? color.opacity(0.12) : Color.tokenTrack.opacity(0.46), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(active ? color.opacity(0.36) : Color.black.opacity(0.045)))
    }
}
