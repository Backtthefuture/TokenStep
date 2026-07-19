import SwiftUI

struct SettingsDisplayCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsCard(title: L("显示入口"), symbol: "macwindow.badge.plus", height: 268) {
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

struct SettingsExperimentalAgentSourcesCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsCard(title: L("实验 Agent 来源"), symbol: "point.3.connected.trianglepath.dotted", height: 282) {
            VStack(alignment: .leading, spacing: 13) {
                SettingsToggleRow(
                    title: L("启用 ZCode / Hermes"),
                    isOn: Binding(
                        get: { appState.settings.showExperimentalAgentSources },
                        set: { appState.setExperimentalAgentSourcesVisible($0) }
                    )
                )

                Text(L("只读取本地 usage 字段，不读取对话正文。"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    experimentalSourceLine(name: "ZCode", sourceKey: "ZCode")
                    experimentalSourceLine(name: "Hermes Agent", sourceKey: "Hermes Agent")
                    experimentalSourceLine(name: "WorkBuddy", sourceKey: "WorkBuddy")
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func experimentalSourceLine(name: String, sourceKey: String) -> some View {
        let rawStatus = appState.snapshot.sources[sourceKey]?.status
        let status = normalizedExperimentalStatus(rawStatus)
        let active = status == "ok"
        let discoveredOnly = status == "discovered_no_usage"
        return StatusLine(
            symbol: active ? "checkmark.circle.fill" : discoveredOnly ? "magnifyingglass.circle.fill" : "circle.dashed",
            title: name,
            value: statusText(status),
            tint: active ? .tokenGreen : discoveredOnly ? .orange : .gray
        )
    }

    private func normalizedExperimentalStatus(_ status: String?) -> String {
        guard appState.settings.showExperimentalAgentSources else {
            return "disabled"
        }
        if appState.isRefreshing {
            return "refreshing"
        }
        if status == nil || status == "disabled" {
            return "pending_refresh"
        }
        return status ?? "missing"
    }

    private func statusText(_ status: String?) -> String {
        switch status {
        case "ok": return L("已计入实验统计")
        case "discovered_no_usage": return L("已发现，暂不可统计")
        case "refreshing": return L("刷新中")
        case "pending_refresh": return L("等待刷新")
        case "disabled": return L("默认关闭")
        case "missing_db", "missing": return L("未发现数据源")
        case "missing_valid_rows": return L("暂无可用 usage")
        case "schema_mismatch", "schema_unreadable", "missing_table": return L("结构待适配")
        case "unreadable_db": return L("无法读取")
        default: return L("等待同步")
        }
    }
}
