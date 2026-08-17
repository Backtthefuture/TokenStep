import Foundation

struct CursorUsageHourBucket: Codable, Equatable {
    var hour: Int
    var tokens: Int
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
}

struct CursorUsageDay: Codable, Equatable {
    var date: String
    var totalTokens: Int
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var cacheWriteTokens: Int
    var cost: Double
    var eventCount: Int
    var models: [String: Int]
    var hourlyBuckets: [CursorUsageHourBucket]
}

struct CursorUsageCache: Codable, Equatable {
    var fetchedAt: Date
    var days: [CursorUsageDay]
}

struct CursorUsageEvent: Equatable {
    var timestamp: Date
    var model: String
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheWriteTokens: Int
    var chargedCents: Double

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }
}

enum CursorUsageService {
    static let toolName = "Cursor"
    static let maxLookbackDays = 30
    static let maxPages = 20
    static let pageSize = 100

    static var databaseURL: URL = CursorQuotaService.databaseURL
    static var cacheURL: URL = AppPaths.cursorUsageCacheJSON

    private static let applicationUserKey =
        "src.vs.platform.reactivestorage.browser.reactiveStorageServiceImpl.persistentStorage.applicationUser"
    private static let eventsURL = URL(string: "https://cursor.com/api/dashboard/get-filtered-usage-events")
    private static let eventsFallbackURL = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetFilteredUsageEvents"
    )

    static func readCache() -> CursorUsageCache? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(CursorUsageCache.self, from: data)
    }

    static func writeCache(_ cache: CursorUsageCache) {
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(cache).write(to: cacheURL, options: [.atomic])
        } catch {
            // Cache is best-effort and must never become a zeroed ledger.
        }
    }

    static func refresh(historyDays: Int, now: Date = Date()) throws -> CursorUsageCache {
        let token = try readAccessToken()
        guard let userId = CursorQuotaService.userId(fromJWT: token) else {
            throw TokenStepError.message(L("未登录 Cursor"))
        }
        let lookback = min(max(historyDays, 1), maxLookbackDays)
        let window = dateWindow(lookbackDays: lookback, now: now)
        let events = try fetchEvents(
            userId: userId,
            accessToken: token,
            dashboardUserId: readDashboardUserId(),
            start: window.start,
            end: window.end
        )
        let incoming = bucket(events)
        let mergedDays = replaceWindow(
            existing: readCache()?.days ?? [],
            incoming: incoming,
            windowStart: window.startDate,
            windowEnd: window.endDate
        )
        let cache = CursorUsageCache(fetchedAt: now, days: mergedDays)
        writeCache(cache)
        return cache
    }

    static func events(from payload: Any) -> [CursorUsageEvent] {
        guard let object = payload as? [String: Any] else { return [] }
        let rawEvents = object["usageEventsDisplay"] as? [Any] ?? object["usageEvents"] as? [Any] ?? []
        return rawEvents.compactMap(event(from:))
    }

    static func event(from raw: Any) -> CursorUsageEvent? {
        guard let object = raw as? [String: Any],
              let timestamp = date(from: object["timestamp"])
        else {
            return nil
        }
        let usage = object["tokenUsage"] as? [String: Any] ?? object
        let model = (object["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CursorUsageEvent(
            timestamp: timestamp,
            model: (model?.isEmpty == false ? model : nil) ?? "unknown",
            inputTokens: int(usage["inputTokens"] ?? usage["input_tokens"]),
            outputTokens: int(usage["outputTokens"] ?? usage["output_tokens"]),
            cacheReadTokens: int(usage["cacheReadTokens"] ?? usage["cache_read_tokens"]),
            cacheWriteTokens: int(usage["cacheWriteTokens"] ?? usage["cache_write_tokens"]),
            chargedCents: QuotaJSON.number(object["chargedCents"] ?? usage["totalCents"] ?? usage["total_cents"]) ?? 0
        )
    }

    static func bucket(_ events: [CursorUsageEvent]) -> [CursorUsageDay] {
        var days: [String: DayAccumulator] = [:]
        for event in events {
            let date = DateFormatter.tokenStepDay.string(from: event.timestamp)
            days[date, default: DayAccumulator(date: date)].add(event)
        }
        return days.values
            .map(\.day)
            .sorted { $0.date < $1.date }
    }

    static func replaceWindow(
        existing: [CursorUsageDay],
        incoming: [CursorUsageDay],
        windowStart: String,
        windowEnd: String
    ) -> [CursorUsageDay] {
        let kept = existing.filter { $0.date < windowStart || $0.date > windowEnd }
        return (kept + incoming).sorted { $0.date < $1.date }
    }

    static func merge(_ snapshot: UsageSnapshot, days: [CursorUsageDay]) -> UsageSnapshot {
        let relevantDays = days.filter { $0.totalTokens > 0 || $0.eventCount > 0 }
        guard !relevantDays.isEmpty else { return stripCursor(snapshot) }

        let snapshot = stripCursor(snapshot)
        var dailyByDate = Dictionary(uniqueKeysWithValues: snapshot.daily.map { ($0.date, $0) })
        var workByDate = Dictionary(uniqueKeysWithValues: snapshot.agentWork.map { ($0.date, $0) })
        var rhythmByDate = Dictionary(uniqueKeysWithValues: snapshot.rhythms.map { ($0.date, $0) })

        for day in relevantDays {
            dailyByDate[day.date] = applyCursor(to: dailyByDate[day.date], day: day)
            workByDate[day.date] = applyCursor(to: workByDate[day.date], day: day)
            rhythmByDate[day.date] = applyCursor(to: rhythmByDate[day.date], day: day)
        }

        let daily = dailyByDate.values.sorted { $0.date < $1.date }
        let totalTokens = daily.map(\.totalTokens).reduce(0, +)
        let totalCost = daily.map(\.cost).reduce(0, +)
        let cursorTokens = relevantDays.map(\.totalTokens).reduce(0, +)
        let cursorEvents = relevantDays.map(\.eventCount).reduce(0, +)

        var tools = snapshot.tools.filter { $0.tool != toolName }
        if cursorTokens > 0 {
            tools.append(ToolUsage(tool: toolName, tokens: cursorTokens, percent: nil))
        }
        tools = tools
            .map { tool in
                ToolUsage(
                    tool: tool.tool,
                    tokens: tool.tokens,
                    percent: percent(tool.tokens, of: totalTokens)
                )
            }
            .sorted { $0.tokens > $1.tokens }

        var modelTotals: [String: Int] = [:]
        for day in relevantDays {
            for (model, tokens) in day.models {
                modelTotals[model, default: 0] += tokens
            }
        }
        var models = snapshot.models.filter { $0.tool != toolName }
        for (model, tokens) in modelTotals where tokens > 0 {
            models.append(ModelUsage(model: model, tool: toolName, tokens: tokens, percent: nil))
        }
        models = models
            .map { model in
                ModelUsage(
                    model: model.model,
                    tool: model.tool,
                    tokens: model.tokens,
                    percent: percent(model.tokens, of: totalTokens)
                )
            }
            .sorted { $0.tokens > $1.tokens }

        var sources = snapshot.sources
        sources[toolName] = SourceInfo(cursorOfficialEvents: cursorEvents)

        return UsageSnapshot(
            generatedAt: snapshot.generatedAt,
            timezone: snapshot.timezone ?? "Asia/Shanghai",
            totals: UsageTotals(
                tokens: totalTokens,
                cost: rounded(totalCost, digits: 2),
                activeDays: daily.filter { $0.totalTokens > 0 }.count
            ),
            daily: daily,
            rhythms: rhythmByDate.values.filter { $0.totalTokens > 0 }.sorted { $0.date < $1.date },
            agentWork: workByDate.values.filter { $0.totalTokens > 0 }.sorted { $0.date < $1.date },
            tools: tools,
            models: models,
            sources: sources
        )
    }

    static func dashboardUserId(from payload: Any) -> Int? {
        guard let object = payload as? [String: Any] else { return nil }
        return intOrNil(object["dashboardUserId"] ?? object["dashboard_user_id"])
    }

    static func date(from timestamp: Any?) -> Date? {
        if let number = QuotaJSON.number(timestamp) {
            return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1000 : number)
        }
        if let text = timestamp as? String {
            if let date = ISO8601DateFormatter.cursorUsageFractional.date(from: text) {
                return date
            }
            return ISO8601DateFormatter.cursorUsage.date(from: text)
        }
        return nil
    }

    private static func fetchEvents(
        userId: String,
        accessToken: String,
        dashboardUserId: Int?,
        start: Date,
        end: Date
    ) throws -> [CursorUsageEvent] {
        var collected: [CursorUsageEvent] = []
        var page = 1
        var total = Int.max
        var lastError: Error = TokenStepError.message(L("Cursor 用量暂不可用"))

        while page <= maxPages, collected.count < total {
            do {
                let payload = try postEvents(
                    url: eventsURL,
                    fallbackURL: eventsFallbackURL,
                    userId: userId,
                    accessToken: accessToken,
                    dashboardUserId: dashboardUserId,
                    start: start,
                    end: end,
                    page: page
                )
                let pageEvents = events(from: payload)
                if let object = payload as? [String: Any],
                   let reported = intOrNil(object["totalUsageEventsCount"]) {
                    total = reported
                } else if pageEvents.isEmpty {
                    total = collected.count
                }
                collected.append(contentsOf: pageEvents)
                if pageEvents.isEmpty {
                    break
                }
                page += 1
            } catch {
                lastError = error
                if collected.isEmpty {
                    throw lastError
                }
                break
            }
        }

        if collected.isEmpty, total == Int.max {
            throw lastError
        }
        return collected
    }

    private static func postEvents(
        url: URL?,
        fallbackURL: URL?,
        userId: String,
        accessToken: String,
        dashboardUserId: Int?,
        start: Date,
        end: Date,
        page: Int
    ) throws -> Any {
        var body: [String: Any] = [
            "startDate": String(Int(start.timeIntervalSince1970 * 1000)),
            "endDate": String(Int(end.timeIntervalSince1970 * 1000)),
            "page": page,
            "pageSize": pageSize
        ]
        if let dashboardUserId {
            body["userId"] = dashboardUserId
        }
        do {
            return try postJSON(url: url, userId: userId, accessToken: accessToken, body: body)
        } catch {
            return try postJSON(url: fallbackURL, userId: userId, accessToken: accessToken, body: body)
        }
    }

    private static func postJSON(
        url: URL?,
        userId: String,
        accessToken: String,
        body: [String: Any]
    ) throws -> Any {
        guard let url else {
            throw TokenStepError.message(L("Cursor 用量暂不可用"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("WorkosCursorSessionToken=\(userId)::\(accessToken)", forHTTPHeaderField: "Cookie")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try HTTPJSONClient.jsonObject(for: request)
    }

    private static func readAccessToken() throws -> String {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw TokenStepError.message(L("未登录 Cursor"))
        }
        let rows = SQLiteReadonly.jsonRows(
            database: databaseURL,
            query: "select value from ItemTable where key='cursorAuth/accessToken' limit 1"
        )
        guard let value = rows?.first?["value"] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw TokenStepError.message(L("未登录 Cursor"))
        }
        return value
    }

    static func readDashboardUserId() -> Int? {
        let query = """
        select json_extract(value, '$.dashboardUserId') as dashboardUserId \
        from ItemTable where key='\(applicationUserKey)' limit 1
        """
        guard let row = SQLiteReadonly.jsonRows(database: databaseURL, query: query)?.first else {
            return nil
        }
        return dashboardUserId(from: row)
    }

    private static func dateWindow(lookbackDays: Int, now: Date) -> (start: Date, end: Date, startDate: String, endDate: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let start = calendar.date(
            byAdding: .day,
            value: -(lookbackDays - 1),
            to: calendar.startOfDay(for: now)
        ) ?? now
        return (
            start,
            now,
            DateFormatter.tokenStepDay.string(from: start),
            DateFormatter.tokenStepDay.string(from: now)
        )
    }

    private static func stripCursor(_ snapshot: UsageSnapshot) -> UsageSnapshot {
        let daily = snapshot.daily.compactMap { day -> DailyUsage? in
            var day = day
            guard let cursorTokens = day.tools.removeValue(forKey: toolName) else {
                return day
            }
            day.totalTokens = max(0, day.totalTokens - cursorTokens)
            return day.totalTokens > 0 || !day.tools.isEmpty ? day : nil
        }
        let agentWork = snapshot.agentWork.compactMap { work -> DailyAgentWork? in
            let cursor = work.sources.first(where: { $0.source == toolName })
            guard cursor != nil || work.hourlyBuckets.contains(where: { bucket in
                bucket.sources.contains { $0.source == toolName }
            }) else {
                return work
            }
            let remainingSources = work.sources.filter { $0.source != toolName }
            let cursorHours = work.hourlyBuckets.flatMap(\.sources).filter { $0.source == toolName }
            let hourly = work.hourlyBuckets.map { bucket in
                AgentWorkHourBucket(
                    hour: bucket.hour,
                    sources: bucket.sources.filter { $0.source != toolName }
                )
            }
            let remainingTokens = max(0, work.totalTokens - (cursor?.tokens ?? 0))
            guard remainingTokens > 0 || remainingSources.contains(where: { $0.tokens > 0 }) else {
                return nil
            }
            return DailyAgentWork(
                date: work.date,
                totalTokens: remainingTokens,
                activeHours: hourly.filter { $0.totalTokens > 0 }.count,
                modelRequestCount: max(0, work.modelRequestCount - (cursor?.modelRequestCount ?? 0)),
                toolCallCount: work.toolCallCount,
                sources: remainingSources,
                inputTokens: max(0, work.inputTokens - cursorHours.map(\.inputTokens).reduce(0, +)),
                cachedInputTokens: max(0, work.cachedInputTokens - cursorHours.map(\.cachedInputTokens).reduce(0, +)),
                outputTokens: max(0, work.outputTokens - cursorHours.map(\.outputTokens).reduce(0, +)),
                cacheCoverageComplete: work.cacheCoverageComplete,
                hourlyBuckets: hourly
            )
        }
        let rhythms = snapshot.rhythms
        return UsageSnapshot(
            generatedAt: snapshot.generatedAt,
            timezone: snapshot.timezone,
            totals: snapshot.totals,
            daily: daily,
            rhythms: rhythms,
            agentWork: agentWork,
            tools: snapshot.tools.filter { $0.tool != toolName },
            models: snapshot.models.filter { $0.tool != toolName },
            sources: snapshot.sources.filter { $0.key != toolName }
        )
    }

    private static func applyCursor(to usage: DailyUsage?, day: CursorUsageDay) -> DailyUsage {
        var usage = usage ?? DailyUsage(date: day.date, tools: [:], totalTokens: 0, cost: 0)
        usage.tools[toolName] = day.totalTokens
        for (model, tokens) in day.models {
            usage.models[model, default: 0] += tokens
        }
        usage.totalTokens += day.totalTokens
        usage.cost += day.cost
        return usage
    }

    private static func applyCursor(to work: DailyAgentWork?, day: CursorUsageDay) -> DailyAgentWork {
        let existing = work ?? DailyAgentWork(
            date: day.date,
            totalTokens: 0,
            activeHours: 0,
            modelRequestCount: 0,
            toolCallCount: 0,
            sources: [],
            cacheCoverageComplete: true
        )
        var sources = existing.sources.filter { $0.source != toolName }
        sources.append(
            AgentWorkSource(
                source: toolName,
                tokens: day.totalTokens,
                modelRequestCount: day.eventCount,
                toolCallCount: 0
            )
        )
        var buckets = Dictionary(uniqueKeysWithValues: existing.hourlyBuckets.map { ($0.hour, $0) })
        for hour in day.hourlyBuckets where (0..<24).contains(hour.hour) {
            var bucket = buckets[hour.hour] ?? AgentWorkHourBucket(hour: hour.hour, sources: [])
            var hourSources = bucket.sources.filter { $0.source != toolName }
            hourSources.append(
                AgentWorkHourlySource(
                    source: toolName,
                    tokens: hour.tokens,
                    inputTokens: hour.inputTokens + hour.cachedInputTokens,
                    cachedInputTokens: hour.cachedInputTokens,
                    outputTokens: hour.outputTokens,
                    cacheCoverageComplete: true
                )
            )
            bucket.sources = hourSources
            buckets[hour.hour] = bucket
        }
        let hourly = (0..<24).map { buckets[$0] ?? AgentWorkHourBucket(hour: $0, sources: []) }
        return DailyAgentWork(
            date: day.date,
            totalTokens: existing.totalTokens + day.totalTokens,
            activeHours: hourly.filter { $0.totalTokens > 0 }.count,
            modelRequestCount: existing.modelRequestCount + day.eventCount,
            toolCallCount: existing.toolCallCount,
            sources: sources.sorted { $0.tokens > $1.tokens },
            inputTokens: existing.inputTokens + day.inputTokens + day.cachedInputTokens,
            cachedInputTokens: existing.cachedInputTokens + day.cachedInputTokens,
            outputTokens: existing.outputTokens + day.outputTokens,
            cacheCoverageComplete: existing.sources.isEmpty ? true : existing.cacheCoverageComplete,
            hourlyBuckets: hourly
        )
    }

    private static func applyCursor(to rhythm: DailyRhythm?, day: CursorUsageDay) -> DailyRhythm {
        var hourly = Array(repeating: 0, count: 24)
        if let rhythm {
            for bucket in rhythm.buckets where (0..<24).contains(bucket.hour) {
                hourly[bucket.hour] = bucket.tokens
            }
        }
        for hour in day.hourlyBuckets where (0..<24).contains(hour.hour) {
            hourly[hour.hour] += hour.tokens
        }
        let totalTokens = hourly.reduce(0, +)
        let peakTokens = hourly.max() ?? 0
        let peakHour = hourly.enumerated().first { $0.element == peakTokens && peakTokens > 0 }?.offset
        return DailyRhythm(
            date: day.date,
            buckets: hourly.enumerated().map { HourlyTokenBucket(hour: $0.offset, tokens: $0.element) },
            totalTokens: totalTokens,
            peakHour: peakHour,
            peakTokens: peakTokens,
            activeHours: hourly.filter { $0 > 0 }.count,
            firstActiveHour: hourly.firstIndex { $0 > 0 },
            lastActiveHour: hourly.lastIndex { $0 > 0 },
            primaryTag: rhythm?.primaryTag ?? inferredTag(peakHour: peakHour, totalTokens: totalTokens),
            companionTag: rhythm?.companionTag ?? .morningPlanner
        )
    }

    private static func inferredTag(peakHour: Int?, totalTokens: Int) -> RhythmTag {
        guard totalTokens > 0, let peakHour else { return .quietDay }
        switch peakHour {
        case 5...8: return .earlyStarter
        case 9...12: return .morningPlanner
        case 13...17: return .afternoonBurst
        case 18...20: return .eveningSprint
        case 21...23, 0...2: return .nightAgent
        default: return .steadyCruise
        }
    }

    private static func percent(_ value: Int, of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return rounded(Double(value) / Double(total) * 100, digits: 2)
    }

    private static func rounded(_ value: Double, digits: Int) -> Double {
        let multiplier = pow(10.0, Double(digits))
        return (value * multiplier).rounded() / multiplier
    }

    private static func int(_ value: Any?) -> Int {
        intOrNil(value) ?? 0
    }

    private static func intOrNil(_ value: Any?) -> Int? {
        switch value {
        case let number as Int:
            return number
        case let number as Int64:
            return Int(number)
        case let number as Double:
            return Int(number)
        case let text as String:
            return Int(text)
        default:
            return nil
        }
    }
}

private extension SourceInfo {
    init(cursorOfficialEvents records: Int) {
        self.init(
            status: "ok",
            files: nil,
            records: records,
            rawRecords: nil,
            dedupedRecords: nil,
            skippedRecords: nil,
            strategy: "cursor_official_events",
            exactRecords: nil,
            legacyRecords: nil,
            duplicateRecords: nil,
            counterResets: nil,
            inheritedRecords: nil,
            inheritedTokens: nil,
            unknownBreakdownRecords: nil,
            accountingRevision: nil,
            recalibratedFromRevision: nil,
            tokenBreakdown: nil
        )
    }
}

private struct DayAccumulator {
    var date: String
    var inputTokens = 0
    var cachedInputTokens = 0
    var outputTokens = 0
    var cacheWriteTokens = 0
    var chargedCents = 0.0
    var eventCount = 0
    var models: [String: Int] = [:]
    var hourly: [Int: HourAccumulator] = [:]

    mutating func add(_ event: CursorUsageEvent) {
        inputTokens += event.inputTokens
        cachedInputTokens += event.cacheReadTokens
        outputTokens += event.outputTokens
        cacheWriteTokens += event.cacheWriteTokens
        chargedCents += event.chargedCents
        eventCount += 1
        models[event.model, default: 0] += event.totalTokens
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let hour = calendar.component(.hour, from: event.timestamp)
        hourly[hour, default: HourAccumulator(hour: hour)].add(event)
    }

    var day: CursorUsageDay {
        CursorUsageDay(
            date: date,
            totalTokens: inputTokens + outputTokens + cachedInputTokens + cacheWriteTokens,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            cacheWriteTokens: cacheWriteTokens,
            cost: (chargedCents / 100 * 10_000).rounded() / 10_000,
            eventCount: eventCount,
            models: models,
            hourlyBuckets: hourly.values.sorted { $0.hour < $1.hour }.map(\.bucket)
        )
    }
}

private struct HourAccumulator {
    var hour: Int
    var tokens = 0
    var inputTokens = 0
    var cachedInputTokens = 0
    var outputTokens = 0

    mutating func add(_ event: CursorUsageEvent) {
        tokens += event.totalTokens
        inputTokens += event.inputTokens
        cachedInputTokens += event.cacheReadTokens
        outputTokens += event.outputTokens
    }

    var bucket: CursorUsageHourBucket {
        CursorUsageHourBucket(
            hour: hour,
            tokens: tokens,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens
        )
    }
}

private extension ISO8601DateFormatter {
    static let cursorUsageFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let cursorUsage: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
