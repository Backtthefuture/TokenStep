import AppKit
import SwiftUI

struct PopoverPanelView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.isScreenshotRendering) private var isScreenshotRendering

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let error = appState.lastError {
                ErrorBanner(message: error) {
                    appState.clearError()
                }
            }
            PopoverTodayRingCard()
            if appState.settings.showCodexQuota {
                PopoverQuotaCard()
            }
            if appState.settings.showTokenRank {
                PopoverTokenRankCard()
            }
            if let update = appState.availableUpdate {
                UpdateNoticeCard(update: update)
            }
            PopoverFooterView()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .frame(width: 412)
        .background(TokenStepBackdrop())
        .id(appState.appearanceID)
    }

    private var header: some View {
        HStack(spacing: 12) {
            TokenStepMark(size: 40)
            VStack(alignment: .leading, spacing: 0) {
                Text("TokenStep")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.tokenInk)
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
                PopoverCaptureMenuButton(
                    shareTodayAction: { copyShareCard(.today) },
                    shareYesterdayAction: { copyShareCard(.yesterday) },
                    downloadTodayAction: { downloadShareCard(.today) },
                    downloadYesterdayAction: { downloadShareCard(.yesterday) },
                    copyPopoverAction: copyPopoverScreenshot,
                    savePopoverAction: savePopoverScreenshot
                )
            }
        }
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

}

private struct PopoverCaptureMenuButton: View {
    var shareTodayAction: () -> Void
    var shareYesterdayAction: () -> Void
    var downloadTodayAction: () -> Void
    var downloadYesterdayAction: () -> Void
    var copyPopoverAction: () -> Void
    var savePopoverAction: () -> Void

    var body: some View {
        Menu {
            Button {
                shareTodayAction()
            } label: {
                Label(L("分享今日卡片"), systemImage: "sun.max.fill")
            }

            Button {
                shareYesterdayAction()
            } label: {
                Label(L("分享昨日成绩"), systemImage: "calendar.badge.clock")
            }

            Button {
                downloadTodayAction()
            } label: {
                Label(L("下载今日卡片"), systemImage: "arrow.down.circle.fill")
            }

            Button {
                downloadYesterdayAction()
            } label: {
                Label(L("下载昨日成绩"), systemImage: "arrow.down.doc.fill")
            }

            Divider()

            Button {
                copyPopoverAction()
            } label: {
                Label(L("复制浮层截图"), systemImage: "doc.on.clipboard")
            }

            Button {
                savePopoverAction()
            } label: {
                Label(L("保存浮层 PNG"), systemImage: "square.and.arrow.down")
            }
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color.tokenInk.opacity(0.76))
                .frame(width: 34, height: 34)
                .background(Color.tokenSurface, in: Circle())
                .overlay(Circle().stroke(Color.black.opacity(0.07)))
                .shadow(color: Color.black.opacity(0.055), radius: 9, x: 0, y: 5)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help(L("截图与分享"))
        .accessibilityLabel(L("截图与分享"))
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
