import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case appearance
    case dataSources
    case quotas
    case tokenRank

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L("通用")
        case .appearance: L("外观")
        case .dataSources: L("数据源")
        case .quotas: L("额度")
        case .tokenRank: "Token Rank"
        }
    }

    var subtitle: String {
        switch self {
        case .general: L("改动立即生效，不需要保存。")
        case .appearance: L("主题和配色，随时切换。")
        case .dataSources: L("只读取本机日志里的用量数字，不读对话内容。")
        case .quotas: L("读取订阅的剩余额度，显示在面板顶部。密钥只存进钥匙串。")
        case .tokenRank: L("在面板里显示你在 Token Rank 公开榜单上的排名。")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintpalette.fill"
        case .dataSources: "externaldrive.fill"
        case .quotas: "gauge.with.dots.needle.50percent"
        case .tokenRank: "trophy.fill"
        }
    }

    var tileColor: Color {
        switch self {
        case .general: Color(red: 0.54, green: 0.54, blue: 0.58)
        case .appearance: Color(red: 0.48, green: 0.36, blue: 1.0)
        case .dataSources: Color(red: 0.23, green: 0.44, blue: 0.85)
        case .quotas: Color(red: 0.88, green: 0.54, blue: 0.18)
        case .tokenRank: Color(red: 0.18, green: 0.62, blue: 0.36)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.isScreenshotRendering) private var isScreenshotRendering
    var captureMode: Bool
    /// In capture mode, render only this pane beside the sidebar; nil stacks
    /// every pane (the full settings screenshot).
    var capturePane: SettingsPane?
    @State private var pane: SettingsPane

    init(captureMode: Bool = false, initialPane: SettingsPane = .general, capturePane: SettingsPane? = nil) {
        self.captureMode = captureMode
        self.capturePane = capturePane
        _pane = State(initialValue: capturePane ?? initialPane)
    }

    var body: some View {
        Group {
            if captureMode {
                captureBody
            } else {
                windowBody
            }
        }
        .environment(\.colorScheme, appState.settings.theme.colorScheme)
        .id(appState.appearanceID)
    }

    private var windowBody: some View {
        HStack(spacing: 0) {
            sidebar
            ZStack {
                TokenStepBackdrop(role: .settings)
                ScrollView(.vertical, showsIndicators: false) {
                    page(pane)
                        .padding(.horizontal, 36)
                        .padding(.top, 34)
                        .padding(.bottom, 28)
                        .frame(maxWidth: 720, alignment: .leading)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(minWidth: 920, minHeight: 700)
        .overlay {
            if TokenStepThemeRuntime.isVoyage {
                VoyageWindowFrame(inset: 8)
            } else if TokenStepThemeRuntime.isInterstellar {
                InterstellarWindowFrame(inset: 8)
            }
        }
    }

    private var captureBody: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
            ZStack(alignment: .top) {
                TokenStepBackdrop(role: .settings)
                VStack(alignment: .leading, spacing: 36) {
                    if let capturePane {
                        page(capturePane)
                    } else {
                        ForEach(SettingsPane.allCases) { item in
                            page(item)
                        }
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 34)
            }
        }
        .frame(width: 920)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Room for the window's traffic lights.
            Color.clear.frame(height: 40)
            ForEach(SettingsPane.allCases) { item in
                SettingsSidebarItem(pane: item, selected: item == pane && (!captureMode || capturePane != nil)) {
                    withAnimation(.easeOut(duration: 0.16)) {
                        pane = item
                    }
                }
            }
            Spacer(minLength: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(LFormat("TokenStep %@", UpdateService.currentVersion))
                Text(L("只在本机统计，不上传用量"))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.tokenHairline).frame(height: 1)
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 12)
        .frame(width: 214)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            TokenStepThemeRuntime.isCinematic
                ? Color.tokenSurface.opacity(0.7)
                : Color(nsColor: .windowBackgroundColor).opacity(0.94)
        )
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.tokenHairline).frame(width: 1)
        }
    }

    // MARK: Pages

    private func page(_ item: SettingsPane) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.tokenInk)
                    Text(item.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !isScreenshotRendering && !captureMode && item == pane {
                    ScreenshotMenuButton(
                        copyTitle: L("复制设置截图"),
                        saveTitle: L("保存设置 PNG"),
                        help: L("截取设置页"),
                        copyAction: copySettingsScreenshot,
                        saveAction: saveSettingsScreenshot
                    )
                }
            }
            paneContent(item)
            if item == .general {
                HStack {
                    Spacer()
                    Button(L("恢复默认设置")) { resetDefaults() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func paneContent(_ item: SettingsPane) -> some View {
        switch item {
        case .general:
            SettingsGeneralPane()
        case .appearance:
            SettingsAppearancePane()
        case .dataSources:
            SettingsDataSourcesPane {
                withAnimation(.easeOut(duration: 0.18)) {
                    pane = .quotas
                }
            }
        case .quotas:
            SettingsQuotaProvidersPane()
        case .tokenRank:
            SettingsTokenRankCard()
        }
    }

    // MARK: Screenshot and reset

    private var settingsScreenshot: some View {
        SettingsView(captureMode: true)
            .environmentObject(appState)
            .environment(\.isScreenshotRendering, true)
    }

    private func copySettingsScreenshot() {
        do {
            try ScreenshotExporter.copy(settingsScreenshot)
        } catch {
            appState.lastError = error.localizedDescription
        }
    }

    private func saveSettingsScreenshot() {
        do {
            try ScreenshotExporter.save(
                settingsScreenshot,
                suggestedFileName: ScreenshotExporter.suggestedFileName(prefix: "settings")
            )
        } catch {
            appState.lastError = error.localizedDescription
        }
    }

    private func resetDefaults() {
        appState.setGoal(TokenStepSettings.defaults.dailyGoalTokens)
        appState.setRefreshInterval(TokenStepSettings.defaults.refreshIntervalSeconds)
        appState.setClassicTheme(TokenStepSettings.defaults.classicTheme)
        appState.setOdysseyChapter(TokenStepSettings.defaults.odysseyChapter)
        appState.setThemePack(TokenStepSettings.defaults.themePack)
        appState.setLanguage(TokenStepSettings.defaults.language)
        appState.setAutoUpdateEnabled(TokenStepSettings.defaults.autoUpdateEnabled)
        appState.setAskBeforeDownloadingUpdates(TokenStepSettings.defaults.askBeforeDownloadingUpdates)
        appState.setRequireVerifiedUpdates(TokenStepSettings.defaults.requireVerifiedUpdates)
        appState.setTokenIslandPlacement(TokenStepSettings.defaults.tokenIslandPlacement)
        appState.setCodexQuotaVisible(false)
        for provider in QuotaProviderID.allCases {
            appState.setQuotaProvider(provider, enabled: false, confirmNetworkAccess: false)
        }
        appState.setCursorCodeSignalEnabled(false)
        appState.setHistoryDays(TokenStepSettings.defaults.historyDays)
        appState.setAgentWorkRankVisibility(TokenStepSettings.defaults.agentWorkRankVisibility)
        appState.setExperimentalAgentSourcesVisible(TokenStepSettings.defaults.showExperimentalAgentSources)
        appState.setAutostart(true)
    }
}

private struct SettingsSidebarItem: View {
    var pane: SettingsPane
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(pane.tileColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(pane.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.tokenGreenDark : Color.tokenInk.opacity(0.85))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(
                selected ? Color.tokenGreen.opacity(0.13) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
