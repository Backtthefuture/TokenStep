import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case dataSources
    case quotas
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dataSources: L("数据源")
        case .quotas: L("额度")
        case .general: L("通用")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.isScreenshotRendering) private var isScreenshotRendering
    var captureMode = false
    @State private var pane: SettingsPane = .dataSources

    var body: some View {
        Group {
            if captureMode {
                captureBody
            } else {
                windowBody
            }
        }
        .id(appState.appearanceID)
    }

    private var windowBody: some View {
        ZStack {
            TokenStepBackdrop()
            VStack(spacing: 0) {
                header
                    .padding(.top, 28)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 14)
                ScrollView(.vertical, showsIndicators: false) {
                    paneContent
                        .padding(.horizontal, 22)
                        .padding(.bottom, 16)
                }
                footer
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
            }
        }
        .frame(width: 920, height: 760)
    }

    private var captureBody: some View {
        ZStack {
            TokenStepBackdrop()
            VStack(alignment: .leading, spacing: 18) {
                header
                SettingsDataSourcesPane(openQuotaTab: {})
                SettingsQuotaProvidersPane()
                SettingsGeneralPane()
                footer
            }
            .padding(.top, 28)
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
        .frame(width: 920)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var paneContent: some View {
        switch pane {
        case .dataSources:
            SettingsDataSourcesPane {
                withAnimation(.easeOut(duration: 0.18)) {
                    pane = .quotas
                }
            }
        case .quotas:
            SettingsQuotaProvidersPane()
        case .general:
            SettingsGeneralPane()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            TokenStepMark(size: 28)
            Text(L("设置"))
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.tokenInk)

            Spacer()

            HStack(spacing: 3) {
                ForEach(SettingsPane.allCases) { item in
                    DashboardSettingsTab(title: item.title, selected: pane == item) {
                        withAnimation(.easeOut(duration: 0.16)) {
                            pane = item
                        }
                    }
                }
            }
            .padding(3)
            .background(Color.tokenTrack.opacity(0.55), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            if !isScreenshotRendering && !captureMode {
                ScreenshotMenuButton(
                    copyTitle: L("复制设置截图"),
                    saveTitle: L("保存设置 PNG"),
                    help: L("截取设置页"),
                    copyAction: copySettingsScreenshot,
                    saveAction: saveSettingsScreenshot
                )
            }
        }
    }

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

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("TokenStep · Local usage tracker"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(LFormat("当前版本 %@", UpdateService.currentVersion))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary.opacity(0.82))
            }

            Spacer()

            Button {
                resetDefaults()
            } label: {
                Text(L("恢复默认"))
                    .font(.callout.weight(.bold))
                    .frame(width: 92, height: 36)
            }
            .buttonStyle(SettingsSecondaryButtonStyle())

            Button {
                SettingsWindowPresenter.shared.close()
                NSApp.keyWindow?.close()
            } label: {
                Text(L("完成"))
                    .font(.callout.weight(.heavy))
                    .frame(width: 82, height: 36)
            }
            .buttonStyle(SettingsPrimaryButtonStyle())
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 1)
        }
    }

    private func resetDefaults() {
        appState.setGoal(TokenStepSettings.defaults.dailyGoalTokens)
        appState.setRefreshInterval(TokenStepSettings.defaults.refreshIntervalSeconds)
        appState.setTheme(TokenStepSettings.defaults.theme)
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

private struct DashboardSettingsTab: View {
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
    }
}
