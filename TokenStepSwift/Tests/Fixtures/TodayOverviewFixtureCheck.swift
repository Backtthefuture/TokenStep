import Darwin
import Foundation

@main
struct TodayOverviewFixtureCheck {
    static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()
    /// Sunday 2026-09-27 15:00 in Shanghai.
    static let now = ISO8601DateFormatter().date(from: "2026-09-27T07:00:00Z")!

    static func main() {
        do {
            try checkComposition()
            try checkHeatLevels()
            try checkRecentWeeks()
            try checkGoalStreak()
            try checkDeltaVersusYesterday()
            try checkHourlyChart()
            print("Today overview fixture checks passed")
        } catch {
            fputs("Today overview fixture failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func checkComposition() throws {
        let work = agentWork(date: "2026-09-27", input: 612, cached: 594, output: 3)
        let composition = TodayOverviewModel.composition(work)
        try expect(composition.freshInput == 18, "cached input is split out of input, got \(composition.freshInput)")
        try expect(composition.cacheRead == 594 && composition.output == 3, "cache read and output kept")
        try expect(composition.total == 615, "parts add up to input + output")
        let odd = TodayOverviewModel.composition(agentWork(date: "x", input: 10, cached: 50, output: 0))
        try expect(odd.cacheRead == 10 && odd.freshInput == 0, "cached never exceeds input")
    }

    private static func checkHeatLevels() throws {
        let goal = 100
        try expect(TodayOverviewModel.heatLevel(tokens: 0, goal: goal) == 0, "no usage is level 0")
        try expect(TodayOverviewModel.heatLevel(tokens: 10, goal: goal) == 1, "under 20% is level 1")
        try expect(TodayOverviewModel.heatLevel(tokens: 20, goal: goal) == 2, "20% is level 2")
        try expect(TodayOverviewModel.heatLevel(tokens: 50, goal: goal) == 3, "50% is level 3")
        try expect(TodayOverviewModel.heatLevel(tokens: 100, goal: goal) == 4, "the goal is level 4")
        try expect(TodayOverviewModel.heatLevel(tokens: 1, goal: 0) == 4, "no goal counts any usage as full")
    }

    private static func checkRecentWeeks() throws {
        let daily = [
            usage("2026-09-27", 40),
            usage("2026-09-21", 100),
            usage("2026-08-24", 60)
        ]
        let cells = TodayOverviewModel.recentWeeks(daily: daily, goal: 100, today: now, weeks: 5, calendar: calendar)
        try expect(cells.count == 35, "five weeks of seven days, got \(cells.count)")
        try expect(cells.first?.date == "2026-08-24", "starts on the Monday four weeks back, got \(cells.first?.date ?? "-")")
        try expect(cells.first?.level == 3, "first Monday carries its usage")
        try expect(cells.last?.date == "2026-09-27" && cells.last?.isToday == true, "today (Sunday) closes the grid")
        try expect(cells.filter(\.isFuture).isEmpty, "a Sunday has no future days")
        try expect(cells.first { $0.date == "2026-09-21" }?.level == 4, "a goal day is level 4")

        let wednesday = ISO8601DateFormatter().date(from: "2026-09-23T07:00:00Z")!
        let midweek = TodayOverviewModel.recentWeeks(daily: daily, goal: 100, today: wednesday, weeks: 5, calendar: calendar)
        try expect(midweek.suffix(4).allSatisfy(\.isFuture), "Thursday to Sunday are future on a Wednesday")
        try expect(midweek[midweek.count - 5].isToday, "Wednesday is today")
    }

    private static func checkGoalStreak() throws {
        let daily = [
            usage("2026-09-23", 50),
            usage("2026-09-24", 120),
            usage("2026-09-25", 100),
            usage("2026-09-26", 300),
            usage("2026-09-27", 40)
        ]
        try expect(TodayOverviewModel.goalStreak(daily: daily, goal: 100, today: now, calendar: calendar) == 3,
                   "an unfinished today keeps yesterday's streak")
        var reached = daily
        reached[4] = usage("2026-09-27", 100)
        try expect(TodayOverviewModel.goalStreak(daily: reached, goal: 100, today: now, calendar: calendar) == 4,
                   "reaching the goal today extends the streak")
        try expect(TodayOverviewModel.goalStreak(daily: [usage("2026-09-25", 500)], goal: 100, today: now, calendar: calendar) == 0,
                   "a gap yesterday breaks the streak")
    }

    private static func checkDeltaVersusYesterday() throws {
        let today = agentWork(date: "2026-09-27", hours: [(9, 50), (14, 30), (15, 20)])
        let yesterday = agentWork(date: "2026-09-26", hours: [(9, 10), (14, 10), (20, 500)])
        try expect(TodayOverviewModel.deltaVersusYesterday(today: today, yesterday: yesterday, throughHour: 14) == 60,
                   "compares only up to the same hour")
        try expect(TodayOverviewModel.deltaVersusYesterday(today: today, yesterday: nil, throughHour: 14) == nil,
                   "no yesterday, no comparison")
    }

    private static func checkHourlyChart() throws {
        let work = DailyAgentWork(
            date: "2026-09-27",
            totalTokens: 0,
            activeHours: 0,
            modelRequestCount: 0,
            toolCallCount: 0,
            sources: [],
            hourlyBuckets: [
                AgentWorkHourBucket(hour: 10, sources: [source("Codex", 50), source("Cursor", 5), source("Hermes", 3), source("Kimi", 2)]),
                AgentWorkHourBucket(hour: 11, sources: [source("Codex", 20), source("Claude Code", 90)])
            ]
        )
        let chart = TodayOverviewModel.hourlyChart(work: work, currentHour: 11, maxSources: 3)
        try expect(chart.sourceOrder == ["Claude Code", "Codex", "Cursor", ""], "top three by total plus other, got \(chart.sourceOrder)")
        try expect(chart.hours[10].parts == [0, 50, 5, 5], "the rest folds into other, got \(chart.hours[10].parts)")
        try expect(chart.peakHour == 11 && chart.peakTokens == 110, "peak is the busiest hour")
        try expect(chart.hours[12].isFuture && !chart.hours[11].isFuture, "hours after now are future")
        let empty = TodayOverviewModel.hourlyChart(work: agentWork(date: "x", input: 0, cached: 0, output: 0), currentHour: nil)
        try expect(empty.peakHour == nil && empty.sourceOrder.isEmpty, "no usage has no peak")
    }

    // MARK: Helpers

    private static func usage(_ date: String, _ tokens: Int) -> DailyUsage {
        DailyUsage(date: date, tools: [:], totalTokens: tokens, cost: 0)
    }

    private static func source(_ name: String, _ tokens: Int) -> AgentWorkHourlySource {
        AgentWorkHourlySource(source: name, tokens: tokens, inputTokens: tokens, cachedInputTokens: 0, outputTokens: 0, cacheCoverageComplete: false)
    }

    private static func agentWork(date: String, input: Int, cached: Int, output: Int) -> DailyAgentWork {
        DailyAgentWork(
            date: date,
            totalTokens: input + output,
            activeHours: 0,
            modelRequestCount: 0,
            toolCallCount: 0,
            sources: [],
            inputTokens: input,
            cachedInputTokens: cached,
            outputTokens: output
        )
    }

    private static func agentWork(date: String, hours: [(Int, Int)]) -> DailyAgentWork {
        DailyAgentWork(
            date: date,
            totalTokens: hours.map(\.1).reduce(0, +),
            activeHours: hours.count,
            modelRequestCount: 0,
            toolCallCount: 0,
            sources: [],
            hourlyBuckets: hours.map { AgentWorkHourBucket(hour: $0.0, sources: [source("Codex", $0.1)]) }
        )
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw FixtureError(message: message) }
    }

    struct FixtureError: Error, CustomStringConvertible {
        var message: String
        var description: String { message }
    }
}
