import Darwin
import Foundation

// Driven by script/test_time_zone_collector.sh, which runs one phase per process
// because the collector fixes its zone for the life of the process.
@main
struct TimeZoneFixtureCheck {
    // 2026-07-13T02:30:00Z is 10:30 on 07-13 in Shanghai and 19:30 on 07-12 in Los Angeles.
    static let eventTimestamp = "2026-07-13T02:30:00Z"

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            guard let phase = arguments.first, arguments.count >= 2 else {
                throw FixtureError("usage: <write|check|cache-generation|json-cache> <dir> [args]")
            }
            let dir = URL(fileURLWithPath: arguments[1], isDirectory: true)
            switch phase {
            case "write":
                try writeSources(in: dir)
            case "check":
                guard arguments.count == 4, let hour = Int(arguments[3]) else {
                    throw FixtureError("check needs <day> <hour>")
                }
                try check(dir: dir, expectedDay: arguments[2], expectedHour: hour)
            case "cache-generation":
                let stats = UsageCollector.codexIncrementalCacheStatsForTests(
                    databaseURL: dir.appendingPathComponent("codex-incremental.sqlite3")
                )
                print(stats?.generation ?? -1)
            case "json-cache":
                let reusable = UsageCollector.collectorCacheIsReusableForTests(
                    cacheURL: dir.appendingPathComponent(arguments.count > 2 ? arguments[2] : "collector-cache.json")
                )
                print(reusable ? "reusable" : "discarded")
            default:
                throw FixtureError("unknown phase \(phase)")
            }
        } catch {
            fputs("Time zone fixture failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func check(dir: URL, expectedDay: String, expectedHour: Int) throws {
        let zone = ProcessInfo.processInfo.environment["TOKENSTEP_TIMEZONE"] ?? "?"
        let codex = UsageCollector.collectCodexUsageSnapshotForTests(
            homeURL: dir.appendingPathComponent("home", isDirectory: true),
            cacheURL: dir.appendingPathComponent("codex-incremental.sqlite3")
        )
        try expect(codex.sources["Codex"]?.status == "ok", "[\(zone)] codex status ok")
        try expect(codex.timezone == zone, "[\(zone)] snapshot records zone, got \(codex.timezone ?? "nil")")
        try expect(
            codex.daily.map(\.date) == [expectedDay],
            "[\(zone)] codex day \(expectedDay), got \(codex.daily.map(\.date))"
        )
        try expect(
            codex.rhythms.first?.peakHour == expectedHour,
            "[\(zone)] codex peak hour \(expectedHour), got \(String(describing: codex.rhythms.first?.peakHour))"
        )

        let claude = UsageCollector.collectClaudeCodeUsageSnapshot(
            rootURL: dir.appendingPathComponent("home/.claude/projects", isDirectory: true)
        )
        try expect(
            claude.daily.map(\.date) == [expectedDay],
            "[\(zone)] claude day \(expectedDay), got \(claude.daily.map(\.date))"
        )
        print("PASS [\(zone)] day=\(expectedDay) hour=\(expectedHour)")
    }

    private static func writeSources(in dir: URL) throws {
        let sessions = dir.appendingPathComponent("home/.codex/sessions/2026/07/13", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let usage: [String: Any] = [
            "input_tokens": 800,
            "output_tokens": 200,
            "cached_input_tokens": 500,
            "reasoning_output_tokens": 50,
            "total_tokens": 1_000
        ]
        let codexLines: [[String: Any]] = [
            ["type": "session_meta", "timestamp": "2026-07-13T02:29:00Z", "payload": ["id": "tz-session"]],
            ["type": "turn_context", "timestamp": "2026-07-13T02:29:01Z", "payload": ["model": "gpt-5"]],
            [
                "type": "event_msg",
                "timestamp": eventTimestamp,
                "payload": [
                    "type": "token_count",
                    "info": ["total_token_usage": usage, "last_token_usage": usage]
                ]
            ]
        ]
        try write(codexLines, to: sessions.appendingPathComponent("tz.jsonl"))

        let project = dir.appendingPathComponent("home/.claude/projects/tz", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let claudeLines: [[String: Any]] = [[
            "type": "assistant",
            "timestamp": eventTimestamp,
            "sessionId": "tz-claude",
            "message": [
                "id": "msg_tz",
                "model": "claude-sonnet-4",
                "stop_reason": "end_turn",
                "usage": ["input_tokens": 100, "output_tokens": 20]
            ]
        ]]
        try write(claudeLines, to: project.appendingPathComponent("tz.jsonl"))
    }

    private static func write(_ objects: [[String: Any]], to url: URL) throws {
        let lines = try objects.map { object -> String in
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return String(decoding: data, as: UTF8.self)
        }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw FixtureError(message) }
    }
}

private struct FixtureError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
