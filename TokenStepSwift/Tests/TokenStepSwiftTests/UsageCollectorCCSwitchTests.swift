import Foundation
import XCTest
@testable import TokenStepSwift

final class UsageCollectorCCSwitchTests: XCTestCase {
    func testSuccessfulRowsAggregateOnlyProxyDataSource() throws {
        let database = try makeFixtureDatabase(rowsSQL: """
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
        """)

        let snapshot = UsageCollector.collectCCSwitchProxyUsageSnapshot(databaseURL: database)

        XCTAssertEqual(snapshot.sources["CC Switch Proxy"]?.status, "ok")
        XCTAssertEqual(snapshot.sources["CC Switch Proxy"]?.records, 2)
        XCTAssertEqual(snapshot.totals.tokens, 168)
        XCTAssertEqual(snapshot.totals.cost, 0.46)

        XCTAssertEqual(snapshot.daily.count, 1)
        XCTAssertEqual(snapshot.daily.first?.date, "2024-06-01")
        XCTAssertEqual(snapshot.daily.first?.tools["Claude Code via CC Switch"], 155)
        XCTAssertEqual(snapshot.daily.first?.tools["Codex via CC Switch"], 13)
        XCTAssertEqual(snapshot.daily.first?.models["claude-priced"], 155)
        XCTAssertNil(snapshot.daily.first?.models["claude-session-priced"])
        XCTAssertNil(snapshot.daily.first?.models["codex-session-priced"])
        XCTAssertEqual(snapshot.daily.first?.models["GPT-5.4"], 13)

        let tools = Dictionary(uniqueKeysWithValues: snapshot.tools.map { ($0.tool, $0.tokens) })
        XCTAssertEqual(tools["Claude Code via CC Switch"], 155)
        XCTAssertEqual(tools["Codex via CC Switch"], 13)

        let models = Dictionary(uniqueKeysWithValues: snapshot.models.map { ("\($0.tool ?? "")|\($0.model)", $0.tokens) })
        XCTAssertEqual(models["Claude Code via CC Switch|claude-priced"], 155)
        XCTAssertNil(models["Claude Code via CC Switch|claude-session-priced"])
        XCTAssertNil(models["Codex via CC Switch|codex-session-priced"])
        XCTAssertEqual(models["Codex via CC Switch|GPT-5.4"], 13)
    }

    func testValidDatabaseWithoutSuccessfulTokenRowsReportsMissingValidRows() throws {
        let database = try makeFixtureDatabase(rowsSQL: """
        insert into proxy_request_logs (
            request_id, provider_id, app_type, model,
            input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
            total_cost_usd, status_code, created_at, data_source, request_model, pricing_model
        ) values
            ('failed-session', 'provider-c', 'claude', 'ignored-model', 9000, 9000, 0, 0, '9.99', 500, 1717207200, 'codex_session', 'ignored', 'ignored'),
            ('zero-session', 'provider-b', 'codex', 'ignored-zero', 0, 0, 0, 0, '0.00', 200, 1717203600, 'opencode_session', 'ignored', 'ignored');
        """)

        let snapshot = UsageCollector.collectCCSwitchProxyUsageSnapshot(databaseURL: database)

        XCTAssertEqual(snapshot.sources["CC Switch Proxy"]?.status, "missing_valid_rows")
        XCTAssertEqual(snapshot.sources["CC Switch Proxy"]?.records, 0)
        XCTAssertEqual(snapshot.totals.tokens, 0)
        XCTAssertTrue(snapshot.daily.isEmpty)
        XCTAssertTrue(snapshot.tools.isEmpty)
        XCTAssertTrue(snapshot.models.isEmpty)
    }

    func testLargeCCSwitchResultDoesNotBlockOnSQLiteOutput() throws {
        let rowCount = 1_500
        let rows = (0..<rowCount).map { index in
            "('bulk-\(index)', 'provider-a', 'codex', 'gpt-5.4', 1, 1, 0, 0, '0.001', 200, 1717200000, 'proxy', 'gpt-5-request', '')"
        }.joined(separator: ",\n")
        let database = try makeFixtureDatabase(rowsSQL: """
        insert into proxy_request_logs (
            request_id, provider_id, app_type, model,
            input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
            total_cost_usd, status_code, created_at, data_source, request_model, pricing_model
        ) values
            \(rows);
        """)

        let snapshot = UsageCollector.collectCCSwitchProxyUsageSnapshot(databaseURL: database)

        XCTAssertEqual(snapshot.sources["CC Switch Proxy"]?.status, "ok")
        XCTAssertEqual(snapshot.sources["CC Switch Proxy"]?.records, rowCount)
        XCTAssertEqual(snapshot.totals.tokens, rowCount * 2)
        XCTAssertEqual(snapshot.daily.first?.tools["Codex via CC Switch"], rowCount * 2)
    }

    private func makeFixtureDatabase(rowsSQL: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepCCSwitchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

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
                domain: "UsageCollectorCCSwitchTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}
