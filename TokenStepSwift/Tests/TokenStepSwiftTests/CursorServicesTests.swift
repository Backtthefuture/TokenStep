import Foundation
import XCTest
@testable import TokenStepSwift

final class CursorServicesTests: XCTestCase {
    func testJWTUserIdReadsSub() {
        let payload = #"{"sub":"user_123","email":"a@b.com"}"#
        let encoded = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        let token = "aaa.\(encoded).sig"
        XCTAssertEqual(CursorQuotaService.userId(fromJWT: token), "user_123")
    }

    func testCursorWindowsParseTwoPoolsFromUsageSummary() {
        let payload: [String: Any] = [
            "billingCycleEnd": "2026-09-16T00:00:00.000Z",
            "individualUsage": [
                "plan": [
                    "autoPercentUsed": 1,
                    "apiPercentUsed": 7,
                    "totalPercentUsed": 4
                ]
            ]
        ]
        let windows = CursorQuotaService.windows(from: payload)
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].kind, .cursorModels)
        XCTAssertEqual(windows[0].usedPercent, 1, accuracy: 0.01)
        XCTAssertEqual(windows[0].remainingPercent, 99, accuracy: 0.01)
        XCTAssertEqual(windows[1].kind, .otherModels)
        XCTAssertEqual(windows[1].usedPercent, 7, accuracy: 0.01)
        XCTAssertEqual(windows[1].remainingPercent, 93, accuracy: 0.01)
    }

    func testCursorWindowsTreatOnePercentAsOneNotOneHundred() {
        let payload: [String: Any] = [
            "individualUsage": [
                "plan": [
                    "autoPercentUsed": 1.0,
                    "apiPercentUsed": 0
                ]
            ]
        ]
        let windows = CursorQuotaService.windows(from: payload)
        XCTAssertEqual(windows[0].usedPercent, 1, accuracy: 0.01)
        XCTAssertEqual(windows[1].usedPercent, 0, accuracy: 0.01)
    }

    func testCursorWindowsParseDisplayMessages() {
        XCTAssertEqual(
            CursorQuotaService.percentFromDisplayMessage("You've used 42% of your included total usage") ?? -1,
            42,
            accuracy: 0.01
        )
        let payload: [String: Any] = [
            "autoModelSelectedDisplayMessage": "You've used 1% of your included total usage",
            "namedModelSelectedDisplayMessage": "You've used 7% of your included API usage"
        ]
        let windows = CursorQuotaService.windows(from: payload)
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].kind, .cursorModels)
        XCTAssertEqual(windows[0].usedPercent, 1, accuracy: 0.01)
        XCTAssertEqual(windows[1].kind, .otherModels)
        XCTAssertEqual(windows[1].usedPercent, 7, accuracy: 0.01)
    }

    func testCursorWindowsParsePlanUsage() {
        let payload: [String: Any] = [
            "planUsage": [
                "used": 40,
                "limit": 100,
                "remaining": 60
            ]
        ]
        let windows = CursorQuotaService.windows(from: payload)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].kind, .monthlyCredits)
        XCTAssertEqual(windows[0].usedPercent, 40, accuracy: 0.01)
        XCTAssertEqual(windows[0].remainingPercent, 60, accuracy: 0.01)
    }

    func testCursorCodeSignalReadsTemporaryDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenstep-cursor-l3-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = directory.appendingPathComponent("ai-code-tracking.db")
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let sql = """
        CREATE TABLE ai_code_hashes (
          hash TEXT PRIMARY KEY, source TEXT NOT NULL, fileExtension TEXT,
          fileName TEXT, requestId TEXT, conversationId TEXT,
          timestamp INTEGER, model TEXT, createdAt INTEGER NOT NULL
        );
        INSERT INTO ai_code_hashes VALUES
          ('h1','composer','.swift','/tmp/secret/A.swift','r1','c1',\(now),'grok-4.6',\(now)),
          ('h2','composer','.swift','/tmp/secret/B.swift','r1','c1',\(now),'grok-4.6',\(now)),
          ('h3','composer','.md','/tmp/secret/C.md','r2','c2',\(now),'claude-opus-5',\(now));
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        input.fileHandleForWriting.write(Data(sql.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        CursorCodeSignalService.databaseURL = database
        let signal = try CursorCodeSignalService.read()
        XCTAssertEqual(signal.blockCount, 3)
        XCTAssertEqual(signal.modelCount, 2)
        XCTAssertEqual(signal.conversationCount, 2)
        XCTAssertEqual(signal.requestCount, 2)
        XCTAssertEqual(signal.fileCount, 3)
        XCTAssertEqual(signal.status, "ok")
        XCTAssertFalse(signal.models.contains(where: { $0.name.contains("/") }))
    }

    func testCursorCodeSignalMissingDatabaseIsEmpty() throws {
        CursorCodeSignalService.databaseURL = URL(fileURLWithPath: "/tmp/tokenstep-missing-ai-code-tracking.db")
        let signal = try CursorCodeSignalService.read()
        XCTAssertTrue(signal.isEmpty)
        XCTAssertEqual(signal.status, "missing_db")
    }

    func testQuotaJSONNeverTreatsFailureAsZero() {
        XCTAssertNil(QuotaJSON.percent(used: nil, remaining: nil, total: nil))
        let unavailable = ProviderQuota.unavailable(.cursor, message: "down")
        XCTAssertFalse(unavailable.isAvailable)
        XCTAssertTrue(unavailable.windows.isEmpty)
    }

    func testDashboardUserIdReadsIntAndString() {
        XCTAssertEqual(
            CursorUsageService.dashboardUserId(from: ["dashboardUserId": 405604729]),
            405604729
        )
        XCTAssertEqual(
            CursorUsageService.dashboardUserId(from: ["dashboardUserId": "405604729"]),
            405604729
        )
        XCTAssertNil(CursorUsageService.dashboardUserId(from: ["email": "hidden"]))
    }

    func testCursorUsageEventsBucketAcrossShanghaiMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let beforeMidnight = calendar.date(from: DateComponents(year: 2026, month: 8, day: 16, hour: 23, minute: 30))!
        let afterMidnight = calendar.date(from: DateComponents(year: 2026, month: 8, day: 17, hour: 0, minute: 30))!
        let payload: [String: Any] = [
            "totalUsageEventsCount": 2,
            "usageEventsDisplay": [
                [
                    "timestamp": String(Int(beforeMidnight.timeIntervalSince1970 * 1000)),
                    "model": "composer-1",
                    "chargedCents": 10,
                    "tokenUsage": [
                        "inputTokens": 100,
                        "outputTokens": 20,
                        "cacheReadTokens": 50,
                        "cacheWriteTokens": 5
                    ]
                ],
                [
                    "timestamp": String(Int(afterMidnight.timeIntervalSince1970 * 1000)),
                    "model": "grok-4.6",
                    "chargedCents": 3,
                    "tokenUsage": [
                        "inputTokens": 10,
                        "outputTokens": 4,
                        "cacheReadTokens": 0
                    ]
                ]
            ]
        ]

        let events = CursorUsageService.events(from: payload)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].totalTokens, 175)
        XCTAssertEqual(events[1].totalTokens, 14)

        let days = CursorUsageService.bucket(events)
        XCTAssertEqual(days.map(\.date), ["2026-08-16", "2026-08-17"])
        XCTAssertEqual(days[0].totalTokens, 175)
        XCTAssertEqual(days[0].hourlyBuckets.first?.hour, 23)
        XCTAssertEqual(days[1].totalTokens, 14)
        XCTAssertEqual(days[1].cost, 0.03, accuracy: 0.0001)
        XCTAssertEqual(days[1].models["grok-4.6"], 14)
    }

    func testCursorUsageMergeAddsOfficialTokensToRing() {
        let ledger = UsageSnapshot(
            generatedAt: "2026-08-17T00:00:00Z",
            timezone: "Asia/Shanghai",
            totals: UsageTotals(tokens: 1_000, cost: 0.1, activeDays: 1),
            daily: [
                DailyUsage(date: "2026-08-17", tools: ["Codex": 1_000], models: ["gpt-5": 1_000], totalTokens: 1_000, cost: 0.1)
            ],
            agentWork: [
                DailyAgentWork(
                    date: "2026-08-17",
                    totalTokens: 1_000,
                    activeHours: 1,
                    modelRequestCount: 2,
                    toolCallCount: 1,
                    sources: [AgentWorkSource(source: "Codex", tokens: 1_000, modelRequestCount: 2, toolCallCount: 1)],
                    cacheCoverageComplete: true,
                    hourlyBuckets: [AgentWorkHourBucket(hour: 10, sources: [
                        AgentWorkHourlySource(
                            source: "Codex",
                            tokens: 1_000,
                            inputTokens: 800,
                            cachedInputTokens: 100,
                            outputTokens: 200,
                            cacheCoverageComplete: true
                        )
                    ])]
                )
            ],
            tools: [ToolUsage(tool: "Codex", tokens: 1_000, percent: 100)],
            models: [ModelUsage(model: "gpt-5", tool: "Codex", tokens: 1_000, percent: 100)],
            sources: [:]
        )
        let days = [
            CursorUsageDay(
                date: "2026-08-17",
                totalTokens: 175,
                inputTokens: 100,
                cachedInputTokens: 50,
                outputTokens: 20,
                cacheWriteTokens: 5,
                cost: 0.10,
                eventCount: 1,
                models: ["composer-1": 175],
                hourlyBuckets: [
                    CursorUsageHourBucket(hour: 15, tokens: 175, inputTokens: 100, cachedInputTokens: 50, outputTokens: 20)
                ]
            )
        ]

        let merged = CursorUsageService.merge(ledger, days: days)
        XCTAssertEqual(merged.daily.last?.tools["Cursor"], 175)
        XCTAssertEqual(merged.daily.last?.totalTokens, 1_175)
        XCTAssertEqual(merged.totals.tokens, 1_175)
        XCTAssertEqual(merged.tools.first(where: { $0.tool == "Cursor" })?.tokens, 175)
        XCTAssertEqual(merged.agentWork.last?.sources.first(where: { $0.source == "Cursor" })?.tokens, 175)
        XCTAssertEqual(merged.agentWork.last?.modelRequestCount, 3)
        XCTAssertEqual(merged.agentWork.last?.bucket(hour: 15).sources.first(where: { $0.source == "Cursor" })?.tokens, 175)

        let again = CursorUsageService.merge(merged, days: days)
        XCTAssertEqual(again.daily.last?.tools["Cursor"], 175)
        XCTAssertEqual(again.totals.tokens, 1_175)
    }

    func testCursorUsageFailedRefreshKeepsLastCache() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenstep-cursor-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previous = CursorUsageService.cacheURL
        CursorUsageService.cacheURL = directory.appendingPathComponent("cursor-usage-cache.json")
        defer { CursorUsageService.cacheURL = previous }

        let cache = CursorUsageCache(
            fetchedAt: Date(),
            days: [
                CursorUsageDay(
                    date: "2026-08-17",
                    totalTokens: 8_000,
                    inputTokens: 1_000,
                    cachedInputTokens: 6_000,
                    outputTokens: 1_000,
                    cacheWriteTokens: 0,
                    cost: 1.2,
                    eventCount: 4,
                    models: ["composer-1": 8_000],
                    hourlyBuckets: []
                )
            ]
        )
        CursorUsageService.writeCache(cache)
        XCTAssertEqual(CursorUsageService.readCache()?.days.first?.totalTokens, 8_000)

        let emptyDays = CursorUsageService.bucket([])
        XCTAssertTrue(emptyDays.isEmpty)
        let kept = CursorUsageService.replaceWindow(
            existing: cache.days,
            incoming: emptyDays,
            windowStart: "2026-08-18",
            windowEnd: "2026-08-18"
        )
        XCTAssertEqual(kept.first?.totalTokens, 8_000)

        let encoded = try JSONEncoder().encode(cache)
        let text = String(data: encoded, encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("accessToken"))
        XCTAssertFalse(text.contains("WorkosCursorSessionToken"))
    }

    func testCursorUsageEmptySuccessfulWindowDoesNotInventZeroRing() {
        let ledger = UsageSnapshot.empty
        let merged = CursorUsageService.merge(ledger, days: [])
        XCTAssertEqual(merged.totals.tokens, 0)
        XCTAssertNil(merged.daily.last?.tools["Cursor"])
        XCTAssertFalse(merged.tools.contains(where: { $0.tool == "Cursor" }))
    }
}
