import AppKit
import SwiftUI

struct PopoverPanelView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.isScreenshotRendering) private var isScreenshotRendering
    @State private var odysseyMotionSurfaceVisible = false
    @State private var interstellarMotionMode = InterstellarMotionLabConfiguration.initialMode
    @State private var interstellarManualPulseTrigger = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let quotaSection = CompactPopoverModel.quotaSection(quotas: appState.visibleQuotas, now: Date())
            if !quotaSection.isEmpty {
                section {
                    CompactQuotaSection(section: quotaSection, updatedAt: quotaUpdatedAt)
                }
                sectionDivider
            }
            section {
                CompactTokenSection(usage: appState.today, lap: appState.todayLap)
            }
            if let rank = rankSection, let board = appState.tokenRank {
                sectionDivider
                section {
                    CompactRankSection(section: rank, fetchedAt: board.fetchedAt)
                }
            }
            notices
            footer
        }
        .frame(width: CompactPopoverStyle.width)
        .background {
            if TokenStepThemeRuntime.isInterstellar {
                InterstellarBackdrop(
                    role: .popover,
                    isScreenshotRendering: isScreenshotRendering,
                    motionMode: interstellarMotionMode,
                    tokenActivity: appState.today.totalTokens,
                    manualPulseTrigger: interstellarManualPulseTrigger
                )
            } else if TokenStepThemeRuntime.isVoyage {
                OdysseyPopoverBackdrop(
                    isMotionSurfaceActive: odysseyMotionSurfaceVisible,
                    isScreenshotRendering: isScreenshotRendering
                )
            } else {
                TokenStepBackdrop(role: .popover)
            }
        }
        .background {
            if TokenStepThemeRuntime.isVoyage && !isScreenshotRendering {
                OdysseySurfaceVisibilityReader(isVisible: $odysseyMotionSurfaceVisible)
                    .frame(width: 1, height: 1)
            }
        }
        .overlay {
            if TokenStepThemeRuntime.isVoyage {
                OdysseyPopoverWindowFrame(inset: 7)
            } else if TokenStepThemeRuntime.isInterstellar {
                InterstellarWindowFrame(inset: 7)
            }
        }
        .environment(\.colorScheme, appState.settings.theme.colorScheme)
        .id(appState.appearanceID)
        .onAppear {
            if !isScreenshotRendering {
                appState.refreshForForeground()
            }
        }
        .onDisappear {
            odysseyMotionSurfaceVisible = false
        }
    }

    /// Cinematic themes put each section on a translucent panel so text stays
    /// readable over the artwork; the classic theme draws sections directly.
    @ViewBuilder
    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if TokenStepThemeRuntime.isCinematic {
            content()
                .padding(12)
                .background {
                    if TokenStepThemeRuntime.isInterstellar {
                        InterstellarPanelBackground(opacity: 0.72, cornerRadius: 14)
                    } else {
                        OdysseyPopoverSectionBackground(opacity: 0.56, cornerRadius: 14)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 10)
                .padding(.top, 10)
        } else {
            content()
                .padding(.horizontal, CompactPopoverStyle.horizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var sectionDivider: some View {
        if !TokenStepThemeRuntime.isCinematic {
            Rectangle()
                .fill(Color.tokenDivider)
                .frame(height: 1)
                .padding(.horizontal, CompactPopoverStyle.horizontalPadding)
        }
    }

    private var quotaUpdatedAt: Date? {
        appState.visibleQuotas.compactMap(\.fetchedAt).max()
    }

    private var rankSection: CompactPopoverModel.RankSection? {
        guard appState.shouldShowAgentWorkRank,
              let identity = appState.agentWorkRankIdentity,
              let board = appState.tokenRank
        else {
            return nil
        }
        let now = Date()
        let buckets = appState.snapshot.rhythm(for: appState.today.date)?.buckets ?? []
        return CompactPopoverModel.rankSection(
            board: board,
            myUserID: identity.id,
            localTodayTokens: appState.today.totalTokens,
            tokensPerHour: CompactPopoverModel.tokensInLastHour(buckets: buckets, now: now, calendar: TokenStepClock.calendar),
            localTimeZoneIdentifier: TokenStepClock.identifier
        )
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Button {
                appState.refreshNow()
            } label: {
                Group {
                    if appState.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(appState.isRefreshing)
            .help(appState.isRefreshing ? L("同步中") : L("刷新"))
            .accessibilityLabel(L("刷新"))

            Button {
                MainWindowPresenter.shared.show(appState: appState)
            } label: {
                Label(L("打开仪表盘"), systemImage: "rectangle.on.rectangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.tokenGreenDark)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Color.tokenGreen.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            Text(appState.settings.refreshIntervalSeconds == 0
                ? L("手动刷新")
                : LFormat("刷新 %@", TokenStepFormat.intervalLabel(appState.settings.refreshIntervalSeconds)))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if appState.availableUpdate != nil || appState.isCheckingForUpdates {
                let update = appState.updateActionVisualState
                Button {
                    appState.showUpdateDetails()
                } label: {
                    Image(systemName: update.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(update.tint)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(update.isChecking)
                .help(update.help)
                .accessibilityLabel(update.accessibilityLabel)
            }

            Button {
                SettingsWindowPresenter.shared.show(appState: appState)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("设置"))
            .accessibilityLabel(L("设置"))

            if !isScreenshotRendering {
                moreMenu
            }
        }
        .foregroundStyle(Color.tokenInk.opacity(0.78))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(TokenStepThemeRuntime.isCinematic ? Color.clear : Color.tokenCanvas.opacity(0.6))
        .overlay(alignment: .top) {
            if !TokenStepThemeRuntime.isCinematic {
                Rectangle().fill(Color.tokenDivider).frame(height: 1)
            }
        }
        .padding(.top, TokenStepThemeRuntime.isCinematic ? 6 : 0)
    }

    private var moreMenu: some View {
        Menu {
            Section(L("分享")) {
                Button(L("分享昨日节奏"), systemImage: "waveform.path.ecg") { copyYesterdayRhythmCard() }
                Button(L("分享昨日成绩"), systemImage: "calendar.badge.clock") { copyShareCard(.yesterday) }
                Button(L("分享今日卡片"), systemImage: "sun.max.fill") { copyShareCard(.today) }
                Button(L("下载昨日节奏"), systemImage: "arrow.down.heart.fill") { downloadYesterdayRhythmCard() }
                Button(L("下载今日卡片"), systemImage: "arrow.down.circle.fill") { downloadShareCard(.today) }
            }
            Section(L("截图")) {
                Button(L("复制浮层截图"), systemImage: "doc.on.clipboard") { copyPopoverScreenshot() }
                Button(L("保存浮层 PNG"), systemImage: "square.and.arrow.down") { savePopoverScreenshot() }
            }
            if TokenStepThemeRuntime.isInterstellar, InterstellarMotionLabConfiguration.isEnabled {
                Picker(L("引力动效"), selection: $interstellarMotionMode) {
                    ForEach(InterstellarMotionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Button(L("触发坠落脉冲"), systemImage: "waveform") { interstellarManualPulseTrigger &+= 1 }
            }
            Divider()
            Button(L("退出 TokenStep"), systemImage: "power") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help(L("更多"))
        .accessibilityLabel(L("更多：分享、截图、退出"))
    }

    @ViewBuilder
    private var notices: some View {
        VStack(spacing: 8) {
            if let error = appState.lastError {
                ErrorBanner(message: error) {
                    appState.clearError()
                }
            }
            if appState.showsUsageRecalibrationNotice {
                UsageRecalibrationNotice {
                    appState.dismissUsageRecalibrationNotice()
                }
            }
            if let update = appState.availableUpdate {
                UpdateNoticeCard(update: update)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, appState.lastError == nil && !appState.showsUsageRecalibrationNotice && appState.availableUpdate == nil ? 0 : 10)
    }

    private func copyShareCard(_ mode: ShareCardMode) {
        guard let day = shareDay(for: mode) else {
            appState.lastError = mode == .yesterday ? L("还没有昨日数据") : L("等待下一次同步")
            return
        }

        do {
            try ScreenshotExporter.copy(
                ShareDailyCardView(
                    mode: mode,
                    day: day,
                    previousDay: previousDay(before: day)
                )
                .environmentObject(appState)
                .environment(\.isScreenshotRendering, true)
            )
        } catch {
            appState.lastError = error.localizedDescription
        }
    }

    private func downloadShareCard(_ mode: ShareCardMode) {
        guard let day = shareDay(for: mode) else {
            appState.lastError = mode == .yesterday ? L("还没有昨日数据") : L("等待下一次同步")
            return
        }

        do {
            try ScreenshotExporter.saveJPGToDownloads(
                ShareDailyCardView(
                    mode: mode,
                    day: day,
                    previousDay: previousDay(before: day)
                )
                .environmentObject(appState)
                .environment(\.isScreenshotRendering, true)
            )
        } catch {
            appState.lastError = error.localizedDescription
        }
    }

    private func copyYesterdayRhythmCard() {
        guard let payload = yesterdayRhythmPayload() else { return }

        do {
            try ScreenshotExporter.copy(
                ShareRhythmCardView(
                    day: payload.day,
                    rhythm: payload.rhythm,
                    previousDay: payload.previousDay
                )
                .environmentObject(appState)
                .environment(\.isScreenshotRendering, true)
            )
        } catch {
            appState.lastError = error.localizedDescription
        }
    }

    private func downloadYesterdayRhythmCard() {
        guard let payload = yesterdayRhythmPayload() else { return }

        do {
            try ScreenshotExporter.saveJPGToDownloads(
                ShareRhythmCardView(
                    day: payload.day,
                    rhythm: payload.rhythm,
                    previousDay: payload.previousDay
                )
                .environmentObject(appState)
                .environment(\.isScreenshotRendering, true)
            )
        } catch {
            appState.lastError = error.localizedDescription
        }
    }

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

    private func shareDay(for mode: ShareCardMode) -> DailyUsage? {
        switch mode {
        case .today:
            return appState.today.totalTokens > 0 ? appState.today : nil
        case .yesterday:
            let calendar = Calendar(identifier: .gregorian)
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) else {
                return nil
            }
            let key = DateFormatter.tokenStepDay.string(from: yesterday)
            return appState.snapshot.daily.first(where: { $0.date == key && $0.totalTokens > 0 })
        }
    }

    private func previousDay(before day: DailyUsage) -> DailyUsage? {
        let rows = appState.snapshot.daily.sorted { $0.date < $1.date }
        guard let index = rows.firstIndex(where: { $0.date == day.date }), index > rows.startIndex else {
            return nil
        }
        return rows[rows.index(before: index)]
    }

    private func yesterdayRhythmPayload() -> (day: DailyUsage, rhythm: DailyRhythm, previousDay: DailyUsage?)? {
        guard let day = shareDay(for: .yesterday) else {
            appState.lastError = L("还没有昨日数据")
            return nil
        }
        guard let rhythm = appState.snapshot.rhythm(for: day.date) else {
            appState.lastError = L("昨日节奏还在等待同步")
            return nil
        }
        return (day, rhythm, previousDay(before: day))
    }
}
