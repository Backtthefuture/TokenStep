import SwiftUI

struct SettingsGeneralPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                SettingsSectionCard(title: L("每日目标"), subtitle: L("一圈等于多少 Token")) {
                    HStack(spacing: 10) {
                        GoalStepButton(symbol: "minus") {
                            appState.setGoal(appState.settings.dailyGoalTokens - 10_000_000)
                        }
                        .disabled(appState.settings.dailyGoalTokens <= 10_000_000)
                        Text(TokenStepFormat.tokens(appState.settings.dailyGoalTokens, compact: true))
                            .font(.system(size: 27, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.tokenInk)
                            .monospacedDigit()
                            .frame(minWidth: 72)
                        GoalStepButton(symbol: "plus") {
                            appState.setGoal(appState.settings.dailyGoalTokens + 10_000_000)
                        }
                        Spacer()
                        HStack(spacing: 5) {
                            ForEach([50_000_000, 100_000_000, 200_000_000], id: \.self) { value in
                                SettingsPickerChip(
                                    title: TokenStepFormat.tokens(value, compact: true),
                                    selected: appState.settings.dailyGoalTokens == value
                                ) {
                                    appState.setGoal(value)
                                }
                            }
                        }
                    }
                }

                SettingsSectionCard(
                    title: L("历史范围"),
                    subtitle: L("采集与图表回溯天数（7–365）"),
                    badge: L("本版新增入口"),
                    badgeStyle: .ok
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 5) {
                            ForEach([90, 180, 365], id: \.self) { days in
                                SettingsPickerChip(
                                    title: "\(days)",
                                    selected: appState.settings.historyDays == days
                                ) {
                                    appState.setHistoryDays(days)
                                }
                            }
                            SettingsPickerChip(
                                title: "30",
                                selected: appState.settings.historyDays == 30
                            ) {
                                appState.setHistoryDays(30)
                            }
                        }
                        Text(L("调大会增加首次采集耗时。"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                SettingsSectionCard(title: L("外观"), subtitle: L("主题色与语言")) {
                    VStack(spacing: 0) {
                        HStack {
                            Text(L("主题色"))
                                .font(.callout.weight(.semibold))
                            Spacer()
                            HStack(spacing: 6) {
                                ForEach(TokenStepTheme.allCases) { theme in
                                    Button {
                                        appState.setTheme(theme)
                                    } label: {
                                        Circle()
                                            .fill(theme.palette.accent.color)
                                            .frame(width: 22, height: 22)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.tokenInk, lineWidth: appState.settings.theme == theme ? 2 : 0)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .help(theme.title)
                                }
                            }
                        }
                        .padding(.vertical, 9)
                        HStack {
                            Text(L("语言"))
                                .font(.callout.weight(.semibold))
                            Spacer()
                            HStack(spacing: 5) {
                                ForEach(TokenStepLanguage.allCases) { language in
                                    SettingsPickerChip(
                                        title: language.compactTitle,
                                        selected: appState.settings.language == language
                                    ) {
                                        appState.setLanguage(language)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 9)
                        .overlay(alignment: .top) {
                            Rectangle().fill(Color.black.opacity(0.05)).frame(height: 1)
                        }
                    }
                }

                SettingsSectionCard(title: L("显示位置"), subtitle: L("菜单栏或灵动岛，二选一")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L("位置"))
                                .font(.callout.weight(.semibold))
                            Spacer()
                            HStack(spacing: 5) {
                                ForEach(TokenIslandDisplayPlacement.allCases) { placement in
                                    SettingsPickerChip(
                                        title: placement.shortTitle,
                                        selected: appState.settings.tokenIslandPlacement == placement
                                    ) {
                                        appState.setTokenIslandPlacement(placement)
                                    }
                                }
                            }
                        }
                        StatusLine(
                            symbol: appState.shouldShowTokenIsland ? "circle.dotted.circle.fill" : "menubar.rectangle",
                            title: appState.tokenIslandStatus,
                            value: appState.tokenIslandStatusDetail,
                            tint: appState.shouldShowTokenIsland ? .tokenGreen : .gray
                        )
                    }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                SettingsSectionCard(title: L("刷新"), subtitle: L("后台节奏 · 前台打开时总会即时刷")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L("间隔"))
                                .font(.callout.weight(.semibold))
                            Spacer()
                            HStack(spacing: 5) {
                                ForEach(refreshOptions) { option in
                                    SettingsPickerChip(
                                        title: option.title,
                                        selected: appState.settings.refreshIntervalSeconds == option.seconds
                                    ) {
                                        appState.setRefreshInterval(option.seconds)
                                    }
                                }
                            }
                        }
                        SettingsSourceRow(
                            title: L("省电策略"),
                            detail: L("电池或低电量时后台最短 30 分钟"),
                            badge: L("始终启用"),
                            badgeStyle: .ok
                        )
                    }
                }

                SettingsSectionCard(
                    title: L("更新与启动"),
                    subtitle: LFormat("当前版本 %@", UpdateService.currentVersion)
                ) {
                    VStack(spacing: 0) {
                        SettingsToggleRow(
                            title: L("自动检查更新"),
                            isOn: Binding(
                                get: { appState.settings.autoUpdateEnabled },
                                set: { appState.setAutoUpdateEnabled($0) }
                            )
                        )
                        SettingsToggleRow(
                            title: L("下载前询问"),
                            isOn: Binding(
                                get: { appState.settings.askBeforeDownloadingUpdates },
                                set: { appState.setAskBeforeDownloadingUpdates($0) }
                            )
                        )
                        SettingsToggleRow(
                            title: L("仅安装已签名公证版本"),
                            isOn: Binding(
                                get: { appState.settings.requireVerifiedUpdates },
                                set: { appState.setRequireVerifiedUpdates($0) }
                            )
                        )
                        SettingsToggleRow(
                            title: L("开机启动"),
                            isOn: Binding(
                                get: { appState.autostartEnabled },
                                set: { appState.setAutostart($0) }
                            )
                        )
                    }
                }
            }
        }
    }

    private var refreshOptions: [RefreshOption] {
        [
            RefreshOption(seconds: 60, title: L("1 分钟")),
            RefreshOption(seconds: 300, title: LFormat("%d 分钟", 5)),
            RefreshOption(seconds: 900, title: LFormat("%d 分钟", 15)),
            RefreshOption(seconds: 0, title: L("手动"))
        ]
    }
}

