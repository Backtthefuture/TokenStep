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

    var odysseySurfaceRole: OdysseySurfaceRole {
        switch self {
        case .today: return .dashboard
        case .history: return .history
        case .privacy: return .privacy
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
                .fill(Color.tokenDivider)
                .frame(height: 1)
            content
                .id(appState.appearanceID)
        }
        .background(TokenStepBackdrop(role: navigation.section.odysseySurfaceRole).id(appState.appearanceID))
        .overlay {
            if TokenStepThemeRuntime.isVoyage {
                VoyageWindowFrame(inset: 8)
            } else if TokenStepThemeRuntime.isInterstellar {
                InterstellarWindowFrame(inset: 8)
            }
        }
        .environment(\.colorScheme, appState.settings.theme.colorScheme)
        .onAppear {
            appState.refreshForForeground()
        }
    }

    private var chrome: some View {
        HStack(spacing: 12) {
            TokenStepBrandLockup(markSize: 22, titleSize: 14)

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
                        .fill(appState.isRefreshing ? Color.secondary.opacity(0.7) : Color.tokenSuccess)
                        .frame(width: 7, height: 7)
                    Text(appState.isRefreshing ? L("同步中") : L("已同步"))
                        .font(.caption.weight(.heavy))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.tokenSurface, in: Capsule())
                .overlay(Capsule().stroke(Color.tokenDivider))

                Button {
                    appState.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .heavy))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(appState.isRefreshing)
                .help(appState.isRefreshing ? L("同步中") : L("刷新"))

                DashboardUpdateButton()

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
        .background {
            ZStack {
                Color.tokenSurface.opacity(0.94)
                if TokenStepThemeRuntime.isCinematic {
                    LinearGradient(
                        colors: [Color.tokenGreen.opacity(0.085), Color.clear, Color.tokenGreenDark.opacity(0.03)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
        }
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
                if let update = appState.availableUpdate {
                    UpdateNoticeCard(update: update)
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
            TodayView(openHistory: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    navigation.select(.history)
                }
            })
        case .history:
            HistoryView()
        case .privacy:
            PrivacyView()
        }
    }
}

private struct DashboardUpdateButton: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button {
            appState.showUpdateDetails()
        } label: {
            ZStack {
                if state.isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(state.tint)
                        .scaleEffect(0.72)
                } else {
                    Image(systemName: state.symbol)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(state.tint)
                }

                if state.isAvailable {
                    Circle()
                        .fill(Color.tokenGreen)
                        .frame(width: 4.5, height: 4.5)
                        .offset(x: 8, y: -8)
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.isChecking)
        .help(state.help)
        .accessibilityLabel(state.accessibilityLabel)
    }

    private var state: UpdateActionVisualState {
        appState.updateActionVisualState
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
                    selected
                        ? (TokenStepThemeRuntime.isCinematic ? Color.tokenGreen.opacity(0.16) : Color.tokenSurface)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(selected && TokenStepThemeRuntime.isCinematic ? Color.tokenHairlineStrong : Color.clear)
                )
                .shadow(color: selected ? Color.tokenShadow : .clear, radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
