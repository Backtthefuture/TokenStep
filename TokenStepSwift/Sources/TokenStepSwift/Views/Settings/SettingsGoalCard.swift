import SwiftUI

struct SettingsGoalCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsCard(title: L("每日目标"), symbol: "figure.walk.circle.fill") {
            HStack(alignment: .center, spacing: 18) {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        ProgressRingView(progress: min(appState.progress, 1), lineWidth: 8)
                            .frame(width: 68, height: 68)
                        Text(TokenStepFormat.percent(min(appState.progress * 100, 999)))
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.tokenInk)
                            .monospacedDigit()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(TokenStepFormat.tokens(appState.settings.dailyGoalTokens))
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.tokenInk)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            Text(L("token / 天"))
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            GoalStepButton(symbol: "minus") {
                                appState.setGoal(appState.settings.dailyGoalTokens - 10_000_000)
                            }
                            .disabled(appState.settings.dailyGoalTokens <= 10_000_000)

                            GoalStepButton(symbol: "plus") {
                                appState.setGoal(appState.settings.dailyGoalTokens + 10_000_000)
                            }
                        }
                    }
                }

                Spacer(minLength: 8)

                LazyVGrid(columns: presetColumns, spacing: 8) {
                    ForEach(goalPresets, id: \.self) { value in
                        PresetChip(
                            title: TokenStepFormat.tokens(value),
                            selected: appState.settings.dailyGoalTokens == value
                        ) {
                            appState.setGoal(value)
                        }
                    }
                }
                .frame(width: 178)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var goalPresets: [Int] {
        [50_000_000, 100_000_000, 200_000_000, 300_000_000, 500_000_000, 1_000_000_000]
    }

    private var presetColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 7), count: 3)
    }
}
