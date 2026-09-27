import Foundation

/// View-independent content of the Today dashboard: the day-over-day
/// comparison, token composition, the recent-weeks heatmap, the goal streak,
/// and the hourly chart stacked by source. Free of SwiftUI so fixture checks
/// can exercise it.
enum TodayOverviewModel {
    // MARK: - Compared with yesterday

    /// Today's tokens minus yesterday's up to the same hour, both counted from
    /// hourly buckets. Nil when yesterday has no hourly data to compare with.
    static func deltaVersusYesterday(
        today: DailyAgentWork,
        yesterday: DailyAgentWork?,
        throughHour hour: Int
    ) -> Int? {
        guard let yesterday, !yesterday.hourlyBuckets.isEmpty else { return nil }
        let limit = min(max(hour, 0), 23)
        func sum(_ work: DailyAgentWork) -> Int {
            work.hourlyBuckets.filter { $0.hour <= limit }.map(\.totalTokens).reduce(0, +)
        }
        return sum(today) - sum(yesterday)
    }

    // MARK: - Token composition

    struct Composition: Equatable {
        /// Input not served from cache.
        var freshInput: Int
        var cacheRead: Int
        var output: Int

        var total: Int { freshInput + cacheRead + output }
        var isEmpty: Bool { total <= 0 }

        func share(_ part: Int) -> Double {
            total > 0 ? Double(part) / Double(total) : 0
        }
    }

    /// Cached input is part of `inputTokens`, so it is split out rather than added.
    static func composition(_ work: DailyAgentWork) -> Composition {
        let cached = min(max(work.cachedInputTokens, 0), max(work.inputTokens, 0))
        return Composition(
            freshInput: max(work.inputTokens - cached, 0),
            cacheRead: cached,
            output: max(work.outputTokens, 0)
        )
    }

    // MARK: - Heatmap and streak

    struct HeatCell: Equatable, Identifiable {
        var id: String { date }
        var date: String
        var tokens: Int
        /// 0 (none) to 4 (goal reached).
        var level: Int
        var isToday: Bool
        var isFuture: Bool
    }

    /// Levels are relative to the daily goal, so reaching it always reads as the
    /// darkest cell.
    static func heatLevel(tokens: Int, goal: Int) -> Int {
        guard tokens > 0 else { return 0 }
        guard goal > 0 else { return 4 }
        let ratio = Double(tokens) / Double(goal)
        if ratio >= 1 { return 4 }
        if ratio >= 0.5 { return 3 }
        if ratio >= 0.2 { return 2 }
        return 1
    }

    /// `weeks` full weeks, Monday first, column by column, ending with the week
    /// that holds `today`. Days after today are marked future.
    static func recentWeeks(
        daily: [DailyUsage],
        goal: Int,
        today: Date,
        weeks: Int,
        calendar: Calendar
    ) -> [HeatCell] {
        let tokensByDay = Dictionary(daily.map { ($0.date, $0.totalTokens) }, uniquingKeysWith: max)
        let todayStart = calendar.startOfDay(for: today)
        // Monday = 0 … Sunday = 6, independent of the calendar's firstWeekday.
        let weekdayIndex = (calendar.component(.weekday, from: todayStart) + 5) % 7
        guard weeks > 0,
              let thisMonday = calendar.date(byAdding: .day, value: -weekdayIndex, to: todayStart),
              let start = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: thisMonday)
        else { return [] }
        let formatter = dayFormatter(calendar)
        return (0..<(weeks * 7)).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = formatter.string(from: day)
            let tokens = tokensByDay[key] ?? 0
            let isFuture = day > todayStart
            return HeatCell(
                date: key,
                tokens: isFuture ? 0 : tokens,
                level: isFuture ? 0 : heatLevel(tokens: tokens, goal: goal),
                isToday: day == todayStart,
                isFuture: isFuture
            )
        }
    }

    /// Consecutive days that reached the goal, ending today when today already
    /// has, else ending yesterday (today is still in progress).
    static func goalStreak(daily: [DailyUsage], goal: Int, today: Date, calendar: Calendar) -> Int {
        guard goal > 0 else { return 0 }
        let tokensByDay = Dictionary(daily.map { ($0.date, $0.totalTokens) }, uniquingKeysWith: max)
        let formatter = dayFormatter(calendar)
        var day = calendar.startOfDay(for: today)
        if (tokensByDay[formatter.string(from: day)] ?? 0) < goal,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: day) {
            day = yesterday
        }
        var streak = 0
        while (tokensByDay[formatter.string(from: day)] ?? 0) >= goal {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// The longest run of consecutive goal days anywhere in `daily`.
    static func longestGoalStreak(daily: [DailyUsage], goal: Int, calendar: Calendar) -> Int {
        guard goal > 0 else { return 0 }
        let formatter = dayFormatter(calendar)
        let goalDays = daily
            .filter { $0.totalTokens >= goal }
            .compactMap { formatter.date(from: $0.date) }
            .map { calendar.startOfDay(for: $0) }
            .sorted()
        var longest = 0
        var current = 0
        var previous: Date?
        for day in goalDays {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous), next == day {
                current += 1
            } else if previous != day {
                current = 1
            }
            longest = max(longest, current)
            previous = day
        }
        return longest
    }

    /// Tokens per hour of day summed over the given days' hourly buckets.
    static func hourOfDayTotals(_ works: [DailyAgentWork]) -> [Int] {
        var totals = Array(repeating: 0, count: 24)
        for work in works {
            for bucket in work.hourlyBuckets where (0..<24).contains(bucket.hour) {
                totals[bucket.hour] += bucket.totalTokens
            }
        }
        return totals
    }

    /// The busiest contiguous 4-hour span in `totals`, as its start hour.
    static func busiestSpan(_ totals: [Int], length: Int = 4) -> Int? {
        guard totals.count == 24, totals.contains(where: { $0 > 0 }) else { return nil }
        var best = 0
        var bestSum = -1
        for start in 0...(24 - length) {
            let sum = totals[start..<(start + length)].reduce(0, +)
            if sum > bestSum {
                bestSum = sum
                best = start
            }
        }
        return best
    }

    // MARK: - Hourly chart

    struct HourStack: Equatable, Identifiable {
        var id: Int { hour }
        var hour: Int
        /// Tokens per source, in `sourceOrder`.
        var parts: [Int]
        var isFuture: Bool

        var total: Int { parts.reduce(0, +) }
    }

    struct HourlyChart: Equatable {
        /// Sources by today's total, largest first; the stack order bottom-up.
        var sourceOrder: [String]
        var hours: [HourStack]
        var peakHour: Int?
        var peakTokens: Int

        var maxTotal: Int { hours.map(\.total).max() ?? 0 }
    }

    /// Up to `maxSources` named sources; the rest fold into the last one's slot
    /// as "other" (an empty string).
    static func hourlyChart(work: DailyAgentWork, currentHour: Int?, maxSources: Int = 3) -> HourlyChart {
        var totals: [String: Int] = [:]
        for bucket in work.hourlyBuckets {
            for source in bucket.sources where source.tokens > 0 {
                totals[source.source, default: 0] += source.tokens
            }
        }
        let ranked = totals.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
        }.map(\.key)
        var order = Array(ranked.prefix(maxSources))
        let folded = ranked.count > maxSources
        if folded { order.append("") }

        var hours: [HourStack] = []
        for hour in 0..<24 {
            let bucket = work.hourlyBuckets.first { $0.hour == hour }
            var parts = Array(repeating: 0, count: order.count)
            for source in bucket?.sources ?? [] where source.tokens > 0 {
                if let index = order.firstIndex(of: source.source) {
                    parts[index] += source.tokens
                } else if folded {
                    parts[order.count - 1] += source.tokens
                }
            }
            let isFuture = currentHour.map { hour > $0 } ?? false
            hours.append(HourStack(hour: hour, parts: parts, isFuture: isFuture))
        }
        let peak = hours.max { $0.total < $1.total }
        return HourlyChart(
            sourceOrder: order,
            hours: hours,
            peakHour: (peak?.total ?? 0) > 0 ? peak?.hour : nil,
            peakTokens: peak?.total ?? 0
        )
    }

    private static func dayFormatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
