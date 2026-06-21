import SwiftUI

struct SettingsDisplayCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsCard(title: L("显示入口"), symbol: "macwindow.badge.plus") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L("显示位置"))
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                    Text(L("刘海屏显示在刘海旁，其他屏幕使用菜单栏。"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    ForEach(TokenIslandDisplayPlacement.allCases) { placement in
                        DisplayPlacementButton(
                            title: placement.shortTitle,
                            selected: appState.settings.tokenIslandPlacement == placement
                        ) {
                            appState.setTokenIslandPlacement(placement)
                        }
                    }
                }

                StatusLine(
                    symbol: appState.shouldShowTokenIsland ? "circle.dotted.circle.fill" : "menubar.rectangle",
                    title: appState.tokenIslandStatus,
                    value: appState.tokenIslandStatusDetail,
                    tint: appState.shouldShowTokenIsland ? .tokenGreen : .gray
                )

                SettingsToggleRow(
                    title: L("Agent 额度显示"),
                    isOn: Binding(
                        get: { appState.settings.showCodexQuota },
                        set: { appState.setCodexQuotaVisible($0) }
                    )
                )
            }
        }
    }
}

struct SettingsRefreshCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsCard(title: L("自动刷新"), symbol: "arrow.triangle.2.circlepath.circle.fill") {
            VStack(alignment: .leading, spacing: 18) {
                Text(L("菜单栏、弹层和仪表盘会按这个频率同步更新。"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(refreshOptions) { option in
                        RefreshOptionButton(
                            title: option.title,
                            selected: appState.settings.refreshIntervalSeconds == option.seconds
                        ) {
                            appState.setRefreshInterval(option.seconds)
                        }
                    }
                }

                StatusLine(
                    symbol: appState.settings.refreshIntervalSeconds == 0 ? "hand.raised.fill" : "timer",
                    title: L("当前节奏"),
                    value: appState.settings.refreshIntervalSeconds == 0 ? L("手动更新") : LFormat("每 %@", TokenStepFormat.intervalLabel(appState.settings.refreshIntervalSeconds)),
                    tint: .tokenGreen
                )

                Spacer(minLength: 0)
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

struct SettingsTokenRankCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsCard(title: L("生财 Token 榜单"), symbol: "list.number") {
            VStack(alignment: .leading, spacing: 13) {
                SettingsToggleRow(
                    title: L("生财榜单显示"),
                    isOn: Binding(
                        get: { appState.settings.showTokenRank },
                        set: { appState.setTokenRankVisible($0) }
                    )
                )

                if appState.settings.showTokenRank {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("我的生财 userId"))
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Color.tokenInk.opacity(0.72))

                        HStack(spacing: 8) {
                            Image(systemName: "person.text.rectangle")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.tokenGreen)

                            TextField(
                                L("可选，填写后显示我的排名"),
                                text: Binding(
                                    get: { appState.settings.tokenRankUserID },
                                    set: { appState.setTokenRankUserID($0) }
                                )
                            )
                            .textFieldStyle(.plain)
                            .font(.callout.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(Color.tokenTrack.opacity(0.30), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.black.opacity(0.045)))
                    }

                    StatusLine(
                        symbol: "arrow.up.right.circle.fill",
                        title: L("点击卡片"),
                        value: appState.settings.tokenRankUserID.isEmpty ? L("打开榜单页") : L("打开个人页"),
                        tint: .tokenGreen
                    )
                } else {
                    StatusLine(
                        symbol: "eye.slash.fill",
                        title: L("默认关闭"),
                        value: L("不会请求榜单"),
                        tint: .gray
                    )
                }

                Spacer(minLength: 0)
            }
        }
    }
}
