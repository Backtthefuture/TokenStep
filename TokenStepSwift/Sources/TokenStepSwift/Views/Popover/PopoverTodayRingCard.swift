import SwiftUI

struct PopoverTodayRingCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let lap = appState.todayLap
        return VStack(spacing: 10) {
            HStack {
                Text(L("今日消耗"))
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.tokenInk)
                Spacer()
                Text(appState.today.date.suffix(5))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            ZStack {
                ProgressRingView(progress: lap.currentLapProgress, lineWidth: 12, color: lap.ringColor)
                VStack(spacing: 2) {
                    Text(TokenStepFormat.tokens(appState.today.totalTokens, compact: true))
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.tokenInk)
                        .minimumScaleFactor(0.62)
                        .lineLimit(1)
                    Text(LFormat("/ %@", TokenStepFormat.tokens(appState.settings.dailyGoalTokens, compact: true)))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 88)
            }
            .frame(width: 118, height: 118)

            VStack(spacing: 3) {
                Text(lap.lapStatusText)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.tokenInk)
                Text(TokenStepFormat.money(appState.today.cost))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(L("圈数进度，颜色不按来源分段"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
