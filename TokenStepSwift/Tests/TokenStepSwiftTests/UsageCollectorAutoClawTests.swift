import Foundation
import XCTest
@testable import TokenStepSwift

final class UsageCollectorAutoClawTests: XCTestCase {
    func testAutoClawMissingRootIsReported() throws {
        let missingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepMissingAutoClaw-\(UUID().uuidString)", isDirectory: true)

        let snapshot = UsageCollector.collectUsageSnapshotForTests(
            autoClawRootURLs: [missingRoot]
        )
        XCTAssertEqual(snapshot.sources["AutoClaw"]?.status, "missing")
    }

    func testAutoClawCollectorReadsSessionUsageWithoutMessageContent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepAutoClaw-\(UUID().uuidString)", isDirectory: true)
        // The collector roots represent the AutoClaw `agents` directory itself,
        // matching the production path `~/.openclaw-autoclaw/agents`.
        let sessions = root.appendingPathComponent("auto-legal/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        // Timestamps: 2024-06-01 00:00 UTC and 01:00 UTC.
        let lines = [
            """
            {"type":"message","id":"run-1","timestamp":"2024-06-01T00:00:00.000Z","message":{"role":"assistant","model":"glm-5.3","usage":{"input":100,"output":20,"cacheRead":80,"cacheWrite":5,"reasoningTokens":3,"totalTokens":205}},"content":"must not be parsed"}
            """,
            """
            {"type":"message","id":"run-2","timestamp":"2024-06-01T01:00:00.000Z","message":{"role":"assistant","model":"kimi-k3","usage":{"input":50,"output":10,"cacheRead":40,"cacheWrite":0,"reasoningTokens":0,"totalTokens":100}}}
            """
        ]
        try lines.joined(separator: "\n").write(
            to: sessions.appendingPathComponent("session.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let snapshot = UsageCollector.collectUsageSnapshotForTests(
            autoClawRootURLs: [root],
            historyDays: 400,
            // Keep the fixture timestamps inside the requested 400-day window.
            now: Date(timeIntervalSince1970: 1_719_878_400)
        )

        XCTAssertEqual(snapshot.sources["AutoClaw"]?.status, "ok")
        XCTAssertEqual(snapshot.sources["AutoClaw"]?.files, 1)
        XCTAssertEqual(snapshot.sources["AutoClaw"]?.records, 2)
        XCTAssertEqual(snapshot.totals.tokens, 305)
        XCTAssertEqual(snapshot.daily.first?.tools["AutoClaw"], 305)
        XCTAssertEqual(snapshot.daily.first?.models["glm-5.3"], 205)

        let work = try XCTUnwrap(snapshot.agentWork.first)
        XCTAssertEqual(work.totalTokens, 305)
        XCTAssertEqual(work.outputTokens, 30)
        XCTAssertEqual(work.modelRequestCount, 2)
        XCTAssertEqual(work.sources.first?.source, "AutoClaw")
    }
}
