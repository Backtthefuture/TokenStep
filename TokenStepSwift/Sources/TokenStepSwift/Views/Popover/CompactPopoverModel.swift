import Foundation

/// View-independent content of the compact menu bar popover: which quotas to
/// show and in what order, today's top models, and the rank chase. Kept free of
/// SwiftUI so fixture checks can exercise it without a UI.
enum CompactPopoverModel {
    /// Providers shown in full before the calm ones fold into one summary row.
    static let expandedProviderLimit = 2
    static let topModelLimit = 3

    // MARK: - Quotas

    enum QuotaLevel: Equatable {
        case normal
        case warning
        case critical

        init(usedPercent: Double) {
            if usedPercent >= 90 {
                self = .critical
            } else if usedPercent >= 70 {
                self = .warning
            } else {
                self = .normal
            }
        }
    }

    struct QuotaWindowRow: Equatable, Identifiable {
        var id: String { kind.rawValue }
        var kind: QuotaWindowKind
        var title: String
        var usedPercent: Double
        var level: QuotaLevel
        var resetsAt: Date?
        /// Share of the window that has passed, 0...1; nil when the window length is unknown.
        var elapsedFraction: Double?
        /// At the current pace the window runs out before it resets.
        var runsOutEarly: Bool
    }

    struct QuotaProviderRow: Equatable, Identifiable {
        var id: QuotaProviderID { provider }
        var provider: QuotaProviderID
        var windows: [QuotaWindowRow]

        var worstUsedPercent: Double {
            windows.map(\.usedPercent).max() ?? 0
        }

        var level: QuotaLevel {
            QuotaLevel(usedPercent: worstUsedPercent)
        }

        var runsOutEarly: Bool {
            windows.contains(where: \.runsOutEarly)
        }
    }

    struct QuotaSection: Equatable {
        var expanded: [QuotaProviderRow]
        /// Calm providers beyond the limit; never includes a warning or critical one.
        var folded: [QuotaProviderRow]

        var isEmpty: Bool {
            expanded.isEmpty && folded.isEmpty
        }

        var worstLevel: QuotaLevel {
            (expanded + folded).map(\.level).max { rank($0) < rank($1) } ?? .normal
        }

        private func rank(_ level: QuotaLevel) -> Int {
            switch level {
            case .normal: return 0
            case .warning: return 1
            case .critical: return 2
            }
        }
    }

    static func quotaSection(
        quotas: [ProviderQuota],
        now: Date,
        calendar: Calendar = TokenStepClock.calendar
    ) -> QuotaSection {
        let rows = quotas
            .filter(\.isAvailable)
            .map { quota in
                QuotaProviderRow(
                    provider: quota.provider,
                    windows: quota.windows.map { windowRow($0, now: now, calendar: calendar) }
                )
            }
            .sorted { lhs, rhs in
                if lhs.worstUsedPercent != rhs.worstUsedPercent {
                    return lhs.worstUsedPercent > rhs.worstUsedPercent
                }
                return providerOrder(lhs.provider) < providerOrder(rhs.provider)
            }
        var expanded: [QuotaProviderRow] = []
        var folded: [QuotaProviderRow] = []
        for row in rows {
            if expanded.count < expandedProviderLimit || row.level != .normal || row.runsOutEarly {
                expanded.append(row)
            } else {
                folded.append(row)
            }
        }
        // Folding a single provider saves no space; show it in full instead.
        if folded.count == 1 {
            expanded.append(contentsOf: folded)
            folded = []
        }
        return QuotaSection(expanded: expanded, folded: folded)
    }

    static func windowRow(_ window: QuotaWindow, now: Date, calendar: Calendar) -> QuotaWindowRow {
        let used = min(max(100 - window.remainingPercent, 0), 100)
        let elapsed = elapsedFraction(kind: window.kind, resetsAt: window.resetsAt, now: now, calendar: calendar)
        let runsOutEarly: Bool
        if let elapsed, elapsed >= 0.1, used < 100 {
            // Straight-line projection of the current pace to the end of the window.
            runsOutEarly = used / 100 > elapsed
        } else {
            runsOutEarly = false
        }
        return QuotaWindowRow(
            kind: window.kind,
            title: window.title,
            usedPercent: used,
            level: QuotaLevel(usedPercent: used),
            resetsAt: window.resetsAt,
            elapsedFraction: elapsed,
            runsOutEarly: runsOutEarly
        )
    }

    /// Only windows with a known fixed length get a pace marker.
    static func windowStart(kind: QuotaWindowKind, resetsAt: Date, calendar: Calendar) -> Date? {
        switch kind {
        case .fiveHour:
            return resetsAt.addingTimeInterval(-5 * 60 * 60)
        case .sevenDay, .weekly:
            return resetsAt.addingTimeInterval(-7 * 24 * 60 * 60)
        case .monthlyCredits, .cursorModels, .otherModels:
            // Cursor's model pools reset with its monthly billing cycle.
            return calendar.date(byAdding: .month, value: -1, to: resetsAt)
        case .session, .tokenWindow, .spend:
            return nil
        }
    }

    static func elapsedFraction(
        kind: QuotaWindowKind,
        resetsAt: Date?,
        now: Date,
        calendar: Calendar
    ) -> Double? {
        guard let resetsAt,
              let start = windowStart(kind: kind, resetsAt: resetsAt, calendar: calendar)
        else {
            return nil
        }
        let length = resetsAt.timeIntervalSince(start)
        guard length > 0 else { return nil }
        return min(max(now.timeIntervalSince(start) / length, 0), 1)
    }

    private static func providerOrder(_ provider: QuotaProviderID) -> Int {
        QuotaProviderID.allCases.firstIndex(of: provider) ?? Int.max
    }

    // MARK: - Tokens

    struct ModelRow: Equatable, Identifiable {
        var id: String { name }
        var name: String
        var tokens: Int
        /// Bar length relative to the largest model, 0...1.
        var share: Double
    }

    static func topModels(_ usage: DailyUsage, limit: Int = topModelLimit) -> [ModelRow] {
        let sorted = usage.models
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
            }
            .prefix(limit)
        let largest = Double(sorted.first?.value ?? 0)
        return sorted.map { name, tokens in
            ModelRow(name: name, tokens: tokens, share: largest > 0 ? Double(tokens) / largest : 0)
        }
    }

    // MARK: - Rank

    /// Token Rank's public board counts days in this zone.
    static let rankBoardTimeZoneIdentifier = "Asia/Shanghai"

    /// The podium is only worth showing to viewers near it; further down the
    /// board the gap to the top is too large to act on.
    static let podiumRankLimit = 10

    struct Podium: Equatable, Identifiable {
        var id: Int { rank }
        var rank: Int
        var name: String
        var tokens: Int
        var isMe: Bool
    }

    /// The closest entry behind the viewer, and by how much the viewer leads it.
    struct Behind: Equatable {
        var rank: Int
        var name: String
        var lead: Int
    }

    enum Chase: Equatable {
        /// The next rank up, and how many tokens it takes to pass it.
        case next(rank: Int, name: String, gap: Int, progress: Double)
        /// Outside the listed ranks: the last listed rank to reach.
        case enterBoard(rank: Int, tokens: Int, gap: Int?)
        /// First place, and the lead over second.
        case leading(lead: Int)
    }

    struct RankSection: Equatable {
        var myRank: Int?
        var rankedUsers: Int
        var listedLimit: Int
        var myBoardTokens: Int?
        /// Empty unless the viewer ranks within `podiumRankLimit`.
        var podium: [Podium]
        var chase: Chase?
        var behind: Behind?
        /// Minutes to close the chase gap at the last hour's pace.
        var etaMinutes: Int?
        var tokensPerHour: Int
        /// Local tokens not yet on the board; only when the local day matches the board's.
        var unsyncedTokens: Int?
        /// Where the local total would place today, when that differs from the board.
        var projectedRank: Int?
    }

    static func rankSection(
        board: TokenRankLeaderboard,
        myUserID: Int?,
        localTodayTokens: Int,
        tokensPerHour: Int,
        localTimeZoneIdentifier: String
    ) -> RankSection {
        let entries = board.entries.sorted { $0.rank < $1.rank }
        let mine = myUserID.flatMap { id in entries.first { $0.userID == id } }
        let podium = (mine.map { $0.rank <= podiumRankLimit } ?? false)
            ? entries.prefix(3).map { entry in
                Podium(rank: entry.rank, name: entry.name, tokens: entry.totalTokens, isMe: entry.userID == mine?.userID)
            }
            : []

        let sameDay = localTimeZoneIdentifier == rankBoardTimeZoneIdentifier
        var chase: Chase?
        var behind: Behind?
        var gap: Int?
        if let mine {
            // Local tokens run ahead of the board between uploads; on the same
            // day they are the truer count to measure gaps from.
            let myTokens = sameDay ? max(mine.totalTokens, localTodayTokens) : mine.totalTokens
            let others = entries.filter { $0.userID != mine.userID }
            if let next = others.last(where: { $0.totalTokens >= myTokens }) {
                let needed = next.totalTokens - myTokens + 1
                gap = needed
                let progress = next.totalTokens > 0 ? Double(myTokens) / Double(next.totalTokens) : 0
                chase = .next(rank: next.rank, name: next.name, gap: needed, progress: min(max(progress, 0), 1))
            } else if let second = others.first {
                chase = .leading(lead: max(myTokens - second.totalTokens, 0))
            }
            // First place already shows its lead over second.
            if case .next = chase, let below = others.first(where: { $0.totalTokens < myTokens }) {
                behind = Behind(rank: below.rank, name: below.name, lead: myTokens - below.totalTokens)
            }
        } else if myUserID != nil, let last = entries.last, entries.count >= board.topLimit {
            // Not listed: the board only returns the top `topLimit`. Local tokens are
            // comparable only when both count the same day.
            let needed = sameDay ? max(last.totalTokens - localTodayTokens, 0) + 1 : nil
            gap = needed
            chase = .enterBoard(rank: last.rank, tokens: last.totalTokens, gap: needed)
        }

        var eta: Int?
        if let gap, tokensPerHour > 0 {
            eta = Int((Double(gap) / Double(tokensPerHour) * 60).rounded(.up))
        }

        var unsynced: Int?
        var projected: Int?
        if sameDay, let mine, localTodayTokens > mine.totalTokens {
            unsynced = localTodayTokens - mine.totalTokens
            let ahead = entries.filter { $0.userID != mine.userID && $0.totalTokens >= localTodayTokens }.count
            if ahead + 1 < mine.rank {
                projected = ahead + 1
            }
        }

        return RankSection(
            myRank: mine?.rank,
            rankedUsers: board.totalRankedUsers,
            listedLimit: board.topLimit,
            myBoardTokens: mine?.totalTokens,
            podium: podium,
            chase: chase,
            behind: behind,
            etaMinutes: eta,
            tokensPerHour: tokensPerHour,
            unsyncedTokens: unsynced,
            projectedRank: projected
        )
    }

    /// Tokens used over the last 60 minutes, from today's hourly buckets. The
    /// previous hour counts only for the part still inside the window.
    static func tokensInLastHour(buckets: [HourlyTokenBucket], now: Date, calendar: Calendar) -> Int {
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let current = buckets.first { $0.hour == hour }?.tokens ?? 0
        let previous = hour > 0 ? (buckets.first { $0.hour == hour - 1 }?.tokens ?? 0) : 0
        return current + Int(Double(previous) * Double(60 - minute) / 60)
    }
}
