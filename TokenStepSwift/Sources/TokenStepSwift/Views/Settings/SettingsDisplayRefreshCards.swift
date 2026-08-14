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
                Text(L("面板可见时按此频率检查；后台会根据供电状态降低频率。"))
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
        SettingsCard(title: L("Agent 消耗榜"), symbol: "list.number", height: 282) {
            VStack(alignment: .leading, spacing: 13) {
                // 注意：segmented Picker 必须用非空标题且不用 labelsHidden——
                // macOS 15 下空标题/labelsHidden 会连分段文字一起隐藏（渲染实测）。
                Picker(L("榜单可见性"), selection: Binding(
                    get: { appState.settings.agentWorkRankVisibility },
                    set: { appState.setAgentWorkRankVisibility($0) }
                )) {
                    Text(L("自动")).tag(AgentWorkRankVisibility.automatic)
                    Text(L("显示")).tag(AgentWorkRankVisibility.visible)
                    Text(L("隐藏")).tag(AgentWorkRankVisibility.hidden)
                }
                .pickerStyle(.segmented)

                StatusLine(
                    symbol: statusSymbol,
                    title: statusTitle,
                    value: statusValue,
                    tint: statusTint
                )

                if !appState.shouldShowAgentWorkRank {
                    // 隐藏态说明：解释本卡用途与隐私默认，避免大片空白。
                    Text(L("记录你在 Agent 用量榜的排名。默认隐藏：不读取本地榜单身份、不请求榜单接口。选择「显示」后才会读取本机榜单身份并拉取公开榜单数据。"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.tokenTrack.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    StatusLine(
                        symbol: "lock.shield.fill",
                        title: L("隐私状态"),
                        value: L("零身份读取 · 零网络请求"),
                        tint: .tokenGreen
                    )
                }

                if appState.shouldShowAgentWorkRank {
                    StatusLine(
                        symbol: "arrow.triangle.2.circlepath",
                        title: L("数据同步"),
                        value: syncText,
                        tint: .tokenGreen
                    )

                    HStack(spacing: 8) {
                        Button {
                            appState.openTokenRankUserPage()
                        } label: {
                            Label(L("我的消耗"), systemImage: "person.crop.circle")
                                .font(.caption.weight(.heavy))
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                        }
                        .buttonStyle(SettingsSecondaryButtonStyle())

                        Button {
                            appState.openTokenRankLeaderboardPage()
                        } label: {
                            Label(L("打开榜单"), systemImage: "list.number")
                                .font(.caption.weight(.heavy))
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                        }
                        .buttonStyle(SettingsSecondaryButtonStyle())
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var statusSymbol: String {
        switch appState.settings.agentWorkRankVisibility {
        case .automatic:
            return appState.agentWorkRankIdentity == nil ? "magnifyingglass" : "checkmark.circle.fill"
        case .visible:
            return "eye.fill"
        case .hidden:
            return "eye.slash.fill"
        }
    }

    private var statusTitle: String {
        switch appState.settings.agentWorkRankVisibility {
        case .automatic:
            return appState.agentWorkRankIdentity == nil ? L("自动检测") : L("已自动显示")
        case .visible:
            return L("已显示")
        case .hidden:
            return L("已手动隐藏")
        }
    }

    private var statusValue: String {
        if let identity = appState.agentWorkRankIdentity {
            return identity.name
        }
        switch appState.settings.agentWorkRankVisibility {
        case .automatic:
            return L("未检测到 Token Rank")
        case .visible:
            return L("等待关联")
        case .hidden:
            return L("不读取身份与榜单")
        }
    }

    private var statusTint: Color {
        switch appState.settings.agentWorkRankVisibility {
        case .automatic:
            return appState.agentWorkRankIdentity == nil ? .orange : .tokenGreen
        case .visible:
            return .tokenGreen
        case .hidden:
            return .gray
        }
    }

    private var syncText: String {
        guard let date = appState.agentWorkRankIdentity?.lastSyncedAt else {
            return L("等待同步")
        }
        return relativeTime(date)
    }

    private func relativeTime(_ date: Date) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes < 1 { return L("刚刚") }
        if minutes < 60 { return LFormat("%d 分钟前", minutes) }
        return LFormat("%d 小时前", minutes / 60)
    }
}

/// 数据来源（统一卡，原型 4）：正式源状态 + 实验源主开关与逐源开关。
struct SettingsAgentSourcesCard: View {
    @EnvironmentObject private var appState: AppState

    /// 全部实验源 = 旧三源 + G-A1 七源；启用语义见 AgentSourceRegistry.enabledIDs。
    private var experimentalSourceIDs: [String] {
        ["ZCode", "Hermes Agent", "WorkBuddy"] + AgentSourceRegistry.allSourceIDs
    }

    private var installedT1IDs: Set<String> {
        Set(AgentSourceRegistry.observeAll().filter { $0.status == "installed" }.map(\.sourceID))
    }

    private var effectiveEnabled: Set<String> {
        Set(AgentSourceRegistry.enabledIDs(
            masterEnabled: appState.settings.showExperimentalAgentSources,
            perSource: appState.settings.experimentalAgentSources
        ))
    }

    var body: some View {
        // 自然高度（height 0）：内容驱动，永不裁剪。
        SettingsCard(title: L("数据来源"), symbol: "square.grid.3x3.middle.filled", height: 0) {
            VStack(alignment: .leading, spacing: 12) {
                StatusLine(
                    symbol: "checkmark.circle.fill",
                    title: "Codex",
                    value: statusText(for: "Codex", experimental: false),
                    tint: .tokenGreen
                )
                StatusLine(
                    symbol: "checkmark.circle.fill",
                    title: "Claude Code",
                    value: statusText(for: "Claude Code", experimental: false),
                    tint: .tokenGreen
                )
                StatusLine(
                    symbol: "point.3.connected.trianglepath.dotted",
                    title: "CC Switch Proxy",
                    value: statusText(for: ccSwitchName(), experimental: false),
                    tint: .tokenGreen
                )

                Divider()

                SettingsToggleRow(
                    title: L("启用实验数据源"),
                    isOn: Binding(
                        get: { appState.settings.showExperimentalAgentSources },
                        set: { appState.setExperimentalAgentSourcesVisible($0) }
                    )
                )
                Text(L("实验源默认关闭；开启后检测到已安装的 Agent 自动纳入统计，可单独关闭某个来源。只读 usage 字段，不读对话正文。"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(experimentalSourceIDs, id: \.self) { sourceID in
                        sourceRow(sourceID)
                    }
                }
            }
        }
    }

    private func ccSwitchName() -> String {
        // 快照里的键名带口径后缀，展示用通用名。
        "CC Switch Proxy"
    }

    /// 单行紧凑源行：开关 + 名称 + 右侧状态。
    private func sourceRow(_ sourceID: String) -> some View {
        let enabled = effectiveEnabled.contains(sourceID)
        let isT1 = AgentSourceRegistry.allSourceIDs.contains(sourceID)
        let detected = !isT1 || installedT1IDs.contains(sourceID)
        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { enabled },
                set: { appState.setExperimentalAgentSource(sourceID, enabled: $0) }
            ))
            .labelsHidden()
            .disabled(!appState.settings.showExperimentalAgentSources)
            .frame(width: 32)
            Text(sourceID)
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.tokenInk.opacity(0.82))
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(statusText(for: sourceID, experimental: true, detected: detected, enabled: enabled))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.tokenTrack.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func statusText(
        for sourceID: String,
        experimental: Bool,
        detected: Bool = true,
        enabled: Bool? = nil
    ) -> String {
        let status = appState.snapshot.sources[sourceID]?.status
            ?? appState.snapshot.sources.keys.first(where: { $0.hasPrefix(sourceID) })
                .flatMap { appState.snapshot.sources[$0]?.status }
        if !experimental {
            return status == "ok" ? L("已计入统计") : L("等待同步")
        }
        guard appState.settings.showExperimentalAgentSources else {
            return detected ? L("默认关闭") : L("未检测到")
        }
        if let enabled, !enabled {
            return detected ? L("已安装，未启用") : L("未检测到")
        }
        switch status {
        case "ok": return L("已计入实验统计")
        case "missing_valid_rows": return L("暂无可用 usage")
        case "missing", "missing_db": return L("未发现数据源")
        default: return L("等待刷新")
        }
    }
}

