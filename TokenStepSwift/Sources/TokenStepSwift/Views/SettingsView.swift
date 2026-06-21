import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.isScreenshotRendering) private var isScreenshotRendering
    var captureMode = false

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

            ScrollView(.vertical, showsIndicators: false) {
                settingsContent
                    .padding(.top, 36)
                    .padding(.horizontal, 34)
                    .padding(.bottom, 24)
            }
        }
        .frame(width: 920, height: 760)
    }

    private var captureBody: some View {
        ZStack {
            TokenStepBackdrop()
            settingsContent
                .padding(.top, 36)
                .padding(.horizontal, 34)
                .padding(.bottom, 24)
        }
        .frame(width: 920)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            cardGrid
            footer
        }
    }

    private var cardGrid: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                SettingsGoalCard()
                SettingsThemeCard()
            }
            HStack(alignment: .top, spacing: 18) {
                SettingsLanguageCard()
                SettingsDisplayCard()
            }
            HStack(alignment: .top, spacing: 18) {
                SettingsTokenRankCard()
                SettingsRefreshCard()
            }
            HStack(alignment: .top, spacing: 18) {
                SettingsUpdateCard()
                SettingsAutostartCard()
            }
            HStack(alignment: .top, spacing: 18) {
                SettingsPrivacyCard()
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            TokenStepMark(size: 54)

            VStack(alignment: .leading, spacing: 5) {
                Text(L("设置"))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.tokenInk)
                Text(L("让 TokenStep 按你的节奏记录 Token 消耗"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(Color.tokenGreen)
                    .frame(width: 8, height: 8)
                Text(L("本地统计"))
                    .font(.callout.weight(.heavy))
                    .foregroundStyle(Color.tokenGreenDark)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(Color.tokenMint.opacity(0.22), in: Capsule())
            .overlay(Capsule().stroke(Color.tokenGreen.opacity(0.12)))

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
                appState.setGoal(TokenStepSettings.defaults.dailyGoalTokens)
                appState.setRefreshInterval(TokenStepSettings.defaults.refreshIntervalSeconds)
                appState.setTheme(TokenStepSettings.defaults.theme)
                appState.setLanguage(TokenStepSettings.defaults.language)
                appState.setAutoUpdateEnabled(TokenStepSettings.defaults.autoUpdateEnabled)
                appState.setAskBeforeDownloadingUpdates(TokenStepSettings.defaults.askBeforeDownloadingUpdates)
                appState.setRequireVerifiedUpdates(TokenStepSettings.defaults.requireVerifiedUpdates)
                appState.setTokenIslandPlacement(TokenStepSettings.defaults.tokenIslandPlacement)
                appState.setCodexQuotaVisible(TokenStepSettings.defaults.showCodexQuota)
                appState.setTokenRankVisible(TokenStepSettings.defaults.showTokenRank)
                appState.setTokenRankUserID(TokenStepSettings.defaults.tokenRankUserID)
                appState.setAutostart(true)
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
    }

}
