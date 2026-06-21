import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 22) {
            hero
            todayBreakdownStrip
            metricStrip
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
                        Text(LFormat("/ %@ 每圈", TokenStepFormat.tokens(appState.settings.dailyGoalTokens, compact: true)))
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
                        Text(L("圈数进度"))
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(Color.tokenInk)
                        LapProgressChips(lap: lap)
                    }

                    HStack(spacing: 10) {
                        MetricPill(label: L("消耗金额"), value: TokenStepFormat.money(appState.today.cost))
                        MetricPill(label: L("本月均值"), value: TokenStepFormat.tokens(appState.monthAverage, compact: true))
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var metricStrip: some View {
        HStack(spacing: 18) {
            CompactMetricCard(label: L("累计 Token 消耗"), value: TokenStepFormat.tokens(appState.snapshot.totals.tokens), detail: L("所有本机记录"))
            CompactMetricCard(label: L("活跃天数"), value: localizedDays(appState.snapshot.totals.activeDays), detail: L("有 AI 使用的日期"))
            CompactMetricCard(label: L("达标天数"), value: localizedDays(appState.goalDays), detail: L("达到每日目标"))
        }
    }

    private var todayBreakdownStrip: some View {
        HStack(alignment: .top, spacing: 22) {
            TodayBreakdownCard(title: L("今日客户端"), rows: todayToolRows, maxRows: 3)
            TodayBreakdownCard(title: L("今日模型"), rows: todayModelRows, maxRows: 4)
        }
    }

    private func localizedDays(_ count: Int) -> String {
        TokenStepLocalization.language == .en ? "\(count)d" : "\(count) 天"
    }

    private var todayToolRows: [TodayBreakdownRow] {
        let total = appState.today.totalTokens
        guard total > 0 else { return [] }
        let primaryTools = ["Codex", "Claude Code"]
        let primaryRows = primaryTools.map { name in
            TodayBreakdownRow(
                name: name,
                tokens: appState.today.tools[name] ?? 0,
                percent: Double(appState.today.tools[name] ?? 0) * 100 / Double(total),
                color: tokenToolColor(name)
            )
        }
        let extraRows = appState.today.tools
            .filter { !primaryTools.contains($0.key) && $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { name, tokens in
                TodayBreakdownRow(
                    name: name,
                    tokens: tokens,
                    percent: Double(tokens) * 100 / Double(total),
                    color: tokenToolColor(name)
                )
            }
        return primaryRows + extraRows
    }

    private var todayModelRows: [TodayBreakdownRow] {
        breakdownRows(from: appState.today.models) { _ in nil }
    }

    private func breakdownRows(from values: [String: Int], color: (String) -> Color?) -> [TodayBreakdownRow] {
        let total = appState.today.totalTokens
        guard total > 0 else { return [] }
        return values
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { name, tokens in
                TodayBreakdownRow(
                    name: name,
                    tokens: tokens,
                    percent: Double(tokens) * 100 / Double(total),
                    color: color(name)
                )
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
                LapChip(title: LFormat("%d圈完成", item), detail: TokenStepFormat.tokens(item * lap.safeGoal, compact: true), active: false, color: .tokenGreen)
            }
            LapChip(title: LFormat("%@进行中", lap.lapTitle), detail: lap.lapPercentText, active: true, color: lap.color)
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
