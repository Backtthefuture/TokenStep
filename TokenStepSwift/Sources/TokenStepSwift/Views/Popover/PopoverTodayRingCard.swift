import SwiftUI

struct PopoverTodayRingCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let lap = appState.todayLap
        return TokenCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L("今日 Token 消耗"))
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                    Spacer()
                    Text(appState.today.date)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 20) {
                    ZStack {
                        ProgressRingView(progress: lap.currentLapProgress, lineWidth: 16, color: lap.color)
                        VStack(spacing: 3) {
                            Text(TokenStepFormat.tokens(appState.today.totalTokens))
                                .font(.system(size: 31, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.tokenInk)
                                .minimumScaleFactor(0.52)
                                .lineLimit(1)
                            Text(LFormat("/ %@ 每圈", TokenStepFormat.tokens(appState.settings.dailyGoalTokens, compact: true)))
                                .font(.callout.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 122)
                    }
                    .frame(width: 148, height: 148)

                    VStack(alignment: .leading, spacing: 11) {
                        Text(lap.lapTitle)
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(Color.tokenInk)
                        Text(lap.lapPercentText)
                            .font(.system(size: 43, weight: .heavy, design: .rounded))
                            .foregroundStyle(lap.color)
                            .monospacedDigit()
                        Text(lap.completedLapsText)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            MetricPill(label: L("消耗金额"), value: TokenStepFormat.money(appState.today.cost))
                            MetricPill(label: L("活跃"), value: localizedDays(appState.snapshot.totals.activeDays))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !todaySourceRows.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L("今日来源"))
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            ForEach(todaySourceRows.indices, id: \.self) { index in
                                let row = todaySourceRows[index]
                                if index > 0 {
                                    Divider()
                                        .frame(height: 30)
                                }
                                TodaySourceMetric(name: row.name, tokens: row.tokens)
                            }
                        }
                    }
                    .padding(.top, 1)
                }
            }
        }
    }

    private func localizedDays(_ count: Int) -> String {
        TokenStepLocalization.language == .en ? "\(count)d" : "\(count) 天"
    }

    private var todaySourceRows: [(name: String, tokens: Int)] {
        var rows = appState.today.tools
            .filter { $0.value > 0 }
            .map { (name: $0.key, tokens: $0.value) }
            .sorted { $0.tokens > $1.tokens }
        guard rows.count > 3 else { return rows }

        var selected = Array(rows.prefix(3))
        if let workBuddy = rows.first(where: { $0.name == "WorkBuddy" }),
           !selected.contains(where: { $0.name == "WorkBuddy" }) {
            selected[2] = workBuddy
        }
        rows = selected.sorted { $0.tokens > $1.tokens }
        return rows
    }
}

private struct TodaySourceMetric: View {
    var name: String
    var tokens: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tokenToolColor(name))
                    .frame(width: 6, height: 6)
                Text(displayName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(TokenStepFormat.tokens(tokens, compact: true))
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.tokenInk.opacity(0.82))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayName: String {
        name == "Claude Code" ? "Claude" : name
    }
}
