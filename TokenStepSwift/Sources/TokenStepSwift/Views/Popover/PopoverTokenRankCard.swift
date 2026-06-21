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
                    if hasConfiguredUserID, userRankFrame.contains(value.location) {
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
            Text(L("生财 Token 榜单"))
                .font(.callout.weight(.heavy))
                .foregroundStyle(Color.tokenInk)
            Spacer()
            if appState.isRefreshingTokenRank {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.72)
            } else if let fetchedAt = appState.tokenRank?.fetchedAt {
                Text(fetchedText(fetchedAt))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var userRankContent: some View {
        mainContent
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TokenRankUserRowFrameKey.self,
                        value: proxy.frame(in: .named("tokenRankCard"))
                    )
                }
            )
            .help(hasConfiguredUserID ? L("打开个人页") : L("打开榜单页"))
    }

    private var mainContent: some View {
        HStack(alignment: .center, spacing: 12) {
            mainIcon
            mainText
            Spacer(minLength: 0)
            mainArrow
        }
        .contentShape(Rectangle())
    }

    private var mainIcon: some View {
        Image(systemName: mainSymbol)
            .font(.system(size: 18, weight: .heavy))
            .foregroundStyle(mainTint)
            .frame(width: 38, height: 38)
            .background(mainTint.opacity(0.16), in: Circle())
    }

    private var mainText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(mainTitle)
                .font(.title3.weight(.heavy))
                .foregroundStyle(Color.tokenInk)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(mainSubtitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var mainArrow: some View {
        Image(systemName: "arrow.up.right")
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Color.tokenInk.opacity(0.48))
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
                    TokenRankMetaPill(label: L("今日 Token"), value: TokenStepFormat.tokens(entry.score, compact: true))
                } else if let topEntry = appState.tokenRank?.topEntry {
                    TokenRankMetaPill(label: L("今日榜首"), value: "#\(topEntry.rank) \(TokenStepFormat.tokens(topEntry.score, compact: true))")
                } else {
                    TokenRankMetaPill(label: L("今日榜单"), value: L("等待同步"))
                }

                TokenRankMetaPill(label: L("上榜："), value: rankingThresholdText)
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
        appState.tokenRank?.entry(matching: appState.settings.tokenRankUserID)
    }

    private var hasConfiguredUserID: Bool {
        !appState.settings.tokenRankUserID.isEmpty
    }

    private var mainTitle: String {
        if let entry = currentUserEntry {
            return LFormat("今日排名 #%d", entry.rank)
        }
        if hasConfiguredUserID, appState.tokenRank != nil {
            return L("今日未上榜")
        }
        if appState.tokenRank == nil, appState.tokenRankError != nil {
            return L("榜单暂不可用")
        }
        return L("生财榜单")
    }

    private var mainSubtitle: String {
        if let entry = currentUserEntry {
            return entry.name
        }
        if hasConfiguredUserID, appState.tokenRank != nil {
            return L("点击查看今日榜单")
        }
        if appState.tokenRank == nil, appState.tokenRankError != nil {
            return L("点击打开榜单页")
        }
        return L("点击查看今日榜单")
    }

    private var mainSymbol: String {
        if currentUserEntry != nil {
            return "trophy.fill"
        }
        if appState.tokenRank == nil, appState.tokenRankError != nil {
            return "exclamationmark.triangle.fill"
        }
        return "list.number"
    }

    private var mainTint: Color {
        appState.tokenRank == nil && appState.tokenRankError != nil ? .secondary : .tokenGreen
    }

    private var rankingThresholdText: String {
        guard let entry = rankingThresholdEntry else {
            return L("等待同步")
        }
        return TokenStepFormat.tokens(entry.score, compact: true)
    }

    private var rankingThresholdEntry: TokenRankEntry? {
        guard let entries = appState.tokenRank?.entries, !entries.isEmpty else {
            return nil
        }
        return entries.first { $0.rank == 100 } ?? entries.max { $0.rank < $1.rank }
    }

    private func fetchedText(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date).rounded()))
        if seconds < 60 {
            return L("刚刚")
        }
        return LFormat("%d 分钟前", max(1, seconds / 60))
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
