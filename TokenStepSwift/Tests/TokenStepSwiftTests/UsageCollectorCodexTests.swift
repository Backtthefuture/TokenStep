import Foundation
import XCTest
@testable import TokenStepSwift

final class UsageCollectorCodexTests: XCTestCase {
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
        XCTAssertEqual(rhythm.activeHours, 3)
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
}
