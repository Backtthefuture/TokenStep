import AppKit
import SwiftUI

struct PopoverPanelView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let error = appState.lastError {
                ErrorBanner(message: error) {
                    appState.clearError()
                }
            }
            todayCard
            trendCard
            if let update = appState.availableUpdate {
                UpdateNoticeCard(update: update)
            }
            footer
        }
        .padding(20)
        .frame(width: 412)
        .background(TokenStepBackdrop())
    }

    private var header: some View {
        HStack(spacing: 13) {
            TokenStepMark(size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text("TokenStep")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.tokenInk)
                Text("像步数一样记录 AI 使用量")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isRefreshing ? Color.secondary.opacity(0.68) : Color.tokenGreen)
                    .frame(width: 7, height: 7)
                Text(appState.isRefreshing ? "同步中" : "已同步")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.tokenInk.opacity(0.72))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.tokenSurface, in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.055)))
        }
    }

    private var todayCard: some View {
        let lap = appState.todayLap
        return TokenCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("今日 AI 步数")
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
                            Text("/ \(TokenStepFormat.tokens(appState.settings.dailyGoalTokens, compact: true)) 每圈")
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
                            MetricPill(label: "消耗金额", value: TokenStepFormat.money(appState.today.cost))
                            MetricPill(label: "活跃", value: "\(appState.snapshot.totals.activeDays) 天")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var trendCard: some View {
        TokenCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("最近 30 天")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                    Spacer()
                    Text("细线是每日目标")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ActivityBarsView(rows: appState.snapshot.daily, goal: appState.settings.dailyGoalTokens)
                    .frame(height: 66)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("本地统计", systemImage: "checkmark.shield.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(appState.settings.refreshIntervalSeconds == 0 ? "手动刷新" : "刷新 \(TokenStepFormat.intervalLabel(appState.settings.refreshIntervalSeconds))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    MainWindowPresenter.shared.show(appState: appState)
                } label: {
                    Label("打开仪表盘", systemImage: "arrow.up.right")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                colors: [.tokenGreen, .tokenGreenDark],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                        )
                        .shadow(color: Color.tokenGreenDark.opacity(0.22), radius: 12, x: 0, y: 7)
                }
                .buttonStyle(.plain)
                .help("打开仪表盘")

                PopoverActionButton(title: "刷新", symbol: "arrow.clockwise") {
                    appState.refresh()
                }
                .disabled(appState.isRefreshing)

                PopoverActionButton(title: "设置", symbol: "gearshape") {
                    SettingsWindowPresenter.shared.show(appState: appState)
                }

                PopoverActionButton(title: "退出", symbol: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

}

private struct PopoverActionButton: View {
    var title: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .heavy))
                    .frame(height: 20)
                Text(title)
                    .font(.caption2.weight(.heavy))
            }
            .foregroundStyle(Color.tokenInk.opacity(0.78))
            .frame(width: 54, height: 54)
            .background(Color.tokenSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.black.opacity(0.055)))
            .shadow(color: Color.black.opacity(0.045), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct UpdateNoticeCard: View {
    @EnvironmentObject private var appState: AppState
    var update: AvailableUpdate

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(Color.tokenGreen)
                .frame(width: 38, height: 38)
                .background(Color.tokenMint.opacity(0.22), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("发现新版本 \(update.version)")
                    .font(.callout.weight(.heavy))
                    .foregroundStyle(Color.tokenInk)
                Text(update.noteLines.first ?? "内存占用优化与稳定性改进")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                appState.showUpdateDetails()
            } label: {
                Text("立即更新")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.tokenGreen, in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                appState.postponeUpdateNotice()
            } label: {
                Text("稍后")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.tokenInk.opacity(0.64))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.tokenTrack.opacity(0.42), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(13)
        .background(Color.tokenSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.tokenGreen.opacity(0.14)))
        .shadow(color: Color.black.opacity(0.045), radius: 12, x: 0, y: 7)
    }
}
