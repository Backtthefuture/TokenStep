import Foundation
import XCTest
@testable import TokenStepSwift

final class UsageCollectorCodexTests: XCTestCase {
    func testCodexCollectorUsesCumulativeDeltasAcrossRepeatedLifecycleEvents() throws {
        let home = try makeTemporaryHome("cumulative")
        let root = home.appendingPathComponent(".codex/sessions/2026/07/13", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let v100 = CodexUsageParts(input: 80, output: 20, cached: 60, reasoning: 5)
        let v160 = CodexUsageParts(input: 125, output: 35, cached: 90, reasoning: 10)
        let v230 = CodexUsageParts(input: 180, output: 50, cached: 120, reasoning: 15)
        let hugeLast = CodexUsageParts(input: 1_600_000, output: 366_220, cached: 1_200_000, reasoning: 300_000)
        let lines = [
            codexMetaLine(id: "cumulative-session", timestamp: "2026-07-13T08:00:00Z"),
            codexContextLine(model: "gpt-5", timestamp: "2026-07-13T08:00:01Z"),
            codexTokenLine(timestamp: "2026-07-13T08:01:00Z", cumulative: v100, last: v100),
            codexTokenLine(
                timestamp: "2026-07-13T08:02:00Z",
                cumulative: v160,
                last: CodexUsageParts(input: 45, output: 15, cached: 30, reasoning: 5)
            ),
            codexTokenLine(timestamp: "2026-07-13T08:03:00Z", cumulative: v160, last: hugeLast),
            codexTokenLine(timestamp: "2026-07-13T08:04:00Z", cumulative: nil, last: hugeLast),
            codexTokenLine(
                timestamp: "2026-07-13T08:05:00Z",
                cumulative: v230,
                last: CodexUsageParts(input: 55, output: 15, cached: 30, reasoning: 5)
            ),
            codexTokenLine(timestamp: "2026-07-13T08:06:00Z", cumulative: v230, last: hugeLast)
        ]
        try writeCodexSession(lines, to: root.appendingPathComponent("cumulative.jsonl"))

        let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home)

        XCTAssertEqual(snapshot.totals.tokens, 230)
        XCTAssertEqual(snapshot.sources["Codex"]?.exactRecords, 3)
        XCTAssertEqual(snapshot.sources["Codex"]?.legacyRecords, 0)
        XCTAssertEqual(snapshot.sources["Codex"]?.duplicateRecords, 2)
        XCTAssertEqual(snapshot.sources["Codex"]?.skippedRecords, 1)
        XCTAssertEqual(
            snapshot.sources["Codex"]?.tokenBreakdown,
            SourceTokenBreakdown(
                processedTokens: 230,
                inputTokens: 180,
                cachedInputTokens: 120,
                uncachedInputTokens: 60,
                outputTokens: 50,
                reasoningTokens: 15
            )
        )
    }

    func testCodexCollectorSeparatesReplayAndIsolatedSubagents() throws {
        let home = try makeTemporaryHome("subagents")
        let root = home.appendingPathComponent(".codex/sessions/2026/07/13", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let parentID = "xctest-parent"

        try writeCodexSession(
            [
                codexMetaLine(id: parentID, timestamp: "2026-07-13T00:00:00Z"),
                codexContextLine(model: "gpt-5", timestamp: "2026-07-13T00:00:01Z"),
                codexTokenLine(timestamp: "2026-07-13T00:01:00Z", cumulative: codexVector(total: 100), last: codexVector(total: 100)),
                codexTokenLine(timestamp: "2026-07-13T00:02:00Z", cumulative: codexVector(total: 200), last: codexVector(total: 100)),
                codexTokenLine(timestamp: "2026-07-13T00:03:00Z", cumulative: codexVector(total: 300), last: codexVector(total: 100))
            ],
            to: root.appendingPathComponent("99-parent.jsonl")
        )
        try writeCodexSession(
            [
                codexMetaLine(id: "xctest-replay", timestamp: "2026-07-13T00:04:00Z", parentID: parentID),
                codexMetaLine(id: parentID, timestamp: "2026-07-13T00:04:01Z"),
                codexContextLine(model: "gpt-5", timestamp: "2026-07-13T00:04:02Z"),
                codexTokenLine(timestamp: "2026-07-13T00:05:00Z", cumulative: codexVector(total: 100), last: codexVector(total: 100)),
                codexTokenLine(timestamp: "2026-07-13T00:06:00Z", cumulative: codexVector(total: 200), last: codexVector(total: 100)),
                codexTokenLine(timestamp: "2026-07-13T00:07:00Z", cumulative: codexVector(total: 300), last: codexVector(total: 100)),
                codexTokenLine(timestamp: "2026-07-13T00:08:00Z", cumulative: codexVector(total: 360), last: codexVector(total: 60))
            ],
            to: root.appendingPathComponent("00-replay-child.jsonl")
        )
        try writeCodexSession(
            [
                codexMetaLine(id: "xctest-isolated", timestamp: "2026-07-13T00:04:00Z", parentID: parentID),
                codexContextLine(model: "gpt-5", timestamp: "2026-07-13T00:04:02Z"),
                codexTokenLine(timestamp: "2026-07-13T00:05:00Z", cumulative: codexVector(total: 20), last: codexVector(total: 20)),
                codexTokenLine(timestamp: "2026-07-13T00:06:00Z", cumulative: codexVector(total: 50), last: codexVector(total: 30))
            ],
            to: root.appendingPathComponent("01-isolated-child.jsonl")
        )

        let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home)

        XCTAssertEqual(snapshot.totals.tokens, 410)
        XCTAssertEqual(snapshot.sources["Codex"]?.inheritedTokens, 300)
        XCTAssertGreaterThan(snapshot.sources["Codex"]?.inheritedRecords ?? 0, 0)
    }

    func testCodexCollectorCacheHitAppendAndRebuildRemainStable() throws {
        let home = try makeTemporaryHome("cache")
        let root = home.appendingPathComponent(".codex/sessions/2026/07/13", isDirectory: true)
        let cache = home.appendingPathComponent("cache/codex-incremental.sqlite3")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("stable.jsonl")
        let initial = [
            codexMetaLine(id: "cache-session", timestamp: "2026-07-13T11:00:00Z"),
            codexContextLine(model: "gpt-5", timestamp: "2026-07-13T11:00:01Z"),
            codexTokenLine(timestamp: "2026-07-13T11:01:00Z", cumulative: codexVector(total: 100), last: codexVector(total: 100)),
            codexTokenLine(timestamp: "2026-07-13T11:02:00Z", cumulative: codexVector(total: 160), last: codexVector(total: 60))
        ]
        try writeCodexSession(initial, to: file)

        let first = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home, cacheURL: cache)
        let firstStats = try XCTUnwrap(
            UsageCollector.codexIncrementalCacheStatsForTests(databaseURL: cache)
        )
        let repeated = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home, cacheURL: cache)
        XCTAssertEqual(first.totals.tokens, 160)
        XCTAssertEqual(repeated.totals.tokens, first.totals.tokens)
        XCTAssertEqual(
            UsageCollector.codexIncrementalCacheStatsForTests(databaseURL: cache),
            firstStats
        )
        XCTAssertEqual(firstStats.sessions, 1)
        XCTAssertEqual(firstStats.records, 2)

        try writeCodexSession(
            initial + [
                codexTokenLine(timestamp: "2026-07-13T11:03:00Z", cumulative: codexVector(total: 230), last: codexVector(total: 70))
            ],
            to: file
        )
        let appended = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home, cacheURL: cache)
        XCTAssertEqual(appended.totals.tokens, 230)
        let appendedStats = try XCTUnwrap(
            UsageCollector.codexIncrementalCacheStatsForTests(databaseURL: cache)
        )
        XCTAssertEqual(appendedStats.generation, firstStats.generation + 1)
        XCTAssertEqual(appendedStats.sessions, 1)
        XCTAssertEqual(appendedStats.records, 3)

        let rebuiltCache = home.appendingPathComponent("cache/codex-rebuilt.sqlite3")
        let rebuilt = UsageCollector.collectCodexUsageSnapshotForTests(
            homeURL: home,
            cacheURL: rebuiltCache
        )
        XCTAssertEqual(rebuilt.totals.tokens, appended.totals.tokens)
        XCTAssertEqual(rebuilt.sources["Codex"]?.tokenBreakdown, appended.sources["Codex"]?.tokenBreakdown)
    }

    func testCodexGPT54PricingTreatsCachedAndReasoningAsSubsets() throws {
        let home = try makeTemporaryHome("pricing")
        let root = home.appendingPathComponent(".codex/sessions/2026/07/13", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let usage = CodexUsageParts(input: 1_000_000, output: 200_000, cached: 400_000, reasoning: 100_000)
        try writeCodexSession(
            [
                codexMetaLine(id: "pricing-session", timestamp: "2026-07-13T12:00:00Z"),
                codexContextLine(model: "gpt-5.4", timestamp: "2026-07-13T12:00:01Z"),
                codexTokenLine(timestamp: "2026-07-13T12:01:00Z", cumulative: usage, last: usage)
            ],
            to: root.appendingPathComponent("pricing.jsonl")
        )

        let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home)

        XCTAssertEqual(snapshot.totals.tokens, 1_200_000)
        XCTAssertEqual(snapshot.totals.cost, 4.6, accuracy: 0.0001)
        XCTAssertEqual(snapshot.sources["Codex"]?.tokenBreakdown?.cachedInputTokens, 400_000)
        XCTAssertEqual(snapshot.sources["Codex"]?.tokenBreakdown?.reasoningTokens, 100_000)
    }

    func testCodexCollectorSplitsDeltasAtShanghaiMidnight() throws {
        let home = try makeTemporaryHome("midnight")
        let root = home.appendingPathComponent(".codex/sessions/2026/06/21", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writeCodexSession(
            [
                codexMetaLine(id: "midnight-session", timestamp: "2026-06-21T15:59:00Z"),
                codexContextLine(model: "gpt-5", timestamp: "2026-06-21T15:59:01Z"),
                codexTokenLine(timestamp: "2026-06-21T15:59:59Z", cumulative: codexVector(total: 100), last: codexVector(total: 100)),
                codexTokenLine(timestamp: "2026-06-21T16:00:00Z", cumulative: codexVector(total: 160), last: codexVector(total: 60))
            ],
            to: root.appendingPathComponent("midnight.jsonl")
        )

        let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home)

        XCTAssertEqual(snapshot.daily.first(where: { $0.date == "2026-06-21" })?.totalTokens, 100)
        XCTAssertEqual(snapshot.daily.first(where: { $0.date == "2026-06-22" })?.totalTokens, 60)
        XCTAssertEqual(snapshot.rhythm(for: "2026-06-21")?.bucket(hour: 23).tokens, 100)
        XCTAssertEqual(snapshot.rhythm(for: "2026-06-22")?.bucket(hour: 0).tokens, 60)
    }

    func testDefaultCodexCollectorIgnoresArchivedSessions() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepCodexTests-\(UUID().uuidString)", isDirectory: true)
        let liveRoot = home.appendingPathComponent(".codex/sessions/2026/06/22", isDirectory: true)
        let archivedRoot = home.appendingPathComponent(".codex/archived_sessions/2026/06/22", isDirectory: true)
        try FileManager.default.createDirectory(at: liveRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archivedRoot, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: home)
        }

        try codexLines(sessionID: "live-session", totalTokens: 120)
            .joined(separator: "\n")
            .write(to: liveRoot.appendingPathComponent("live.jsonl"), atomically: true, encoding: .utf8)
        try codexLines(sessionID: "archived-session", totalTokens: 900_000_000)
            .joined(separator: "\n")
            .write(to: archivedRoot.appendingPathComponent("archived.jsonl"), atomically: true, encoding: .utf8)

        let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home)

        XCTAssertEqual(snapshot.sources["Codex"]?.status, "ok")
        XCTAssertEqual(snapshot.sources["Codex"]?.files, 1)
        XCTAssertEqual(snapshot.sources["Codex"]?.records, 1)
        XCTAssertEqual(snapshot.totals.tokens, 120)
        XCTAssertEqual(snapshot.daily.count, 1)
        XCTAssertEqual(snapshot.daily.first?.date, "2026-06-22")
        XCTAssertEqual(snapshot.daily.first?.tools["Codex"], 120)
        XCTAssertEqual(snapshot.rhythms.first?.bucket(hour: 13).tokens, 120)
    }

    func testCodexCollectorBuildsDailyRhythmBuckets() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepCodexRhythmTests-\(UUID().uuidString)", isDirectory: true)
        let liveRoot = home.appendingPathComponent(".codex/sessions/2026/06/21", isDirectory: true)
        try FileManager.default.createDirectory(at: liveRoot, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: home)
        }

        let lines = [
            codexLines(sessionID: "afternoon-a", totalTokens: 400, timestamp: "2026-06-21T07:00:00Z"),
            codexLines(sessionID: "afternoon-b", totalTokens: 350, timestamp: "2026-06-21T08:00:00Z"),
            codexLines(sessionID: "night-c", totalTokens: 100, timestamp: "2026-06-21T14:00:00Z")
        ].flatMap { $0 }
        try lines.joined(separator: "\n")
            .write(to: liveRoot.appendingPathComponent("rhythm.jsonl"), atomically: true, encoding: .utf8)

        let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home)
        let rhythm = try XCTUnwrap(snapshot.rhythm(for: "2026-06-21"))

        XCTAssertEqual(rhythm.totalTokens, 850)
        // The 100-token night trace remains visible in its bucket, but is below
        // the 30%-of-peak significance threshold used for active-hour labeling.
        XCTAssertEqual(rhythm.activeHours, 2)
        XCTAssertEqual(rhythm.peakHour, 15)
        XCTAssertEqual(rhythm.peakTokens, 400)
        XCTAssertEqual(rhythm.bucket(hour: 15).tokens, 400)
        XCTAssertEqual(rhythm.bucket(hour: 16).tokens, 350)
        XCTAssertEqual(rhythm.bucket(hour: 22).tokens, 100)
        XCTAssertEqual(rhythm.primaryTag, .afternoonBurst)
        XCTAssertEqual(rhythm.companionTag, .morningPlanner)
    }

    func testCodexCollectorPrefersDoublePeakOverMorningShare() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepCodexDoublePeakTests-\(UUID().uuidString)", isDirectory: true)
        let liveRoot = home.appendingPathComponent(".codex/sessions/2026/06/21", isDirectory: true)
        try FileManager.default.createDirectory(at: liveRoot, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: home)
        }

        let lines = [
            codexLines(sessionID: "morning-small", totalTokens: 100, timestamp: "2026-06-21T02:00:00Z"),
            codexLines(sessionID: "noon-peak", totalTokens: 500, timestamp: "2026-06-21T03:00:00Z"),
            codexLines(sessionID: "noon-tail", totalTokens: 260, timestamp: "2026-06-21T04:00:00Z"),
            codexLines(sessionID: "evening-peak", totalTokens: 520, timestamp: "2026-06-21T12:00:00Z"),
            codexLines(sessionID: "night-trace", totalTokens: 5, timestamp: "2026-06-21T15:00:00Z")
        ].flatMap { $0 }
        try lines.joined(separator: "\n")
            .write(to: liveRoot.appendingPathComponent("double-peak.jsonl"), atomically: true, encoding: .utf8)

        let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home)
        let rhythm = try XCTUnwrap(snapshot.rhythm(for: "2026-06-21"))

        XCTAssertEqual(rhythm.peakHour, 20)
        XCTAssertEqual(rhythm.primaryTag, .doublePeak)
        XCTAssertLessThan(rhythm.activeHours, 5)
        XCTAssertEqual(rhythm.bucket(hour: 23).tokens, 5)
    }

    private func codexLines(
        sessionID: String,
        totalTokens: Int,
        timestamp: String = "2026-06-22T05:00:00Z"
    ) -> [String] {
        [
            jsonLine([
                "type": "session_meta",
                "timestamp": timestamp,
                "payload": ["id": sessionID]
            ]),
            jsonLine([
                "type": "turn_context",
                "timestamp": timestamp,
                "payload": ["model": "gpt-5"]
            ]),
            jsonLine([
                "type": "event_msg",
                "timestamp": timestamp,
                "payload": [
                    "type": "token_count",
                    "info": [
                        "last_token_usage": [
                            "total_tokens": totalTokens
                        ]
                    ]
                ]
            ])
        ]
    }

    private func jsonLine(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    private func makeTemporaryHome(_ label: String) throws -> URL {
        let home = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("TokenStepCodexXCTest-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: home)
        }
        return home
    }

    private func writeCodexSession(_ lines: [String], to url: URL) throws {
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func codexMetaLine(id: String, timestamp: String, parentID: String? = nil) -> String {
        var payload: [String: Any] = ["id": id]
        if let parentID {
            payload["source"] = [
                "subagent": [
                    "thread_spawn": ["parent_thread_id": parentID]
                ]
            ]
        }
        return jsonLine([
            "type": "session_meta",
            "timestamp": timestamp,
            "payload": payload
        ])
    }

    private func codexContextLine(model: String, timestamp: String) -> String {
        jsonLine([
            "type": "turn_context",
            "timestamp": timestamp,
            "payload": ["model": model]
        ])
    }

    private func codexTokenLine(
        timestamp: String,
        cumulative: CodexUsageParts?,
        last: CodexUsageParts?
    ) -> String {
        var info: [String: Any] = [:]
        if let cumulative {
            info["total_token_usage"] = cumulative.dictionary
        }
        if let last {
            info["last_token_usage"] = last.dictionary
        }
        return jsonLine([
            "type": "event_msg",
            "timestamp": timestamp,
            "payload": [
                "type": "token_count",
                "info": info
            ]
        ])
    }

    private func codexVector(total: Int) -> CodexUsageParts {
        let output = max(1, total / 5)
        return CodexUsageParts(
            input: total - output,
            output: output,
            cached: min(total - output, total / 2),
            reasoning: min(output, total / 10)
        )
    }

    private struct CodexUsageParts {
        var input: Int
        var output: Int
        var cached: Int
        var reasoning: Int

        var dictionary: [String: Any] {
            [
                "input_tokens": input,
                "output_tokens": output,
                "cached_input_tokens": cached,
                "reasoning_output_tokens": reasoning,
                "total_tokens": input + output
            ]
        }
    }
}
