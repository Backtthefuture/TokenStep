import SwiftUI

struct PopoverQuotaCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TokenCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.tokenGreen)
                        .frame(width: 8, height: 8)
                    Text(L("Agent 剩余额度"))
                        .font(.callout.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                    Spacer()
                    if appState.isRefreshingCodexQuota {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.72)
                    }
                }

                // 从未读到额度的供应商整段隐藏（用户裁决 2026-08-13）；
                // "失败但保留旧值"的段落仍按 G-V1 规则展示。
                if showsCodexQuotaSection || showsClaudeQuotaSection {
                    VStack(spacing: 12) {
                        if showsCodexQuotaSection {
                            // Codex 已取消 5 小时额度，仅展示 7 天窗口（2026-08-13）。
                            quotaSection(
                                title: "Codex",
                                quota: appState.codexQuota,
                                freshness: appState.codexQuotaFreshness,
                                showsFiveHourWindow: false
                            )
                        }
                        if showsClaudeQuotaSection {
                            quotaSection(
                                title: "Claude Code",
                                quota: appState.claudeQuota,
                                freshness: appState.claudeQuotaFreshness
                            )
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "terminal")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.tokenGreen)
                            .frame(width: 28, height: 28)
                            .background(Color.tokenMint.opacity(0.22), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("暂未读取到 Agent 额度"))
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(Color.tokenInk.opacity(0.76))
                            Text(L("打开并登录 Codex / Claude Code 后会自动显示。"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.vertical, -2)
    }

    private var showsCodexQuotaSection: Bool {
        appState.codexQuota.isAvailable || appState.codexQuotaFreshness.kind == .stale
    }

    private var showsClaudeQuotaSection: Bool {
        appState.claudeQuota.isAvailable || appState.claudeQuotaFreshness.kind == .stale
    }

    private func quotaSection(
        title: String,
        quota: CodexQuotaSnapshot,
        freshness: UsageFreshness,
        showsFiveHourWindow: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.tokenInk.opacity(0.76))
                Spacer()
                FreshnessBadge(freshness: freshness, showsLastSucceeded: freshness.needsAttention)
            }
            if quota.isAvailable {
                VStack(spacing: 8) {
                    if showsFiveHourWindow {
                        quotaRow(quota.fiveHour, fallbackTitle: L("5 小时"))
                    }
                    quotaRow(quota.sevenDay, fallbackTitle: L("7 天"))
                }
            } else if freshness.kind == .stale, let keeps = freshness.keepsLastValueLabel {
                Text(keeps)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text(L("暂无数据"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func quotaRow(_ window: CodexQuotaWindow?, fallbackTitle: String) -> some View {
        HStack(spacing: 10) {
            Text(window?.title ?? fallbackTitle)
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.tokenInk.opacity(0.72))
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(window.map { LFormat("剩余 %@", TokenStepFormat.percent($0.remainingPercent)) } ?? L("等待同步"))
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(window == nil ? .secondary : Color.tokenInk.opacity(0.82))
                    Spacer()
                    Text(window.map { quotaResetText($0.resetsAt) } ?? L("等待重置"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.tokenGreen.opacity(0.10))
                        if let window {
                            Capsule()
                                .fill(Color.tokenGreen)
                                .frame(width: max(5, proxy.size.width * window.remainingPercent / 100))
                        }
                    }
                }
                .frame(height: 6)
            }
        }
    }

    private func quotaResetText(_ date: Date?) -> String {
        guard let date else { return L("等待重置") }
        let seconds = max(0, Int(date.timeIntervalSinceNow.rounded()))
        if seconds < 60 {
            return L("即将重置")
        }
        if seconds < 3_600 {
            return LFormat("%d 分后重置", max(1, seconds / 60))
        }
        if seconds < 86_400 {
            let hours = seconds / 3_600
            let minutes = (seconds % 3_600) / 60
            return LFormat("约 %d:%02d 后重置", hours, minutes)
        }
        let days = max(1, Int(ceil(Double(seconds) / 86_400)))
        return LFormat("%d 天后重置", days)
    }
}
