import SwiftUI

struct SettingsDataSourcesPane: View {
    @EnvironmentObject private var appState: AppState
    var openQuotaTab: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            SettingsSectionCard(
                title: L("L1 · 本地账本"),
                subtitle: L("本地日志有可核对的 token 数，才会计入 Token 总量"),
                badge: L("计入圆环与总量"),
                badgeStyle: .l1
            ) {
                VStack(spacing: 0) {
                    ForEach(AgentSourceRegistry.ledgerSources) { source in
                        sourceRow(source)
                    }
                    SettingsSourceRow(
                        title: L("实验来源（ZCode / Hermes / DeepSeek Harness / WorkBuddy）"),
                        detail: L("只读取本地 usage 字段，不读取对话正文。"),
                        badge: appState.settings.showExperimentalAgentSources ? L("已开启") : L("未启用"),
                        badgeStyle: appState.settings.showExperimentalAgentSources ? .ok : .off,
                        showsToggle: true,
                        isOn: Binding(
                            get: { appState.settings.showExperimentalAgentSources },
                            set: { appState.setExperimentalAgentSourcesVisible($0) }
                        )
                    )
                }
            }

            SettingsSectionCard(
                title: L("L2 · 配额探针"),
                subtitle: L("额度百分比不进圆环。Cursor 开启后，官方 token 事件会计入圆环。"),
                badge: L("只进额度栏"),
                badgeStyle: .l2,
                tint: .l2
            ) {
                VStack(spacing: 0) {
                    SettingsSourceRow(
                        title: "Cursor",
                        detail: L("官方用量事件计入圆环 · 两档额度另见额度页"),
                        badge: appState.settings.cursorQuotaEnabled ? L("计入圆环") : L("去额度页配置"),
                        badgeStyle: appState.settings.cursorQuotaEnabled ? .ok : .l2,
                        actionTitle: L("去额度页配置"),
                        action: openQuotaTab
                    )
                    SettingsSourceRow(
                        title: "GLM / Kimi / Grok",
                        detail: L("本机登录态或手动填写 · 密钥只进钥匙串"),
                        badge: L("去额度页配置"),
                        badgeStyle: .l2,
                        actionTitle: L("去额度页配置"),
                        action: openQuotaTab
                    )
                }
            }

            SettingsSectionCard(
                title: L("L3 · 产出信号"),
                subtitle: L("不是 token，是「AI 写了多少」。纯本地读取，不计入任何 Token 口径"),
                badge: L("独立展示"),
                badgeStyle: .l3,
                tint: .l3
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsSourceRow(
                        title: L("Cursor 代码产出"),
                        detail: L("~/.cursor/ai-tracking/ai-code-tracking.db · 只读计数与模型"),
                        badge: l3Badge,
                        badgeStyle: appState.settings.cursorCodeSignalEnabled ? .ok : .off,
                        showsToggle: true,
                        isOn: Binding(
                            get: { appState.settings.cursorCodeSignalEnabled },
                            set: { appState.setCursorCodeSignalEnabled($0) }
                        )
                    )
                    Text(L("不读取 tracked_file_content（代码正文）与 conversation_summaries（对话摘要）。"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func sourceRow(_ source: AgentSourceDescriptor) -> some View {
        if source.isExperimental {
            SettingsSourceRow(
                title: source.displayName,
                detail: AgentSourceCopy.detail(source),
                badge: statusText(for: source),
                badgeStyle: badgeStyle(for: source)
            )
        } else {
            SettingsSourceRow(
                title: source.displayName,
                detail: AgentSourceCopy.detail(source),
                badge: statusText(for: source),
                badgeStyle: badgeStyle(for: source)
            )
        }
    }

    private var l3Badge: String {
        if !appState.settings.cursorCodeSignalEnabled {
            return L("未启用")
        }
        if let signal = appState.cursorCodeSignal, signal.blockCount > 0 {
            return LFormat("%d 块可读", signal.blockCount)
        }
        return SourceStatusCopy.text(appState.cursorCodeSignal?.status ?? "pending_refresh")
    }

    private func rawStatus(for source: AgentSourceDescriptor) -> String {
        appState.snapshot.sources[source.displayName]?.status
            ?? appState.snapshot.sources[source.id]?.status
            ?? (source.isExperimental && !appState.settings.showExperimentalAgentSources ? "disabled" : "missing")
    }

    private func statusText(for source: AgentSourceDescriptor) -> String {
        let raw = rawStatus(for: source)
        if source.id == "cc-switch", raw == "ok" || raw == "ok_sqlite" {
            let info = appState.snapshot.sources[source.displayName] ?? appState.snapshot.sources[source.id]
            if (info?.records ?? 0) == 0, (info?.dedupedRecords ?? 0) > 0 {
                return L("已全部去重")
            }
        }
        if let info = appState.snapshot.sources[source.displayName] ?? appState.snapshot.sources[source.id],
           (raw == "ok" || raw == "ok_sqlite"),
           let records = info.records, records > 0 {
            return LFormat("正常 · %d 请求", records)
        }
        return SourceStatusCopy.text(raw)
    }

    private func badgeStyle(for source: AgentSourceDescriptor) -> SettingsBadgeStyle {
        switch rawStatus(for: source) {
        case "ok", "ok_sqlite", "available":
            return .ok
        case "disabled":
            return .off
        case "missing", "missing_db", "empty":
            return .warn
        default:
            return .warn
        }
    }
}

struct SettingsSourceRow: View {
    var title: String
    var detail: String
    var badge: String
    var badgeStyle: SettingsBadgeStyle
    var showsToggle = false
    var isOn: Binding<Bool>?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.tokenInk)
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            SettingsBadge(text: badge, style: badgeStyle)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.caption.weight(.heavy))
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                }
                .buttonStyle(SettingsSecondaryButtonStyle())
            }
            if showsToggle, let isOn {
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(TokenStepSwitchToggleStyle())
            }
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.tokenDivider)
                .frame(height: 1)
        }
    }
}

enum AgentSourceCopy {
    static func detail(_ source: AgentSourceDescriptor) -> String {
        switch source.id {
        case "codex":
            return L("~/.codex/sessions · JSONL 增量")
        case "claude":
            return L("~/.claude/projects · 按 message.id 去重")
        case "cc-switch":
            return L("~/.cc-switch/cc-switch.db · 与原生跨源去重")
        case "zcode":
            return L("~/.zcode/cli/db/db.sqlite · 实验")
        case "hermes":
            return L("~/.hermes/state.db · 实验")
        case "workbuddy":
            return L("~/.workbuddy/projects · 实验")
        case "deepseek-harness":
            return L("DeepSeek Harness 会话压缩档 · 实验")
        case "autoclaw":
            return L("~/.openclaw-autoclaw · 会话 JSONL")
        case "cursor":
            return L("本地无 token 账本 · 官方事件计入圆环")
        case "cursor-code":
            return L("~/.cursor/ai-tracking/ai-code-tracking.db · 只读计数与模型")
        default:
            return L("各自本机登录态")
        }
    }
}

enum SourceStatusCopy {
    static func text(_ status: String?) -> String {
        switch status {
        case "ok", "ok_sqlite": return L("已读取")
        case "available": return L("额度可用")
        case "missing", "missing_db": return L("数据库未找到")
        case "unreadable_db": return L("无法读取")
        case "missing_table": return L("缺少数据表")
        case "schema_unreadable": return L("结构无法读取")
        case "schema_mismatch", "schema_missing_data_source": return L("结构待适配")
        case "query_failed": return L("查询失败")
        case "disabled": return L("默认关闭")
        case "incremental_cache_error": return L("增量缓存异常")
        case "empty": return L("今日暂无")
        case "pending_refresh": return L("等待刷新")
        case "notLoggedIn": return L("未登录")
        case "wrongKeyType": return L("当前 key 非订阅计划")
        case "needsLogin": return L("需要 grok login")
        case "unavailable": return L("暂不可用")
        case "all_deduped": return L("已全部去重")
        default: return L("等待同步")
        }
    }
}

struct SettingsDataSourcesCard: View {
    var body: some View {
        SettingsDataSourcesPane(openQuotaTab: {})
    }
}
