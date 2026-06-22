import Foundation

@main
struct CCSwitchProxyFixtureCheck {
    static func main() throws {
        try runCCSwitchChecks()
        try runClaudeCodeChecks()
        try runCodexArchivedSessionChecks()
        try runCrossSourceDedupeChecks()
        print("Usage collector fixture checks passed")
    }

    private static func runCCSwitchChecks() throws {
        let database = try makeFixtureDatabase()
        defer {
            try? FileManager.default.removeItem(at: database.deletingLastPathComponent())
        }

        let snapshot = UsageCollector.collectCCSwitchProxyUsageSnapshot(databaseURL: database)

        try assertEqual(snapshot.sources["CC Switch Proxy"]?.status, "ok", "source status")
        try assertEqual(snapshot.sources["CC Switch Proxy"]?.records, 2, "source records")
        try assertEqual(snapshot.totals.tokens, 168, "total tokens")
        try assertEqual(snapshot.totals.cost, 0.46, "total cost")
        try assertEqual(snapshot.daily.first?.date, "2024-06-01", "daily date")
        try assertEqual(snapshot.daily.first?.tools["Claude Code via CC Switch"], 155, "claude tool tokens")
        try assertEqual(snapshot.daily.first?.tools["Codex via CC Switch"], 13, "codex tool tokens")
        try assertEqual(snapshot.daily.first?.models["claude-priced"], 155, "priced model tokens")
        try assertNil(snapshot.daily.first?.models["claude-session-priced"], "session model tokens")
        try assertNil(snapshot.daily.first?.models["codex-session-priced"], "codex session model tokens")
        try assertEqual(snapshot.daily.first?.models["GPT-5.4"], 13, "model fallback tokens")

        let emptyDatabase = try makeFixtureDatabase(rowsSQL: """
        insert into proxy_request_logs (
            request_id, provider_id, app_type, model,
            input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
            total_cost_usd, status_code, created_at, data_source, request_model, pricing_model
        ) values
            ('failed-session', 'provider-c', 'claude', 'ignored-model', 9000, 9000, 0, 0, '9.99', 500, 1717207200, 'codex_session', 'ignored', 'ignored'),
            ('zero-session', 'provider-b', 'codex', 'ignored-zero', 0, 0, 0, 0, '0.00', 200, 1717203600, 'opencode_session', 'ignored', 'ignored');
        """)
        defer {
            try? FileManager.default.removeItem(at: emptyDatabase.deletingLastPathComponent())
        }

        let emptySnapshot = UsageCollector.collectCCSwitchProxyUsageSnapshot(databaseURL: emptyDatabase)
        try assertEqual(emptySnapshot.sources["CC Switch Proxy"]?.status, "missing_valid_rows", "empty source status")
        try assertEqual(emptySnapshot.totals.tokens, 0, "empty total tokens")

        let legacyDatabase = try makeLegacyDatabaseWithoutDataSource()
        defer {
            try? FileManager.default.removeItem(at: legacyDatabase.deletingLastPathComponent())
        }

        let legacySnapshot = UsageCollector.collectCCSwitchProxyUsageSnapshot(databaseURL: legacyDatabase)
        try assertEqual(
            legacySnapshot.sources["CC Switch Proxy"]?.status,
            "schema_missing_data_source",
            "legacy source status"
        )
        try assertEqual(legacySnapshot.totals.tokens, 0, "legacy total tokens")

        let largeDatabase = try makeFixtureDatabase(rowsSQL: largeRowsSQL)
        defer {
            try? FileManager.default.removeItem(at: largeDatabase.deletingLastPathComponent())
        }

        let largeSnapshot = UsageCollector.collectCCSwitchProxyUsageSnapshot(databaseURL: largeDatabase)
        try assertEqual(largeSnapshot.sources["CC Switch Proxy"]?.status, "ok", "large source status")
        try assertEqual(largeSnapshot.sources["CC Switch Proxy"]?.records, 1_500, "large source records")
        try assertEqual(largeSnapshot.totals.tokens, 3_000, "large total tokens")
    }

    private static func runClaudeCodeChecks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepClaudeFixture-\(UUID().uuidString)", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let log = project.appendingPathComponent("session.jsonl")
        let lines = [
            claudeAssistantLine(
                uuid: "block-thinking",
                messageID: "msg_same_response",
                timestamp: "2026-06-21T08:00:00Z",
                model: "claude-opus-4-20250514",
                stopReason: nil,
                input: 10,
                output: 3,
                cacheRead: 100
            ),
            claudeAssistantLine(
                uuid: "block-text",
                messageID: "msg_same_response",
                timestamp: "2026-06-21T08:00:01Z",
                model: "claude-opus-4-20250514",
                stopReason: "end_turn",
                input: 10,
                output: 3,
                cacheRead: 100
            ),
            claudeAssistantLine(
                uuid: "tool-1",
                messageID: "msg_tool_batch",
                timestamp: "2026-06-21T08:01:00Z",
                model: "claude-opus-4-20250514",
                stopReason: nil,
                input: 7,
                output: 2,
                cacheRead: 200
            ),
            claudeAssistantLine(
                uuid: "tool-2",
                messageID: "msg_tool_batch",
                timestamp: "2026-06-21T08:01:01Z",
                model: "claude-opus-4-20250514",
                stopReason: nil,
                input: 7,
                output: 2,
                cacheRead: 200
            ),
            claudeAssistantLine(
                uuid: "legacy-1",
                messageID: nil,
                timestamp: "2026-06-21T08:02:00Z",
                model: nil,
                stopReason: "end_turn",
                input: 1,
                output: 1,
                cacheRead: 0
            ),
            claudeAssistantLine(
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
        try lines.joined(separator: "\n").write(to: log, atomically: true, encoding: .utf8)

        let snapshot = UsageCollector.collectClaudeCodeUsageSnapshot(rootURL: root)
        try assertEqual(snapshot.sources["Claude Code"]?.status, "ok", "claude source status")
        try assertEqual(snapshot.sources["Claude Code"]?.records, 3, "claude source records")
        try assertEqual(snapshot.totals.tokens, 324, "claude total tokens")
        try assertEqual(snapshot.daily.first?.date, "2026-06-21", "claude daily date")
        try assertEqual(snapshot.daily.first?.tools["Claude Code"], 324, "claude tool tokens")
        try assertEqual(snapshot.daily.first?.models["claude-opus-4-20250514"], 322, "claude model tokens")
        try assertEqual(snapshot.daily.first?.models["unknown"], 2, "claude fallback model tokens")
    }

    private static func runCrossSourceDedupeChecks() throws {
        try runClaudeProxyDedupeChecks()
        try runCodexProxyDedupeChecks()
    }

    private static func runCodexArchivedSessionChecks() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepCodexArchivedFixture-\(UUID().uuidString)", isDirectory: true)
        let liveRoot = home.appendingPathComponent(".codex/sessions/2026/06/22", isDirectory: true)
        let archivedRoot = home.appendingPathComponent(".codex/archived_sessions/2026/06/22", isDirectory: true)
        try FileManager.default.createDirectory(at: liveRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archivedRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: home)
        }

        try codexLines(sessionID: "live-session", totalTokens: 120)
            .joined(separator: "\n")
            .write(to: liveRoot.appendingPathComponent("live.jsonl"), atomically: true, encoding: .utf8)
        try codexLines(sessionID: "archived-session", totalTokens: 900_000_000)
            .joined(separator: "\n")
            .write(to: archivedRoot.appendingPathComponent("archived.jsonl"), atomically: true, encoding: .utf8)

        let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home)
        try assertEqual(snapshot.sources["Codex"]?.status, "ok", "codex archived source status")
        try assertEqual(snapshot.sources["Codex"]?.files, 1, "codex archived source files")
        try assertEqual(snapshot.sources["Codex"]?.records, 1, "codex archived source records")
        try assertEqual(snapshot.totals.tokens, 120, "codex archived total tokens")
        try assertEqual(snapshot.daily.first?.date, "2026-06-22", "codex archived daily date")
        try assertEqual(snapshot.daily.first?.tools["Codex"], 120, "codex archived tool tokens")
    }

    private static func runClaudeProxyDedupeChecks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepClaudeDedupeFixture-\(UUID().uuidString)", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let log = project.appendingPathComponent("session.jsonl")
        let lines = [
            claudeAssistantLine(
                uuid: "dedupe-claude-1",
                messageID: "msg-dedupe-claude-1",
                timestamp: "2026-06-21T08:00:00Z",
                model: "claude-opus-4-20250514",
                stopReason: "end_turn",
                input: 10,
                output: 3,
                cacheRead: 100,
                requestID: "req-claude-1",
                sessionID: "session-claude-1"
            )
        ]
        try lines.joined(separator: "\n").write(to: log, atomically: true, encoding: .utf8)

        let database = try makeFixtureDatabase(rowsSQL: """
        insert into proxy_request_logs (
            request_id, provider_id, app_type, model,
            input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
            total_cost_usd, status_code, created_at, data_source, request_model, pricing_model
        ) values
            ('req-claude-1', 'provider-a', 'claude', 'claude-opus-4-20250514', 10, 3, 100, 0, '0.12', 200, 1782028800, 'proxy', 'claude-opus-4-20250514', 'claude-opus-4-20250514'),
            ('req-claude-2', 'provider-a', 'claude', 'claude-opus-4-20250514', 20, 4, 0, 0, '0.24', 200, 1782028860, 'proxy', 'claude-opus-4-20250514', 'claude-opus-4-20250514'),
            ('req-gemini-1', 'provider-b', 'gemini', 'gemini-2.5-pro', 5, 1, 0, 0, '0.06', 200, 1782028920, 'proxy', 'gemini-2.5-pro', 'gemini-2.5-pro');
        """)
        defer {
            try? FileManager.default.removeItem(at: database.deletingLastPathComponent())
        }

        let snapshot = UsageCollector.collectUsageSnapshotForTests(
            claudeRootURL: root,
            ccSwitchDatabaseURL: database
        )

        let source = snapshot.sources["CC Switch Proxy"]
        try assertEqual(source?.status, "ok", "claude dedupe source status")
        try assertEqual(source?.rawRecords, 3, "claude dedupe raw proxy records")
        try assertEqual(source?.records, 2, "claude dedupe kept proxy records")
        try assertEqual(source?.dedupedRecords, 1, "claude dedupe skipped duplicate proxy records")
        try assertEqual(source?.strategy, "request_level_dedupe", "claude dedupe strategy")
        try assertEqual(snapshot.totals.tokens, 143, "claude dedupe total tokens")
        try assertEqual(snapshot.totals.cost, 0.42, "claude dedupe total cost")
        try assertEqual(snapshot.daily.first?.tools["Claude Code"], 113, "claude native tokens")
        try assertEqual(snapshot.daily.first?.tools["Claude Code via CC Switch"], 24, "claude proxy residual tokens")
        try assertEqual(snapshot.daily.first?.tools["Gemini via CC Switch"], 6, "gemini proxy residual tokens")
    }

    private static func runCodexProxyDedupeChecks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepCodexDedupeFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let log = root.appendingPathComponent("session.jsonl")
        let lines = [
            jsonLine([
                "type": "session_meta",
                "timestamp": "2026-06-21T09:00:00Z",
                "payload": ["id": "codex-session-1"]
            ]),
            jsonLine([
                "type": "turn_context",
                "timestamp": "2026-06-21T09:00:00Z",
                "payload": ["model": "gpt-5.4"]
            ]),
            jsonLine([
                "type": "event_msg",
                "timestamp": "2026-06-21T09:00:00Z",
                "payload": [
                    "type": "token_count",
                    "info": [
                        "last_token_usage": [
                            "input_tokens": 30,
                            "output_tokens": 5,
                            "cache_read_input_tokens": 10
                        ]
                    ]
                ]
            ])
        ]
        try lines.joined(separator: "\n").write(to: log, atomically: true, encoding: .utf8)

        let database = try makeFixtureDatabase(rowsSQL: """
        insert into proxy_request_logs (
            request_id, provider_id, app_type, model,
            input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
            total_cost_usd, status_code, created_at, data_source, request_model, pricing_model
        ) values
            ('proxy-codex-strong-match', 'provider-a', 'codex', 'gpt-5.4', 30, 5, 10, 0, '0.45', 200, 1782032400, 'proxy', 'gpt-5.4', '');
        """)
        defer {
            try? FileManager.default.removeItem(at: database.deletingLastPathComponent())
        }

        let snapshot = UsageCollector.collectUsageSnapshotForTests(
            codexRoots: [root],
            ccSwitchDatabaseURL: database
        )

        let source = snapshot.sources["CC Switch Proxy"]
        try assertEqual(source?.status, "all_deduped", "codex dedupe source status")
        try assertEqual(source?.rawRecords, 1, "codex dedupe raw proxy records")
        try assertEqual(source?.records, 0, "codex dedupe kept proxy records")
        try assertEqual(source?.dedupedRecords, 1, "codex dedupe duplicate proxy records")
        try assertEqual(snapshot.totals.tokens, 45, "codex dedupe total tokens")
        try assertEqual(snapshot.totals.cost, 0.45, "codex dedupe total cost")
        try assertEqual(snapshot.daily.first?.tools["Codex"], 45, "codex native tokens")
        try assertNil(snapshot.daily.first?.tools["Codex via CC Switch"], "codex proxy duplicate tokens")
    }

    private static func codexLines(sessionID: String, totalTokens: Int) -> [String] {
        [
            jsonLine([
                "type": "session_meta",
                "timestamp": "2026-06-22T05:00:00Z",
                "payload": ["id": sessionID]
            ]),
            jsonLine([
                "type": "turn_context",
                "timestamp": "2026-06-22T05:00:00Z",
                "payload": ["model": "gpt-5"]
            ]),
            jsonLine([
                "type": "event_msg",
                "timestamp": "2026-06-22T05:00:00Z",
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

    private static func makeFixtureDatabase(rowsSQL: String = defaultRowsSQL) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepCCSwitchFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = directory.appendingPathComponent("cc-switch.db")
        try runSQLite(database: database, sql: """
        create table proxy_request_logs (
            request_id text primary key,
            provider_id text not null,
            app_type text not null,
            model text not null,
            input_tokens integer not null default 0,
            output_tokens integer not null default 0,
            cache_read_tokens integer not null default 0,
            cache_creation_tokens integer not null default 0,
            total_cost_usd text not null default '0',
            status_code integer not null,
            created_at integer not null,
            data_source text not null default 'proxy',
            request_model text,
            pricing_model text
        );
        \(rowsSQL)
        """)
        return database
    }

    private static func makeLegacyDatabaseWithoutDataSource() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepCCSwitchLegacyFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = directory.appendingPathComponent("cc-switch.db")
        try runSQLite(database: database, sql: """
        create table proxy_request_logs (
            request_id text primary key,
            provider_id text not null,
            app_type text not null,
            model text not null,
            input_tokens integer not null default 0,
            output_tokens integer not null default 0,
            cache_read_tokens integer not null default 0,
            cache_creation_tokens integer not null default 0,
            total_cost_usd text not null default '0',
            status_code integer not null,
            created_at integer not null,
            request_model text,
            pricing_model text
        );
        insert into proxy_request_logs (
            request_id, provider_id, app_type, model,
            input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
            total_cost_usd, status_code, created_at, request_model, pricing_model
        ) values
            ('legacy-proxy-1', 'provider-a', 'claude', 'claude-raw', 100, 20, 30, 5, '0.12', 200, 1717200000, 'claude-request', 'claude-priced');
        """)
        return database
    }

    private static let defaultRowsSQL = """
    insert into proxy_request_logs (
        request_id, provider_id, app_type, model,
        input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
        total_cost_usd, status_code, created_at, data_source, request_model, pricing_model
    ) values
        ('proxy-1', 'provider-a', 'claude', 'claude-raw', 100, 20, 30, 5, '0.12', 200, 1717200000, 'proxy', 'claude-request', 'claude-priced'),
        ('proxy-2', 'provider-b', 'codex', 'gpt-5.4', 10, 3, 0, 0, '0.34', 201, 1717203600, 'proxy', 'gpt-5-request', ''),
        ('session-import', 'provider-c', 'claude', 'claude-session-raw', 21, 19, 0, 0, '0.10', 200, 1717207200, 'session_log', 'claude-session-request', 'claude-session-priced'),
        ('codex-import', 'provider-c', 'codex', 'codex-session-raw', 99, 1, 0, 0, '0.20', 200, 1717207200, 'codex_session', 'codex-session-request', 'codex-session-priced'),
        ('failed-proxy', 'provider-d', 'gemini', 'ignored-gemini', 1000, 1000, 0, 0, '8.88', 500, 1717207200, 'proxy', 'ignored', 'ignored'),
        ('zero-proxy', 'provider-e', 'codex', 'ignored-zero', 0, 0, 0, 0, '7.77', 200, 1717207200, 'codex_session', 'ignored', 'ignored');
    """

    private static var largeRowsSQL: String {
        let rows = (0..<1_500).map { index in
            "('bulk-\(index)', 'provider-a', 'codex', 'gpt-5.4', 1, 1, 0, 0, '0.001', 200, 1717200000, 'proxy', 'gpt-5-request', '')"
        }.joined(separator: ",\n")
        return """
        insert into proxy_request_logs (
            request_id, provider_id, app_type, model,
            input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
            total_cost_usd, status_code, created_at, data_source, request_model, pricing_model
        ) values
            \(rows);
        """
    }

    private static func runSQLite(database: URL, sql: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path, sql]
        process.standardOutput = Pipe()
        let standardError = Pipe()
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = standardError.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "sqlite fixture failed"
            throw FixtureError.message(message)
        }
    }

    private static func claudeAssistantLine(
        uuid: String,
        messageID: String?,
        timestamp: String,
        model: String?,
        stopReason: String?,
        input: Int,
        output: Int,
        cacheRead: Int,
        requestID: String? = nil,
        sessionID: String? = nil
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

        var object: [String: Any] = [
            "type": "assistant",
            "uuid": uuid,
            "timestamp": timestamp,
            "message": message
        ]
        if let requestID {
            object["requestId"] = requestID
        }
        if let sessionID {
            object["sessionId"] = sessionID
        }
        return jsonLine(object)
    }

    private static func jsonLine(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    private static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
        guard actual == expected else {
            throw FixtureError.message("\(label): expected \(expected), got \(actual)")
        }
    }

    private static func assertNil<T>(_ actual: T?, _ label: String) throws {
        guard actual == nil else {
            throw FixtureError.message("\(label): expected nil, got \(String(describing: actual))")
        }
    }
}

private enum FixtureError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(value):
            return value
        }
    }
}
