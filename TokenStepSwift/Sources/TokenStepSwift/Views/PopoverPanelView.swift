import AppKit
import SwiftUI

struct PopoverPanelView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.isScreenshotRendering) private var isScreenshotRendering

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let error = appState.lastError {
                ErrorBanner(message: error) {
                    appState.clearError()
                }
            }
            todayCard
            codexQuotaCard
            trendCard
            if let update = appState.availableUpdate {
                UpdateNoticeCard(update: update)
            }
            footer
        }
        .padding(20)
        .frame(width: 412)
        .background(TokenStepBackdrop())
        .id(appState.settings.theme.id)
    }

    private var header: some View {
        HStack(spacing: 13) {
            TokenStepMark(size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text("TokenStep")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.tokenInk)
                Text(L("每日 Token 消耗追踪"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isRefreshing ? Color.secondary.opacity(0.68) : Color.tokenGreen)
                    .frame(width: 7, height: 7)
                Text(appState.isRefreshing ? L("同步中") : L("已同步"))
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.tokenInk.opacity(0.72))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.tokenSurface, in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.055)))

            if !isScreenshotRendering {
                ScreenshotMenuButton(
                    copyTitle: L("复制浮层截图"),
                    saveTitle: L("保存浮层 PNG"),
                    help: L("截取浮层"),
                    copyAction: copyPopoverScreenshot,
                    saveAction: savePopoverScreenshot
                )
            }
        }
    }

    private var todayCard: some View {
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
            }
        }
    }

    private var trendCard: some View {
        TokenCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L("最近 30 天"))
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                    Spacer()
                    Text(L("细线是每日目标"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ActivityBarsView(rows: appState.snapshot.daily, goal: appState.settings.dailyGoalTokens)
                    .frame(height: 66)
            }
        }
    }

    private var codexQuotaCard: some View {
        TokenCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Self.codexBlue)
                        .frame(width: 8, height: 8)
                    Text(L("Codex 剩余额度"))
                        .font(.callout.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                    Spacer()
                    if appState.isRefreshingCodexQuota {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.72)
                    } else if let fetchedAt = appState.codexQuota.fetchedAt {
                        Text(quotaFetchedText(fetchedAt))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }

                if appState.codexQuota.isAvailable {
                    VStack(spacing: 10) {
                        quotaRow(appState.codexQuota.fiveHour, fallbackTitle: L("5 小时"))
                        quotaRow(appState.codexQuota.sevenDay, fallbackTitle: L("7 天"))
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "terminal")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Self.codexBlue)
                            .frame(width: 28, height: 28)
                            .background(Self.codexBlue.opacity(0.10), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("暂未读取到 Codex 额度"))
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(Color.tokenInk.opacity(0.76))
                            Text(L("打开并登录 Codex 后会自动显示额度。"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.vertical, -2)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(L("本地统计"), systemImage: "checkmark.shield.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(appState.settings.refreshIntervalSeconds == 0 ? L("手动刷新") : LFormat("刷新 %@", TokenStepFormat.intervalLabel(appState.settings.refreshIntervalSeconds)))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    MainWindowPresenter.shared.show(appState: appState)
                } label: {
                    Label(L("打开仪表盘"), systemImage: "arrow.up.right")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.tokenGreen, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .shadow(color: Color.tokenGreenDark.opacity(0.14), radius: 10, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .help(L("打开仪表盘"))

                PopoverActionButton(title: L("刷新"), symbol: "arrow.clockwise") {
                    appState.refresh()
                }
                .disabled(appState.isRefreshing)

                PopoverActionButton(title: L("设置"), symbol: "gearshape") {
                    SettingsWindowPresenter.shared.show(appState: appState)
                }

                PopoverActionButton(title: L("退出"), symbol: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private func localizedDays(_ count: Int) -> String {
        TokenStepLocalization.language == .en ? "\(count)d" : "\(count) 天"
    }

    private func quotaRow(_ window: CodexQuotaWindow?, fallbackTitle: String) -> some View {
        HStack(spacing: 10) {
            Text(window?.title ?? fallbackTitle)
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.tokenInk.opacity(0.72))
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(window.map { LFormat("剩余 %@", TokenStepFormat.percent($0.remainingPercent)) } ?? L("等待同步"))
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(window == nil ? .secondary : Color.tokenInk.opacity(0.82))
                    Spacer()
                    Text(window.map { quotaResetText($0.resetsAt) } ?? L("等待重置"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Self.codexBlue.opacity(0.10))
                        if let window {
                            Capsule()
                                .fill(Self.codexBlue)
                                .frame(width: max(5, proxy.size.width * window.remainingPercent / 100))
                        }
                    }
                }
                .frame(height: 6)
            }
        }
    }

    private func quotaResetText(_ date: Date?) -> String {
        guard let date else { return L("等待重置") }
        let seconds = max(0, Int(date.timeIntervalSinceNow.rounded()))
        if seconds < 60 {
            return L("即将重置")
        }
        if seconds < 3_600 {
            return LFormat("%d 分后重置", max(1, seconds / 60))
        }
        if seconds < 86_400 {
            let hours = seconds / 3_600
            let minutes = (seconds % 3_600) / 60
            return LFormat("约 %d:%02d 后重置", hours, minutes)
        }
        let days = max(1, Int(ceil(Double(seconds) / 86_400)))
        return LFormat("%d 天后重置", days)
    }

    private func quotaFetchedText(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date).rounded()))
        if seconds < 60 {
            return L("刚刚")
        }
        return LFormat("%d 分钟前", max(1, seconds / 60))
    }

    private static let codexBlue = Color(red: 39 / 255, green: 111 / 255, blue: 246 / 255)

    private var popoverScreenshot: some View {
        PopoverPanelView()
            .environmentObject(appState)
            .environment(\.isScreenshotRendering, true)
    }

    private func copyPopoverScreenshot() {
        do {
            try ScreenshotExporter.copy(popoverScreenshot)
        } catch {
            appState.lastError = error.localizedDescription
        }
    }

    private func savePopoverScreenshot() {
        do {
            try ScreenshotExporter.save(
                popoverScreenshot,
                suggestedFileName: ScreenshotExporter.suggestedFileName(prefix: "popover")
            )
        } catch {
            appState.lastError = error.localizedDescription
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
                Text(LFormat("发现新版本 %@", update.version))
                    .font(.callout.weight(.heavy))
                    .foregroundStyle(Color.tokenInk)
                Text(update.noteLines.first ?? L("内存占用优化与稳定性改进"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                appState.showUpdateDetails()
            } label: {
                Text(L("立即更新"))
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
                Text(L("稍后"))
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
