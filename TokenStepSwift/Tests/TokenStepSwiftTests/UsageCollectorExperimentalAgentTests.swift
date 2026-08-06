import Foundation
import XCTest
@testable import TokenStepSwift

final class UsageCollectorExperimentalAgentTests: XCTestCase {
    func testExperimentalSourcesAreDisabledByDefault() throws {
        let zCodeDB = try makeZCodeDatabase(rowsSQL: """
        insert into model_usage (
            id, logical_request_id, session_id, query_source, provider_id, model_id, status, started_at,
            input_tokens, output_tokens, reasoning_tokens, cache_creation_input_tokens, cache_read_input_tokens,
            computed_total_tokens, tool_call_count
        ) values
            ('z-1', 'logical-1', 'session-z', 'cli', 'openai', 'gpt-5', 'completed', 1717200000000,
             10, 20, 5, 3, 2, 40, 4);
        """)
        let hermesDB = try makeHermesDatabase(rowsSQL: """
        insert into sessions (
            id, source, model, started_at, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens,
            reasoning_tokens, tool_call_count, api_call_count, actual_cost_usd, estimated_cost_usd, cost_status
        ) values
            ('h-1', 'cli', 'gpt-5', 1717203600, 10, 15, 5, 2, 3, 6, 2, 0.42, 0.30, 'included');
        """)

        let snapshot = UsageCollector.collectUsageSnapshotForTests(
            zCodeDatabaseURL: zCodeDB,
            hermesDatabaseURL: hermesDB
        )

        XCTAssertEqual(snapshot.sources["ZCode"]?.status, "disabled")
        XCTAssertEqual(snapshot.sources["Hermes Agent"]?.status, "disabled")
        XCTAssertEqual(snapshot.totals.tokens, 0)
        XCTAssertTrue(snapshot.agentWork.isEmpty)
    }

    func testZCodeCollectorUsesCompletedModelUsageRowsOnly() throws {
        let database = try makeZCodeDatabase(rowsSQL: """
        insert into model_usage (
            id, logical_request_id, session_id, query_source, provider_id, model_id, status, started_at,
            input_tokens, output_tokens, reasoning_tokens, cache_creation_input_tokens, cache_read_input_tokens,
            computed_total_tokens, tool_call_count
        ) values
            ('z-ok', 'logical-1', 'session-z', 'cli', 'openai', 'gpt-5', 'completed', 1717200000000,
             30, 10, 5, 3, 2, 0, 4),
            ('z-error', 'logical-2', 'session-z', 'cli', 'openai', 'gpt-5', 'error', 1717203600000,
             100, 100, 0, 0, 0, 200, 99),
            ('z-cancel', 'logical-3', 'session-z', 'cli', 'openai', 'gpt-5', 'cancelled', 1717207200000,
             100, 100, 0, 0, 0, 200, 99);
        """)

        let snapshot = UsageCollector.collectUsageSnapshotForTests(
            zCodeDatabaseURL: database,
            includeExperimentalAgentSources: true
        )

        XCTAssertEqual(snapshot.sources["ZCode"]?.status, "ok")
        XCTAssertEqual(snapshot.sources["ZCode"]?.records, 1)
        XCTAssertEqual(snapshot.totals.tokens, 40)
        XCTAssertEqual(snapshot.daily.first?.tools["ZCode"], 40)
        XCTAssertEqual(snapshot.daily.first?.models["gpt-5"], 40)

        let work = try XCTUnwrap(snapshot.agentWork.first)
        XCTAssertEqual(work.totalTokens, 40)
        XCTAssertEqual(work.modelRequestCount, 1)
        XCTAssertEqual(work.toolCallCount, 4)
        XCTAssertEqual(work.sources.first?.source, "ZCode")
        XCTAssertEqual(work.sources.first?.tokens, 40)
        XCTAssertEqual(work.hourlyBuckets.count, 24)
        XCTAssertEqual(work.hourlyBuckets.map(\.totalTokens).reduce(0, +) + work.unbucketedTokens, 40)
        XCTAssertEqual(try XCTUnwrap(work.cacheHitRate), 2.0 / 30.0, accuracy: 0.000_001)
    }

    func testHermesCollectorReadsSessionUsageWithoutMessageContent() throws {
        let database = try makeHermesDatabase(rowsSQL: """
        insert into sessions (
            id, source, model, started_at, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens,
            reasoning_tokens, tool_call_count, api_call_count, actual_cost_usd, estimated_cost_usd, cost_status
        ) values
            ('h-ok', 'feishu', 'gpt-5.5', 1717203600.5, 10, 15, 5, 2, 3, 6, 2, 0.42, 0.30, 'included'),
            ('h-zero', 'cli', 'gpt-5.5', 1717207200, 0, 0, 0, 0, 0, 3, 1, 9.99, 9.99, 'included');
        """)

        let snapshot = UsageCollector.collectUsageSnapshotForTests(
            hermesDatabaseURL: database,
            includeExperimentalAgentSources: true
        )

        XCTAssertEqual(snapshot.sources["Hermes Agent"]?.status, "ok")
        XCTAssertEqual(snapshot.sources["Hermes Agent"]?.records, 1)
        XCTAssertEqual(snapshot.totals.tokens, 32)
        XCTAssertEqual(snapshot.totals.cost, 0.42)
        XCTAssertEqual(snapshot.daily.first?.tools["Hermes Agent"], 32)
        XCTAssertEqual(snapshot.daily.first?.models["gpt-5.5"], 32)

        let work = try XCTUnwrap(snapshot.agentWork.first)
        XCTAssertEqual(work.modelRequestCount, 2)
        XCTAssertEqual(work.toolCallCount, 6)
        XCTAssertEqual(work.sources.first?.source, "Hermes Agent")
        XCTAssertEqual(work.inputTokens, 17)
        XCTAssertEqual(work.cachedInputTokens, 5)
        XCTAssertEqual(work.outputTokens, 15)
        XCTAssertEqual(try XCTUnwrap(work.cacheHitRate), 5.0 / 17.0, accuracy: 0.000_001)
    }

    func testWorkBuddyDiscoveryDoesNotEnterTotals() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepWorkBuddy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let snapshot = UsageCollector.collectUsageSnapshotForTests(
            workBuddyRootURLs: [directory],
            includeExperimentalAgentSources: true
        )

        XCTAssertEqual(snapshot.sources["WorkBuddy"]?.status, "discovered_no_usage")
        XCTAssertEqual(snapshot.sources["WorkBuddy"]?.records, 0)
        XCTAssertEqual(snapshot.totals.tokens, 0)
        XCTAssertTrue(snapshot.daily.isEmpty)
        XCTAssertTrue(snapshot.agentWork.isEmpty)
    }

    func testWorkBuddyCollectorReadsUsageWithoutMessageContent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepWorkBuddy-\(UUID().uuidString)", isDirectory: true)
        let project = root.appendingPathComponent("projects/example", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let lines = [
            """
            {"type":"function_call","timestamp":1717200000000,"sessionId":"wb-session","message":{"usage":{"input_tokens":100,"output_tokens":20,"total_tokens":120,"cache_read_input_tokens":80}},"providerData":{"requestModelId":"hy3","conversationRequestId":"wb-request-1","toolResult":{"content":"must not be parsed"}}}
            """,
            """
            {"type":"message","timestamp":1717203600000,"sessionId":"wb-session","providerData":{"requestModelId":"kimi-k3-1","conversationRequestId":"wb-request-2","rawUsage":{"prompt_tokens":50,"completion_tokens":10,"total_tokens":60,"prompt_cache_hit_tokens":40,"completion_thinking_tokens":3}}}
            """,
            """
            {"type":"message","timestamp":1717207200000,"sessionId":"wb-session","message":{"content":"no usage row"}}
            """
        ]
        try lines.joined(separator: "\n").write(
            to: project.appendingPathComponent("session.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let snapshot = UsageCollector.collectUsageSnapshotForTests(
            workBuddyRootURLs: [root],
            includeExperimentalAgentSources: true
        )

        XCTAssertEqual(snapshot.sources["WorkBuddy"]?.status, "ok")
        XCTAssertEqual(snapshot.sources["WorkBuddy"]?.files, 1)
        XCTAssertEqual(snapshot.sources["WorkBuddy"]?.records, 2)
        XCTAssertEqual(snapshot.totals.tokens, 180)
        XCTAssertEqual(snapshot.daily.first?.tools["WorkBuddy"], 180)
        XCTAssertEqual(snapshot.daily.first?.models["hy3"], 120)
        XCTAssertEqual(snapshot.daily.first?.models["kimi-k3-1"], 60)

        let work = try XCTUnwrap(snapshot.agentWork.first)
        XCTAssertEqual(work.totalTokens, 180)
        XCTAssertEqual(work.inputTokens, 150)
        XCTAssertEqual(work.cachedInputTokens, 120)
        XCTAssertEqual(work.outputTokens, 30)
        XCTAssertEqual(work.modelRequestCount, 2)
        XCTAssertEqual(work.toolCallCount, 1)
        XCTAssertEqual(work.sources.first?.source, "WorkBuddy")
    }

    private func makeZCodeDatabase(rowsSQL: String) throws -> URL {
        let database = try fixtureDatabase(prefix: "TokenStepZCode")
        try runSQLite(database: database, sql: """
        create table model_usage (
            id text primary key,
            logical_request_id text not null,
            attempt_index integer not null default 0,
            session_id text not null,
            turn_id text,
            trace_id text,
            span_id text,
            assistant_message_id text,
            parent_user_message_id text,
            query_source text not null,
            provider_id text not null,
            model_id text not null,
            variant text,
            agent text,
            mode text,
            task_type text,
            status text not null,
            started_at integer not null,
            first_token_at integer,
            completed_at integer,
            duration_ms integer,
            time_to_first_token_ms integer,
            finish_reason text,
            tool_call_count integer not null default 0,
            input_tokens integer not null default 0,
            output_tokens integer not null default 0,
            reasoning_tokens integer not null default 0,
            cache_creation_input_tokens integer not null default 0,
            cache_read_input_tokens integer not null default 0,
            provider_total_tokens integer,
            computed_total_tokens integer not null default 0,
            retry_count integer not null default 0,
            retryable integer not null default 0,
            cancelled_by_user integer not null default 0,
            context_exceeded integer not null default 0,
            error_type text,
            error_code text,
            error_message text,
            raw_usage_json text,
            provider_metadata_json text
        );
        \(rowsSQL)
        """)
        return database
    }

    private func makeHermesDatabase(rowsSQL: String) throws -> URL {
        let database = try fixtureDatabase(prefix: "TokenStepHermes")
        try runSQLite(database: database, sql: """
        create table sessions (
            id text primary key,
            source text not null,
            user_id text,
            model text,
            model_config text,
            system_prompt text,
            parent_session_id text,
            started_at real not null,
            ended_at real,
            end_reason text,
            message_count integer default 0,
            tool_call_count integer default 0,
            input_tokens integer default 0,
            output_tokens integer default 0,
            cache_read_tokens integer default 0,
            cache_write_tokens integer default 0,
            reasoning_tokens integer default 0,
            billing_provider text,
            billing_base_url text,
            billing_mode text,
            estimated_cost_usd real,
            actual_cost_usd real,
            cost_status text,
            cost_source text,
            pricing_version text,
            title text,
            api_call_count integer default 0
        );
        create table messages (
            id integer primary key autoincrement,
            session_id text not null,
            role text not null,
            content text,
            timestamp real not null
        );
        \(rowsSQL)
        """)
        return database
    }

    private func fixtureDatabase(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("fixture.sqlite")
    }

    private func runSQLite(database: URL, sql: String) throws {
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
            throw NSError(
                domain: "UsageCollectorExperimentalAgentTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}
