import Foundation
import XCTest
@testable import TokenStepSwift

final class UsageCollectorClaudeCodeTests: XCTestCase {
    func testClaudeCodeDeduplicatesAssistantContentBlocksByMessageID() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepClaudeTests-\(UUID().uuidString)", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let log = project.appendingPathComponent("session.jsonl")
        try fixtureLines.joined(separator: "\n").write(to: log, atomically: true, encoding: .utf8)

        let snapshot = UsageCollector.collectClaudeCodeUsageSnapshot(rootURL: root)

        XCTAssertEqual(snapshot.sources["Claude Code"]?.status, "ok")
        XCTAssertEqual(snapshot.sources["Claude Code"]?.records, 2)
        XCTAssertEqual(snapshot.totals.tokens, 324)
        XCTAssertEqual(snapshot.daily.count, 1)
        XCTAssertEqual(snapshot.daily.first?.date, "2026-06-21")
        XCTAssertEqual(snapshot.daily.first?.tools["Claude Code"], 324)
        XCTAssertEqual(snapshot.daily.first?.models["claude-opus-4-20250514"], 322)
        XCTAssertEqual(snapshot.daily.first?.models["unknown"], 2)
    }

    private var fixtureLines: [String] {
        [
            assistantLine(
                uuid: "block-thinking",
                messageID: "msg_same_response",
                timestamp: "2026-06-21T08:00:00Z",
                model: "claude-opus-4-20250514",
                stopReason: nil,
                input: 10,
                output: 3,
                cacheRead: 100
            ),
            assistantLine(
                uuid: "block-text",
                messageID: "msg_same_response",
                timestamp: "2026-06-21T08:00:01Z",
                model: "claude-opus-4-20250514",
                stopReason: "end_turn",
                input: 10,
                output: 3,
                cacheRead: 100
            ),
            assistantLine(
                uuid: "tool-1",
                messageID: "msg_tool_batch",
                timestamp: "2026-06-21T08:01:00Z",
                model: "claude-opus-4-20250514",
                stopReason: nil,
                input: 7,
                output: 2,
                cacheRead: 200
            ),
            assistantLine(
                uuid: "tool-2",
                messageID: "msg_tool_batch",
                timestamp: "2026-06-21T08:01:01Z",
                model: "claude-opus-4-20250514",
                stopReason: nil,
                input: 7,
                output: 2,
                cacheRead: 200
            ),
            assistantLine(
                uuid: "legacy-1",
                messageID: nil,
                timestamp: "2026-06-21T08:02:00Z",
                model: nil,
                stopReason: "end_turn",
                input: 1,
                output: 1,
                cacheRead: 0
            ),
            assistantLine(
                uuid: "legacy-1",
                messageID: nil,
                timestamp: "2026-06-21T08:02:01Z",
                model: nil,
                stopReason: "end_turn",
                input: 1,
                output: 1,
                cacheRead: 0
            )
        ]
    }

    private func assistantLine(
        uuid: String,
        messageID: String?,
        timestamp: String,
        model: String?,
        stopReason: String?,
        input: Int,
        output: Int,
        cacheRead: Int
    ) -> String {
        var message: [String: Any] = [
            "usage": [
                "input_tokens": input,
                "output_tokens": output,
                "cache_read_input_tokens": cacheRead
            ]
        ]
        if let messageID {
            message["id"] = messageID
        }
        if let model {
            message["model"] = model
        }
        if let stopReason {
            message["stop_reason"] = stopReason
        }

        let object: [String: Any] = [
            "type": "assistant",
            "uuid": uuid,
            "timestamp": timestamp,
            "message": message
        ]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}
