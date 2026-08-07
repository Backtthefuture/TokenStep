import SwiftUI

struct PopoverTokenRankCard: View {
    @EnvironmentObject private var appState: AppState
    @State private var userRankFrame: CGRect = .zero

    var body: some View {
        TokenCard {
            VStack(alignment: .leading, spacing: 13) {
                header
                userRankContent
                metaContent
            }
        }
        .coordinateSpace(name: "tokenRankCard")
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onPreferenceChange(TokenRankUserRowFrameKey.self) { frame in
            userRankFrame = frame
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("tokenRankCard"))
                .onEnded { value in
                    let dx = abs(value.location.x - value.startLocation.x)
                    let dy = abs(value.location.y - value.startLocation.y)
                    guard dx < 4, dy < 4 else { return }
                    if appState.agentWorkRankIdentity != nil, userRankFrame.contains(value.location) {
                        appState.openTokenRankUserPage()
                    } else {
                        appState.openTokenRankLeaderboardPage()
                    }
                }
        )
        .onAppear {
            appState.refreshTokenRank()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.tokenGreen)
                .frame(width: 8, height: 8)
            Text(L("Agent 消耗榜"))
                .font(.callout.weight(.heavy))
                .foregroundStyle(Color.tokenInk)
            Spacer()
            if appState.isRefreshingTokenRank {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.72)
            } else if let fetchedAt = appState.tokenRank?.fetchedAt {
                Text(headerStatus(fetchedAt))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var userRankContent: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: mainSymbol)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(mainTint)
                .frame(width: 38, height: 38)
                .background(mainTint.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                if let entry = currentUserEntry {
                    Text(L("今日排名"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("#\(entry.rank)")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.tokenInk)
                        .monospacedDigit()
                } else {
                    Text(mainTitle)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                Text(mainSubtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let rankContext {
                    Text(rankContext)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(mainTint)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color.tokenInk.opacity(0.48))
        }
        .contentShape(Rectangle())
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TokenRankUserRowFrameKey.self,
                    value: proxy.frame(in: .named("tokenRankCard"))
                )
            }
        )
        .help(appState.agentWorkRankIdentity == nil ? L("打开榜单页") : L("打开个人页"))
    }

    @ViewBuilder
    private var metaContent: some View {
        if let error = appState.tokenRankError, appState.tokenRank == nil {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(error)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.tokenTrack.opacity(0.30), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        } else {
            HStack(spacing: 8) {
                if let entry = currentUserEntry {
                    TokenRankMetaPill(label: L("我的今日 Token"), value: TokenStepFormat.tokens(entry.totalTokens, compact: true))
                } else if let topEntry = appState.tokenRank?.topEntry {
                    TokenRankMetaPill(label: L("今日榜首"), value: TokenStepFormat.tokens(topEntry.totalTokens, compact: true))
                } else {
                    TokenRankMetaPill(label: L("今日榜单"), value: L("等待同步"))
                }
                TokenRankMetaPill(label: L("全榜今日 Token"), value: totalRankTokensText)
            }

            if let error = appState.tokenRankError {
                Text(error)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var currentUserEntry: TokenRankEntry? {
        guard let identity = appState.agentWorkRankIdentity else { return nil }
        return appState.tokenRank?.entry(matching: identity.id)
    }

    private var mainTitle: String {
        if let entry = currentUserEntry {
            return LFormat("今日排名 #%d", entry.rank)
        }
        if appState.agentWorkRankIdentity == nil {
            return L("尚未关联")
        }
        if appState.tokenRank != nil {
            return L("今日未上榜")
        }
        if appState.tokenRankError != nil {
            return L("榜单暂不可用")
        }
        return L("Agent 消耗榜")
    }

    private var mainSubtitle: String {
        if let entry = currentUserEntry {
            return "\(entry.name) · \(L("主力")) \(primaryClientName(entry))"
        }
        if let identity = appState.agentWorkRankIdentity {
            return identity.name
        }
        return L("安装 Token Rank 后自动识别")
    }

    private var mainSymbol: String {
        if currentUserEntry != nil { return "trophy.fill" }
        if appState.agentWorkRankIdentity == nil { return "person.crop.circle.badge.questionmark" }
        if appState.tokenRank == nil, appState.tokenRankError != nil { return "exclamationmark.triangle.fill" }
        return "list.number"
    }

    private var mainTint: Color {
        appState.tokenRank == nil && appState.tokenRankError != nil ? .secondary : .tokenGreen
    }

    private var rankContext: String? {
        guard let entry = currentUserEntry,
              let leaderboard = appState.tokenRank,
              leaderboard.totalRankedUsers > 0 else { return nil }
        let percentile = max(
            0,
            min(100, Int((Double(leaderboard.totalRankedUsers - entry.rank) / Double(leaderboard.totalRankedUsers) * 100).rounded()))
        )
        return LFormat(
            "第 %d / %d · 超过 %d%% 参榜用户",
            entry.rank,
            leaderboard.totalRankedUsers,
            percentile
        )
    }

    private var totalRankTokensText: String {
        guard let leaderboard = appState.tokenRank else { return L("等待同步") }
        return TokenStepFormat.tokens(leaderboard.totalTokens, compact: true)
    }

    private func primaryClientName(_ entry: TokenRankEntry) -> String {
        guard let client = entry.clients.max(by: { $0.value < $1.value })?.key else {
            return L("全部工具")
        }
        switch client {
        case "codex": return "Codex"
        case "claude": return "Claude Code"
        case "workbuddy": return "WorkBuddy"
        case "zcode": return "ZCode"
        case "hermes": return "Hermes"
        default: return client
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date).rounded()))
        if seconds < 60 { return L("刚刚") }
        return LFormat("%d 分钟前", max(1, seconds / 60))
    }

    private func headerStatus(_ date: Date) -> String {
        let time = relativeTime(date)
        guard let count = appState.tokenRank?.totalRankedUsers, count > 0 else { return time }
        return LFormat("%d 人 · %@", count, time)
    }
}

private struct TokenRankMetaPill: View {
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.tokenInk.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.tokenTrack.opacity(0.30), in: Capsule())
    }
}

private struct TokenRankUserRowFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
