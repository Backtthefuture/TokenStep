import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case today
    case history
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: L("今日")
        case .history: L("历史")
        case .privacy: L("隐私")
        }
    }

    var sidebarTitle: String {
        switch self {
        case .today: L("今日消耗")
        case .history: L("历史活动")
        case .privacy: L("隐私")
        }
    }

    var subtitle: String {
        switch self {
        case .today: L("今天的 Token 使用节奏")
        case .history: L("长期节奏和所有历史记录")
        case .privacy: L("只统计数量，不读取内容")
        }
    }

    var systemImage: String {
        switch self {
        case .today: "figure.walk.circle.fill"
        case .history: "square.grid.3x3.fill"
        case .privacy: "lock.shield.fill"
        }
    }

    var screenshotFilePrefix: String {
        switch self {
        case .today: "today"
        case .history: "history-30d"
        case .privacy: "privacy"
        }
    }

    var saveScreenshotTitle: String {
        switch self {
        case .history: L("保存当前页 PNG（最近 30 天）")
        default: L("保存当前页 PNG")
        }
    }
}

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var navigation: MainWindowNavigation

    var body: some View {
        VStack(spacing: 0) {
            chrome
                .id(appState.appearanceID)
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 1)
            content
                .id(appState.appearanceID)
        }
        .background(TokenStepBackdrop().id(appState.appearanceID))
        .onAppear {
            appState.refreshForForeground()
        }
    }

    private var chrome: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                TokenStepMark(size: 22)
                Text("TokenStep")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.tokenInk)
            }

            Spacer(minLength: 8)

            HStack(spacing: 3) {
                ForEach(AppSection.allCases) { section in
                    DashboardTabButton(
                        title: section.title,
                        selected: navigation.section == section
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            navigation.select(section)
                        }
                    }
                }
            }
            .padding(3)
            .background(Color.tokenTrack.opacity(0.55), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.isRefreshing ? Color.secondary.opacity(0.7) : Color.tokenGreen)
                        .frame(width: 7, height: 7)
                    Text(appState.isRefreshing ? L("同步中") : L("已同步"))
                        .font(.caption.weight(.heavy))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.tokenSurface, in: Capsule())
                .overlay(Capsule().stroke(Color.black.opacity(0.06)))

                Button {
                    appState.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .heavy))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(appState.isRefreshing)
                .help(appState.isRefreshing ? L("同步中") : L("刷新"))

                ScreenshotMenuButton(
                    copyTitle: L("复制当前页截图"),
                    saveTitle: navigation.section.saveScreenshotTitle,
                    help: L("截取当前页"),
                    copyAction: copyCurrentPageScreenshot,
                    saveAction: saveCurrentPageScreenshot
                )

                Button {
                    SettingsWindowPresenter.shared.show(appState: appState)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .heavy))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(L("设置"))
            }
            .foregroundStyle(Color.tokenInk.opacity(0.78))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.tokenSurface.opacity(0.94))
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
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
                detailView
            }
            .padding(16)
            .frame(maxWidth: 1160, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentPageScreenshot: some View {
        DashboardScreenshotView(section: navigation.section)
            .environmentObject(appState)
            .environment(\.isScreenshotRendering, true)
    }

    private func copyCurrentPageScreenshot() {
        do {
            try ScreenshotExporter.copy(currentPageScreenshot)
        } catch {
            appState.lastError = error.localizedDescription
        }
    }

    private func saveCurrentPageScreenshot() {
        do {
            try ScreenshotExporter.save(
                currentPageScreenshot,
                suggestedFileName: ScreenshotExporter.suggestedFileName(prefix: navigation.section.screenshotFilePrefix)
            )
        } catch {
            appState.lastError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch navigation.section {
        case .today:
            TodayView()
        case .history:
            HistoryView()
        case .privacy:
            PrivacyView()
        }
    }
}

private struct DashboardTabButton: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(selected ? Color.tokenInk : Color.tokenInk.opacity(0.55))
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(
                    selected ? Color.tokenSurface : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .shadow(color: selected ? Color.black.opacity(0.07) : .clear, radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
