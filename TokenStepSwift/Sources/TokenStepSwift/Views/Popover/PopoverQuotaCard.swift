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
                    } else if let fetchedAt = appState.codexQuota.fetchedAt {
                        Text(quotaFetchedText(fetchedAt))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    } else if let fetchedAt = appState.claudeQuota.fetchedAt {
                        Text(quotaFetchedText(fetchedAt))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }

                if appState.hasAnyQuota {
                    VStack(spacing: 12) {
                        if appState.codexQuota.isAvailable {
                            quotaSection(title: "Codex", quota: appState.codexQuota)
                        }
                        if appState.claudeQuota.isAvailable {
                            quotaSection(title: "Claude Code", quota: appState.claudeQuota)
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

    private func quotaSection(title: String, quota: CodexQuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.tokenInk.opacity(0.76))
            VStack(spacing: 8) {
                quotaRow(quota.fiveHour, fallbackTitle: L("5 小时"))
                quotaRow(quota.sevenDay, fallbackTitle: L("7 天"))
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

    private func quotaFetchedText(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date).rounded()))
        if seconds < 60 {
            return L("刚刚")
        }
        return LFormat("%d 分钟前", max(1, seconds / 60))
    }
}
