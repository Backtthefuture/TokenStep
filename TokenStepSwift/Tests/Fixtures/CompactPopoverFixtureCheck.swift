import Darwin
import Foundation

@main
struct CompactPopoverFixtureCheck {
    static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()
    static let now = ISO8601DateFormatter().date(from: "2026-09-25T04:57:00Z")!

    static func main() {
        do {
            try checkOrderingAndFolding()
            try checkUrgentProvidersNeverFold()
            try checkSingleFoldedProviderStaysExpanded()
            try checkPaceProjection()
            try checkWindowLengths()
            try checkLevels()
            try checkTopModels()
            try checkChaseNextRank()
            try checkLeader()
            try checkOutsideBoard()
            try checkUnsyncedOnlyOnSameDay()
            try checkLastHourRate()
            print("Compact popover fixture checks passed")
        } catch {
            fputs("Compact popover fixture failed: \(error)\n", stderr)
            exit(1)
        }
    }

    // MARK: Quotas

    private static func checkOrderingAndFolding() throws {
        let section = CompactPopoverModel.quotaSection(
            quotas: [
                quota(.grok, [(.monthlyCredits, 32, nil)]),
                quota(.codex, [(.fiveHour, 67, hours(0.2)), (.sevenDay, 69, hours(34.5))]),
                quota(.glm, [(.monthlyCredits, 24, nil)]),
                quota(.kimi, [(.weekly, 12, nil)]),
                quota(.claude, [(.fiveHour, 58, nil)]),
                ProviderQuota.unavailable(.cursor)
            ],
            now: now,
            calendar: calendar
        )
        try expect(section.expanded.map(\.provider) == [.codex, .claude], "two worst providers expanded: \(section.expanded.map(\.provider))")
        try expect(section.folded.map(\.provider) == [.grok, .glm, .kimi], "calm providers fold in order: \(section.folded.map(\.provider))")
    }

    private static func checkUrgentProvidersNeverFold() throws {
        let section = CompactPopoverModel.quotaSection(
            quotas: [
                quota(.codex, [(.fiveHour, 95, nil)]),
                quota(.claude, [(.fiveHour, 91, nil)]),
                quota(.grok, [(.monthlyCredits, 75, nil)]),
                quota(.glm, [(.monthlyCredits, 10, nil)]),
                quota(.kimi, [(.weekly, 5, nil)])
            ],
            now: now,
            calendar: calendar
        )
        try expect(section.expanded.map(\.provider) == [.codex, .claude, .grok], "a warning provider stays expanded past the limit")
        try expect(section.worstLevel == .critical, "worst level is critical")
    }

    private static func checkSingleFoldedProviderStaysExpanded() throws {
        let section = CompactPopoverModel.quotaSection(
            quotas: [
                quota(.codex, [(.fiveHour, 40, nil)]),
                quota(.claude, [(.fiveHour, 30, nil)]),
                quota(.grok, [(.monthlyCredits, 20, nil)])
            ],
            now: now,
            calendar: calendar
        )
        try expect(section.expanded.count == 3 && section.folded.isEmpty, "one foldable provider is shown in full")
    }

    private static func checkPaceProjection() throws {
        // 7 days, resets in 34.5 hours: 79.5% of the window has passed.
        let week = row(.sevenDay, used: 89, resetsIn: hours(34.5))
        try expect(abs((week.elapsedFraction ?? 0) - 0.7946) < 0.001, "7-day elapsed \(String(describing: week.elapsedFraction))")
        try expect(week.runsOutEarly, "89% used at 79% elapsed runs out early")
        let session = row(.fiveHour, used: 67, resetsIn: hours(11.0 / 60))
        try expect(!session.runsOutEarly, "67% used at 96% elapsed is on pace")
        let fresh = row(.fiveHour, used: 8, resetsIn: hours(4.8))
        try expect(!fresh.runsOutEarly, "the first 10% of a window is never flagged")
        let exhausted = row(.fiveHour, used: 100, resetsIn: hours(1))
        try expect(!exhausted.runsOutEarly, "an exhausted window is not a projection")
    }

    private static func checkWindowLengths() throws {
        try expect(row(.session, used: 50, resetsIn: hours(1)).elapsedFraction == nil, "unknown session length has no marker")
        let cursor = row(.cursorModels, used: 50, resetsIn: hours(24)).elapsedFraction ?? 0
        try expect(cursor > 0.9 && cursor < 1, "cursor model window follows the monthly billing cycle: \(cursor)")
        try expect(row(.fiveHour, used: 50, resetsIn: nil).elapsedFraction == nil, "no reset time has no marker")
        let pastReset = row(.fiveHour, used: 71, resetsIn: -hours(1))
        try expect(pastReset.isReset && pastReset.usedPercent == 0 && !pastReset.runsOutEarly && pastReset.elapsedFraction == nil,
                   "a window past its reset drops the stale percentage")
        // Resets 2026-10-01 00:00 Shanghai; the window began 2026-09-01 00:00.
        let reset = ISO8601DateFormatter().date(from: "2026-09-30T16:00:00Z")!
        let monthly = CompactPopoverModel.windowRow(
            QuotaWindow(kind: .monthlyCredits, usedPercent: 50, resetsAt: reset),
            now: now,
            calendar: calendar
        )
        let expected = now.timeIntervalSince(ISO8601DateFormatter().date(from: "2026-08-31T16:00:00Z")!) / (30 * 24 * 3600)
        try expect(abs((monthly.elapsedFraction ?? 0) - expected) < 0.0001, "monthly window uses the calendar month")
    }

    private static func checkLevels() throws {
        try expect(CompactPopoverModel.QuotaLevel(usedPercent: 69.9) == .normal, "69.9 is normal")
        try expect(CompactPopoverModel.QuotaLevel(usedPercent: 70) == .warning, "70 is warning")
        try expect(CompactPopoverModel.QuotaLevel(usedPercent: 89.9) == .warning, "89.9 is warning")
        try expect(CompactPopoverModel.QuotaLevel(usedPercent: 90) == .critical, "90 is critical")
    }

    // MARK: Tokens

    private static func checkTopModels() throws {
        let usage = DailyUsage(
            date: "2026-09-25",
            tools: [:],
            models: ["GLM-5.3": 24_050_000, "GLM-5.3-Flash": 4_350_000, "gpt-6-luna": 280_000, "b-model": 120_000, "a-model": 120_000, "idle": 0],
            totalTokens: 28_920_000,
            cost: 0
        )
        let rows = CompactPopoverModel.topModels(usage)
        try expect(rows.map(\.name) == ["GLM-5.3", "GLM-5.3-Flash", "gpt-6-luna"], "top three by tokens: \(rows.map(\.name))")
        try expect(rows.first?.share == 1 && abs(rows[1].share - 4_350_000.0 / 24_050_000) < 1e-9, "shares are relative to the largest")
        let tie = CompactPopoverModel.topModels(usage, limit: 5).suffix(2).map(\.name)
        try expect(tie == ["a-model", "b-model"], "ties break by name: \(tie)")
        try expect(CompactPopoverModel.topModels(DailyUsage(date: "d", tools: [:], totalTokens: 0, cost: 0)).isEmpty, "no models, no rows")
    }

    // MARK: Rank

    private static func checkChaseNextRank() throws {
        let board = leaderboard(ranked: 88, limit: 100, [
            (1, 11, "A", 860_000_000), (2, 12, "B", 716_000_000), (3, 13, "C", 666_000_000),
            (34, 20, "Next", 32_630_000), (35, 99, "Me", 28_510_000), (36, 21, "Below", 20_000_000)
        ])
        let section = CompactPopoverModel.rankSection(
            board: board, myUserID: 99, localTodayTokens: 28_800_000,
            tokensPerHour: 9_800_000, localTimeZoneIdentifier: "America/Los_Angeles"
        )
        try expect(section.myRank == 35 && section.myBoardTokens == 28_510_000, "own entry found")
        guard case let .next(rank, name, gap, progress) = section.chase else {
            throw FixtureError("expected a next-rank chase, got \(String(describing: section.chase))")
        }
        try expect(rank == 34 && name == "Next" && gap == 4_120_001, "gap to #34 is \(gap)")
        try expect(abs(progress - 28_510_000.0 / 32_630_000) < 1e-9, "progress toward #34")
        try expect(section.etaMinutes == 26, "ETA rounds up: \(String(describing: section.etaMinutes))")
        try expect(section.podium.isEmpty, "no podium outside the top \(CompactPopoverModel.podiumRankLimit)")
        try expect(section.behind == .init(rank: 36, name: "Below", lead: 8_510_000), "closest entry behind: \(String(describing: section.behind))")
        try expect(section.unsyncedTokens == nil && section.projectedRank == nil, "different days are not compared")
    }

    private static func checkLeader() throws {
        let board = leaderboard(ranked: 3, limit: 100, [(1, 99, "Me", 900), (2, 12, "B", 600), (3, 13, "C", 100)])
        let section = CompactPopoverModel.rankSection(
            board: board, myUserID: 99, localTodayTokens: 900, tokensPerHour: 100, localTimeZoneIdentifier: "Asia/Shanghai"
        )
        try expect(section.chase == .leading(lead: 300), "first place shows its lead")
        try expect(section.etaMinutes == nil, "no ETA when leading")
        try expect(section.podium.map(\.rank) == [1, 2, 3] && section.podium.first?.isMe == true, "podium near the top marks me")
        try expect(section.behind == nil, "first place shows its lead instead of who is behind")
    }

    private static func checkOutsideBoard() throws {
        let rows = (1...100).map { (rank: $0, id: $0, name: "U\($0)", tokens: 1_000_000_000 / $0) }
        let board = leaderboard(ranked: 146, limit: 100, rows)
        let shanghai = CompactPopoverModel.rankSection(
            board: board, myUserID: 999, localTodayTokens: 3_100_000, tokensPerHour: 1_500_000, localTimeZoneIdentifier: "Asia/Shanghai"
        )
        try expect(shanghai.myRank == nil, "not listed")
        try expect(shanghai.chase == .enterBoard(rank: 100, tokens: 10_000_000, gap: 6_900_001), "gap to enter the board: \(String(describing: shanghai.chase))")
        try expect(shanghai.etaMinutes == 277, "ETA to enter the board: \(String(describing: shanghai.etaMinutes))")
        let elsewhere = CompactPopoverModel.rankSection(
            board: board, myUserID: 999, localTodayTokens: 3_100_000, tokensPerHour: 1_500_000, localTimeZoneIdentifier: "Europe/Berlin"
        )
        try expect(elsewhere.chase == .enterBoard(rank: 100, tokens: 10_000_000, gap: nil), "no gap from a different day")
        try expect(elsewhere.etaMinutes == nil, "no ETA without a gap")
        let small = leaderboard(ranked: 3, limit: 100, [(1, 1, "A", 3), (2, 2, "B", 2), (3, 3, "C", 1)])
        let absent = CompactPopoverModel.rankSection(
            board: small, myUserID: 999, localTodayTokens: 0, tokensPerHour: 0, localTimeZoneIdentifier: "Asia/Shanghai"
        )
        try expect(absent.chase == nil, "not on a board that lists everyone: no chase")
    }

    private static func checkUnsyncedOnlyOnSameDay() throws {
        let board = leaderboard(ranked: 5, limit: 100, [
            (1, 1, "A", 500), (2, 2, "B", 400), (3, 3, "C", 300), (4, 99, "Me", 200), (5, 5, "E", 100)
        ])
        let section = CompactPopoverModel.rankSection(
            board: board, myUserID: 99, localTodayTokens: 350, tokensPerHour: 0, localTimeZoneIdentifier: "Asia/Shanghai"
        )
        try expect(section.unsyncedTokens == 150, "unsynced local tokens")
        try expect(section.projectedRank == 3, "350 would place third: \(String(describing: section.projectedRank))")
        // Gaps count the local total, not the board's stale one.
        guard case let .next(rank, _, gap, _) = section.chase else {
            throw FixtureError("expected a next-rank chase, got \(String(describing: section.chase))")
        }
        try expect(rank == 2 && gap == 51, "local 350 chases #2 at 400: #\(rank) gap \(gap)")
        try expect(section.behind == .init(rank: 3, name: "C", lead: 50), "local 350 leads #3: \(String(describing: section.behind))")
        let behind = CompactPopoverModel.rankSection(
            board: board, myUserID: 99, localTodayTokens: 180, tokensPerHour: 0, localTimeZoneIdentifier: "Asia/Shanghai"
        )
        try expect(behind.unsyncedTokens == nil && behind.projectedRank == nil, "local behind the board shows nothing")
    }

    private static func checkLastHourRate() throws {
        let buckets = [HourlyTokenBucket(hour: 11, tokens: 6_000_000), HourlyTokenBucket(hour: 12, tokens: 4_000_000)]
        // 12:57 Shanghai: all of 12:00-12:57 plus the last 3 minutes of 11:00.
        let rate = CompactPopoverModel.tokensInLastHour(buckets: buckets, now: now, calendar: calendar)
        try expect(rate == 4_000_000 + 300_000, "last-hour rate \(rate)")
    }

    // MARK: Helpers

    private static func hours(_ value: Double) -> TimeInterval { value * 3600 }

    private static func row(_ kind: QuotaWindowKind, used: Double, resetsIn: TimeInterval?) -> CompactPopoverModel.QuotaWindowRow {
        CompactPopoverModel.windowRow(
            QuotaWindow(kind: kind, usedPercent: used, resetsAt: resetsIn.map { now.addingTimeInterval($0) }),
            now: now,
            calendar: calendar
        )
    }

    private static func quota(_ provider: QuotaProviderID, _ windows: [(QuotaWindowKind, Double, TimeInterval?)]) -> ProviderQuota {
        ProviderQuota(
            provider: provider,
            windows: windows.map { QuotaWindow(kind: $0.0, usedPercent: $0.1, resetsAt: $0.2.map { now.addingTimeInterval($0) }) },
            status: .available,
            fetchedAt: now,
            message: nil
        )
    }

    private static func leaderboard(ranked: Int, limit: Int, _ rows: [(rank: Int, id: Int, name: String, tokens: Int)]) -> TokenRankLeaderboard {
        TokenRankLeaderboard(
            fetchedAt: now,
            range: "today",
            client: "all",
            usageMode: "all",
            totalTokens: rows.map(\.tokens).reduce(0, +),
            totalRankedUsers: ranked,
            topLimit: limit,
            entries: rows.map {
                TokenRankEntry(rank: $0.rank, userID: $0.id, name: $0.name, avatarURL: nil, totalTokens: $0.tokens, callCount: 0, sessionCount: 0, clients: [:], models: [:])
            }
        )
    }

    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw FixtureError(message) }
    }
}

private struct FixtureError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
