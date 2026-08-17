import Foundation

@main
struct CCSwitchProxyFixtureCheck {
    static func main() throws {
        try runCCSwitchChecks()
        try runClaudeCodeChecks()
        try runClaudeOpusCostCheck()
        try runCodexArchivedSessionChecks()
        try runCrossSourceDedupeChecks()
        try runAmbiguousFuzzyDedupeCheck()
        try runShanghaiHistoryWindowCheck()
        try runExperimentalAgentChecks()
        try runAgentWorkRankChecks()
        try runLegacyAgentWorkDecodeCheck()
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
        try assertEqual(snapshot.daily.first?.models["gpt-5.4"], 13, "model fallback tokens")

        let semanticsDatabase = try makeSemanticsFixtureDatabase()
        defer {
            try? FileManager.default.removeItem(at: semanticsDatabase.deletingLastPathComponent())
        }
        let semanticsSnapshot = UsageCollector.collectCCSwitchProxyUsageSnapshot(
            databaseURL: semanticsDatabase
        )
        try assertEqual(
            semanticsSnapshot.sources["CC Switch Proxy"]?.records,
            4,
            "all input-token semantics rows are collected"
        )
        try assertEqual(semanticsSnapshot.totals.tokens, 480, "input-token semantics total")
        let semanticsWork = try unwrap(
            semanticsSnapshot.agentWork.first,
            "input-token semantics agent work"
        )
        try assertEqual(
            semanticsWork.totalTokens,
            480,
            "TOTAL, FRESH, LEGACY, and Claude rows preserve processed total"
        )
        try assertEqual(
            semanticsWork.inputTokens,
            400,
            "all input-token semantics normalize to canonical input"
        )
        try assertEqual(
            semanticsWork.cachedInputTokens,
            240,
            "cache-read tokens stay a subset of canonical input"
        )
        try assertEqual(
            semanticsWork.outputTokens,
            80,
            "output tokens are never duplicated"
        )
        try assertApprox(
            semanticsWork.cacheHitRate,
            0.6,
            "cache hit uses cache reads over canonical input"
        )

        let missingSemanticsDatabase = try makeFixtureDatabase(rowsSQL: """
        insert into proxy_request_logs (
            request_id, provider_id, app_type, model,
            input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
            total_cost_usd, status_code, created_at, data_source, request_model, pricing_model
        ) values
            ('missing-column-codex', 'provider-a', 'codex', 'gpt-5.4', 90, 20, 60, 10, '0', 200, 1717200000, 'proxy', 'gpt-5.4', ''),
            ('missing-column-claude', 'provider-b', 'claude', 'claude-raw', 30, 20, 60, 10, '0', 200, 1717203600, 'proxy', 'claude-raw', '');
        """)
        defer {
            try? FileManager.default.removeItem(
                at: missingSemanticsDatabase.deletingLastPathComponent()
            )
        }
        let missingSemanticsSnapshot = UsageCollector.collectCCSwitchProxyUsageSnapshot(
            databaseURL: missingSemanticsDatabase
        )
        try assertEqual(
            missingSemanticsSnapshot.totals.tokens,
            240,
            "a missing semantics column preserves the official LEGACY behavior"
        )
        try assertApprox(
            missingSemanticsSnapshot.agentWork.first?.cacheHitRate,
            0.6,
            "legacy schema cache hit remains canonical"
        )

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

    private static func runClaudeOpusCostCheck() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepClaudeCostFixture-\(UUID().uuidString)", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let log = project.appendingPathComponent("session.jsonl")
        try claudeAssistantLine(
            uuid: "opus-cost",
            messageID: "msg-opus-cost",
            timestamp: "2026-06-21T08:00:00Z",
            model: "claude-opus-4-8",
            stopReason: "end_turn",
            input: 1_000_000,
            output: 1_000_000,
            cacheCreation: 1_000_000,
            cacheRead: 1_000_000
        ).write(to: log, atomically: true, encoding: .utf8)

        let snapshot = UsageCollector.collectClaudeCodeUsageSnapshot(rootURL: root)
        try assertEqual(snapshot.totals.tokens, 4_000_000, "claude opus cost tokens")
        try assertEqual(snapshot.totals.cost, 36.75, "claude opus current cost")
        try assertEqual(snapshot.daily.first?.cost, 36.75, "claude opus current daily cost")
    }

    private static func runCrossSourceDedupeChecks() throws {
        try runClaudeProxyDedupeChecks()
        try runCodexSimilarIndependentRequestCheck()
        try runCodexSharedSessionDedupeCheck()
    }

    private static func runAmbiguousFuzzyDedupeCheck() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepAmbiguousDedupe-\(UUID().uuidString)", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try claudeAssistantLine(
            uuid: "ambiguous-native",
            messageID: "ambiguous-native-message",
            timestamp: "2026-06-21T08:00:00Z",
            model: "claude-opus-4-20250514",
            stopReason: "end_turn",
            input: 10,
            output: 3,
            cacheRead: 100
        ).write(
            to: project.appendingPathComponent("session.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let database = try makeFixtureDatabase(rowsSQL: """
        insert into proxy_request_logs (
            request_id, provider_id, app_type, model,
            input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
            total_cost_usd, status_code, created_at, data_source, request_model, pricing_model
        ) values
            ('ambiguous-proxy-1', 'provider-a', 'claude', 'claude-opus-4-20250514', 10, 3, 100, 0, '0.10', 200, 1782028800, 'proxy', 'claude-opus-4-20250514', ''),
            ('ambiguous-proxy-2', 'provider-a', 'claude', 'claude-opus-4-20250514', 10, 3, 100, 0, '0.10', 200, 1782028801, 'proxy', 'claude-opus-4-20250514', '');
        """)
        defer { try? FileManager.default.removeItem(at: database.deletingLastPathComponent()) }

        let snapshot = UsageCollector.collectUsageSnapshotForTests(
            claudeRootURL: root,
            ccSwitchDatabaseURL: database
        )
        let source = snapshot.sources["CC Switch Proxy"]
        try assertEqual(source?.records, 2, "ambiguous fuzzy candidates are both kept")
        try assertEqual(source?.dedupedRecords, 0, "ambiguous fuzzy candidates are not deduplicated")
        try assertEqual(snapshot.totals.tokens, 339, "one native plus two ambiguous proxy rows")
    }

    private static func runShanghaiHistoryWindowCheck() throws {
        let formatter = ISO8601DateFormatter()
        func epoch(_ value: String) -> Int {
            Int(formatter.date(from: value)!.timeIntervalSince1970)
        }
        let database = try makeFixtureDatabase(rowsSQL: """
        insert into proxy_request_logs (
            request_id, provider_id, app_type, model,
            input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
            total_cost_usd, status_code, created_at, data_source, request_model, pricing_model
        ) values
            ('outside-before', 'provider-a', 'codex', 'gpt-5.4', 1, 1, 0, 0, '0', 200, \(epoch("2026-07-17T15:59:59Z")), 'proxy', 'gpt-5.4', ''),
            ('inside-first-second', 'provider-a', 'codex', 'gpt-5.4', 1, 1, 0, 0, '0', 200, \(epoch("2026-07-17T16:00:00Z")), 'proxy', 'gpt-5.4', ''),
            ('inside-last-second', 'provider-a', 'codex', 'gpt-5.4', 1, 1, 0, 0, '0', 200, \(epoch("2026-07-19T15:59:59Z")), 'proxy', 'gpt-5.4', ''),
            ('outside-after', 'provider-a', 'codex', 'gpt-5.4', 1, 1, 0, 0, '0', 200, \(epoch("2026-07-19T16:00:00Z")), 'proxy', 'gpt-5.4', '');
        """)
        defer { try? FileManager.default.removeItem(at: database.deletingLastPathComponent()) }

        let snapshot = UsageCollector.collectUsageSnapshotForTests(
            ccSwitchDatabaseURL: database,
            historyDays: 2,
            now: formatter.date(from: "2026-07-19T04:00:00Z")!
        )
        try assertEqual(snapshot.totals.tokens, 4, "Shanghai two-day window is calendar-inclusive")
        try assertEqual(snapshot.daily.map(\.date), ["2026-07-18", "2026-07-19"], "Shanghai window dates")
    }

    private static func runExperimentalAgentChecks() throws {
        let zCodeDB = try makeZCodeFixtureDatabase()
        let hermesDB = try makeHermesFixtureDatabase()
        let workBuddyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepWorkBuddyFixture-\(UUID().uuidString)", isDirectory: true)
        let workBuddyProject = workBuddyRoot.appendingPathComponent("projects/example", isDirectory: true)
        try FileManager.default.createDirectory(at: workBuddyProject, withIntermediateDirectories: true)
        try """
        {"type":"function_call","timestamp":1717200000000,"sessionId":"wb-session","message":{"usage":{"input_tokens":100,"output_tokens":20,"total_tokens":120,"cache_read_input_tokens":80}},"providerData":{"requestModelId":"hy3","conversationRequestId":"wb-request-1"}}
        """.write(
            to: workBuddyProject.appendingPathComponent("session.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        defer {
            try? FileManager.default.removeItem(at: zCodeDB.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: hermesDB.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: workBuddyRoot)
        }

        let disabled = UsageCollector.collectUsageSnapshotForTests(
            zCodeDatabaseURL: zCodeDB,
            hermesDatabaseURL: hermesDB,
            workBuddyRootURLs: [workBuddyRoot]
        )
        try assertEqual(disabled.sources["ZCode"]?.status, "disabled", "zcode disabled status")
        try assertEqual(disabled.sources["Hermes Agent"]?.status, "disabled", "hermes disabled status")
        try assertEqual(disabled.sources["WorkBuddy"]?.status, "disabled", "workbuddy disabled status")
        try assertEqual(disabled.totals.tokens, 0, "experimental disabled total")
        try assertEqual(disabled.agentWork.count, 0, "experimental disabled agent work")

        let snapshot = UsageCollector.collectUsageSnapshotForTests(
            zCodeDatabaseURL: zCodeDB,
            hermesDatabaseURL: hermesDB,
            workBuddyRootURLs: [workBuddyRoot],
            includeExperimentalAgentSources: true
        )
        try assertEqual(snapshot.sources["ZCode"]?.status, "ok", "zcode source status")
        try assertEqual(snapshot.sources["ZCode"]?.records, 1, "zcode source records")
        try assertEqual(snapshot.sources["Hermes Agent"]?.status, "ok", "hermes source status")
        try assertEqual(snapshot.sources["Hermes Agent"]?.records, 1, "hermes source records")
        try assertEqual(snapshot.sources["WorkBuddy"]?.status, "ok", "workbuddy source status")
        try assertEqual(snapshot.sources["WorkBuddy"]?.records, 1, "workbuddy records")
        try assertEqual(snapshot.totals.tokens, 192, "experimental total tokens")
        try assertEqual(snapshot.daily.first?.tools["ZCode"], 40, "zcode tool tokens")
        try assertEqual(snapshot.daily.first?.tools["Hermes Agent"], 32, "hermes tool tokens")
        try assertEqual(snapshot.daily.first?.tools["WorkBuddy"], 120, "workbuddy tool tokens")
        try assertEqual(snapshot.totals.cost, 0.42, "hermes actual cost")

        let work = try unwrap(snapshot.agentWork.first, "experimental agent work")
        try assertEqual(work.totalTokens, 192, "experimental agent work tokens")
        try assertEqual(work.modelRequestCount, 4, "experimental model requests")
        try assertEqual(work.toolCallCount, 11, "experimental tool calls")
        try assertEqual(work.sources.count, 3, "experimental source count")
        try assertEqual(work.hourlyBuckets.count, 24, "agent work always exposes 24 hourly buckets")
        try assertEqual(
            work.hourlyBuckets.map(\.totalTokens).reduce(0, +) + work.unbucketedTokens,
            work.totalTokens,
            "hourly and unbucketed agent tokens reconcile to the day"
        )
        try assertEqual(work.unbucketedTokens, 0, "timestamped agent rows are fully bucketed")
        try assertEqual(work.cacheCoverageComplete, true, "experimental cache coverage is complete")
        try assertApprox(work.cacheHitRate, 87.0 / 147.0, "daily cache hit uses canonical input denominator")
    }

    private static func runLegacyAgentWorkDecodeCheck() throws {
        let legacyJSON = Data("""
        {
          "date": "2026-07-18",
          "total_tokens": 123,
          "active_hours": 2,
          "model_request_count": 3,
          "tool_call_count": 4,
          "sources": []
        }
        """.utf8)
        let work = try JSONDecoder().decode(DailyAgentWork.self, from: legacyJSON)
        try assertEqual(work.hourlyBuckets.count, 24, "legacy agent work gains 24 empty buckets")
        try assertEqual(work.hourlyBuckets.map(\.totalTokens).reduce(0, +), 0, "legacy buckets are empty")
        try assertEqual(work.unbucketedTokens, 123, "legacy total is preserved as unbucketed")
        try assertNil(work.cacheHitRate, "legacy cache hit is unavailable")
    }

    private static func runAgentWorkRankChecks() throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_720_000_000)
        let leaderboardData = Data("""
        {
          "success": true,
          "data": {
            "range": "today",
            "client": "all",
            "usage_mode": "all",
            "total_tokens": 999,
            "total_ranked_users": 1,
            "top_limit": 100,
            "rows": [{
              "user": {
                "id": 4,
                "name": "Agent User",
                "email": "ignored@example.com",
                "avatar_url": "https://example.com/avatar.png"
              },
              "total_tokens": 180,
              "call_count": 2,
              "session_count": 1,
              "clients": {"workbuddy": 120, "codex": 60},
              "models": {"hy3": 120, "gpt-test": 60},
              "rank": 7
            }]
          }
        }
        """.utf8)
        let leaderboard = try AgentWorkRankService.decodeLeaderboard(
            data: leaderboardData,
            fetchedAt: fetchedAt
        )
        try assertEqual(leaderboard.fetchedAt, fetchedAt, "rank fetch date")
        try assertEqual(leaderboard.totalRankedUsers, 1, "ranked users")
        let entry = try unwrap(leaderboard.entry(matching: 4), "rank entry")
        try assertEqual(entry.rank, 7, "rank position")
        try assertEqual(entry.totalTokens, 180, "rank tokens")
        try assertEqual(entry.clients["workbuddy"], 120, "rank workbuddy tokens")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepRankIdentityFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("client-state.json")
        try """
        {
          "device_token": "must-not-leave-this-file",
          "source_id": "private-source",
          "last_successful_sync_at": "2026-08-06T08:00:00.661715+00:00",
          "user": {
            "id": 4,
            "name": "Agent User",
            "email": "ignored@example.com",
            "avatar_url": "https://example.com/avatar.png"
          }
        }
        """.write(to: stateURL, atomically: true, encoding: .utf8)
        let identity = try unwrap(
            AgentWorkRankService.loadLocalIdentity(clientStateURL: stateURL),
            "local rank identity"
        )
        try assertEqual(identity.id, 4, "local rank identity id")
        try assertEqual(identity.name, "Agent User", "local rank identity name")
        try assertEqual(identity.lastSyncedAt == nil, false, "local rank sync date")

        let legacySettings = try JSONDecoder().decode(
            TokenStepSettings.self,
            from: Data("""
            {"show_token_rank":true,"token_rank_user_id":"168066"}
            """.utf8)
        )
        try assertEqual(legacySettings.agentWorkRankVisibility, .automatic, "legacy rank uses automatic detection")

        let hiddenSettings = try JSONDecoder().decode(
            TokenStepSettings.self,
            from: Data("""
            {"agent_work_rank_visibility":"hidden","show_agent_work_rank":true}
            """.utf8)
        )
        try assertEqual(hiddenSettings.agentWorkRankVisibility, .hidden, "explicit hidden rank state")
        try assertEqual(AgentWorkRankVisibility.automatic.readsLocalIdentity, true, "automatic reads identity")
        try assertEqual(AgentWorkRankVisibility.automatic.shouldShow(hasLocalIdentity: false), false, "automatic hides without identity")
        try assertEqual(AgentWorkRankVisibility.automatic.shouldShow(hasLocalIdentity: true), true, "automatic shows with identity")
        try assertEqual(AgentWorkRankVisibility.hidden.readsLocalIdentity, false, "hidden skips identity")
        try assertEqual(AgentWorkRankVisibility.hidden.shouldShow(hasLocalIdentity: true), false, "hidden stays hidden")

        let encodedHidden = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(hiddenSettings)
        ) as? [String: Any]
        try assertEqual(encodedHidden?["agent_work_rank_visibility"] as? String, "hidden", "new rank visibility encoding")
        try assertEqual(encodedHidden?["show_agent_work_rank"] == nil, true, "legacy rank key is not encoded")
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
        try assertNil(snapshot.agentWork.first?.cacheHitRate, "total-only Codex cache hit is unavailable")
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

    private static func runCodexSimilarIndependentRequestCheck() throws {
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
            ('independent-proxy-codex-request', 'provider-a', 'codex', 'gpt-5.4', 30, 5, 10, 0, '0.45', 200, 1782032400, 'proxy', 'gpt-5.4', '');
        """)
        defer {
            try? FileManager.default.removeItem(at: database.deletingLastPathComponent())
        }

        let snapshot = UsageCollector.collectUsageSnapshotForTests(
            codexRoots: [root],
            ccSwitchDatabaseURL: database
        )

        let source = snapshot.sources["CC Switch Proxy"]
        try assertEqual(source?.status, "ok", "independent Codex proxy source status")
        try assertEqual(source?.rawRecords, 1, "independent Codex raw proxy records")
        try assertEqual(source?.records, 1, "independent Codex proxy record is kept")
        try assertEqual(source?.dedupedRecords, 0, "similar requests without a shared ID are not deduplicated")
        try assertEqual(snapshot.totals.tokens, 70, "native and independent proxy Codex requests both count")
        try assertEqual(snapshot.totals.cost, 0.45, "independent Codex request total cost")
        try assertEqual(snapshot.daily.first?.tools["Codex"], 35, "independent native Codex tokens")
        try assertEqual(
            snapshot.daily.first?.tools["Codex via CC Switch"],
            35,
            "independent proxy Codex tokens"
        )
    }

    private static func runCodexSharedSessionDedupeCheck() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepCodexSessionDedupeFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let timestamp = "2026-06-21T10:00:00Z"
        let sessionID = "shared-codex-session"
        let log = root.appendingPathComponent("session.jsonl")
        let lines = [
            jsonLine([
                "type": "session_meta",
                "timestamp": timestamp,
                "payload": ["id": sessionID]
            ]),
            jsonLine([
                "type": "turn_context",
                "timestamp": timestamp,
                "payload": ["model": "gpt-5.4"]
            ]),
            jsonLine([
                "type": "event_msg",
                "timestamp": timestamp,
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

        let createdAt = Int(ISO8601DateFormatter().date(from: timestamp)!.timeIntervalSince1970)
        let database = try makeFixtureDatabase(
            rowsSQL: """
            insert into proxy_request_logs (
                request_id, session_id, provider_id, app_type, model,
                input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
                total_cost_usd, status_code, created_at, data_source, request_model, pricing_model
            ) values
                ('different-proxy-request-id', '\(sessionID)', 'provider-a', 'codex', 'gpt-5.4',
                 30, 5, 10, 0, '0.45', 200, \(createdAt), 'proxy', 'gpt-5.4', '');
            """,
            includeSessionID: true
        )
        defer {
            try? FileManager.default.removeItem(at: database.deletingLastPathComponent())
        }

        let snapshot = UsageCollector.collectUsageSnapshotForTests(
            codexRoots: [root],
            ccSwitchDatabaseURL: database
        )
        let source = snapshot.sources["CC Switch Proxy"]
        try assertEqual(source?.status, "all_deduped", "shared-session Codex source status")
        try assertEqual(source?.records, 0, "shared-session proxy record is removed")
        try assertEqual(source?.dedupedRecords, 1, "shared-session proxy record is deduplicated")
        try assertEqual(snapshot.totals.tokens, 35, "shared-session request counts once")
        try assertEqual(snapshot.totals.cost, 0.45, "shared-session proxy cost enriches native record")

        let incremental = UsageCollector.collectIncrementalCodexAndProxySnapshotForTests(
            codexRoots: [root],
            cacheURL: root.appendingPathComponent("incremental-cache.sqlite3"),
            ccSwitchDatabaseURL: database
        )
        let incrementalSource = incremental.sources["CC Switch Proxy"]
        try assertEqual(
            incrementalSource?.status,
            "all_deduped",
            "incremental shared-session Codex source status"
        )
        try assertEqual(
            incrementalSource?.dedupedRecords,
            1,
            "incremental cache retains request-level details for proxy dedupe"
        )
        try assertEqual(incremental.totals.tokens, 35, "incremental shared-session request counts once")
        try assertEqual(incremental.totals.cost, 0.45, "incremental proxy cost enriches native record")
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

    private static func makeZCodeFixtureDatabase() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepZCodeFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = directory.appendingPathComponent("zcode.sqlite")
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
        insert into model_usage (
            id, logical_request_id, session_id, query_source, provider_id, model_id, status, started_at,
            input_tokens, output_tokens, reasoning_tokens, cache_creation_input_tokens, cache_read_input_tokens,
            computed_total_tokens, tool_call_count
        ) values
            ('z-ok', 'logical-1', 'session-z', 'cli', 'openai', 'gpt-5', 'completed', 1717200000000,
             30, 10, 5, 3, 2, 0, 4),
            ('z-error', 'logical-2', 'session-z', 'cli', 'openai', 'gpt-5', 'error', 1717203600000,
             100, 100, 0, 0, 0, 200, 99);
        """)
        return database
    }

    private static func makeHermesFixtureDatabase() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepHermesFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = directory.appendingPathComponent("hermes.sqlite")
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
        insert into sessions (
            id, source, model, started_at, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens,
            reasoning_tokens, tool_call_count, api_call_count, actual_cost_usd, estimated_cost_usd, cost_status
        ) values
            ('h-ok', 'feishu', 'gpt-5.5', 1717203600.5, 10, 15, 5, 2, 3, 6, 2, 0.42, 0.30, 'included'),
            ('h-zero', 'cli', 'gpt-5.5', 1717207200, 0, 0, 0, 0, 0, 3, 1, 9.99, 9.99, 'included');
        insert into messages (session_id, role, content, timestamp) values
            ('h-ok', 'user', 'must not be read by TokenStep', 1717203600.5);
        """)
        return database
    }

    private static func makeFixtureDatabase(
        rowsSQL: String = defaultRowsSQL,
        includeSessionID: Bool = false
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepCCSwitchFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = directory.appendingPathComponent("cc-switch.db")
        try runSQLite(database: database, sql: """
        create table proxy_request_logs (
            request_id text primary key,
            \(includeSessionID ? "session_id text," : "")
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

    private static func makeSemanticsFixtureDatabase() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepCCSwitchSemantics-\(UUID().uuidString)", isDirectory: true)
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
            input_token_semantics integer not null default 0,
            total_cost_usd text not null default '0',
            status_code integer not null,
            created_at integer not null,
            data_source text not null default 'proxy',
            request_model text,
            pricing_model text
        );
        insert into proxy_request_logs (
            request_id, provider_id, app_type, model,
            input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
            input_token_semantics,
            total_cost_usd, status_code, created_at, data_source, request_model, pricing_model
        ) values
            ('semantics-total', 'provider-a', 'codex', 'gpt-5.4', 100, 20, 60, 10, 1, '0', 200, 1717200000, 'proxy', 'gpt-5.4', ''),
            ('semantics-fresh', 'provider-a', 'codex', 'gpt-5.4', 30, 20, 60, 10, 2, '0', 200, 1717203600, 'proxy', 'gpt-5.4', ''),
            ('semantics-legacy', 'provider-a', 'codex', 'gpt-5.4', 90, 20, 60, 10, 0, '0', 200, 1717207200, 'proxy', 'gpt-5.4', ''),
            ('semantics-claude', 'provider-b', 'claude', 'claude-raw', 30, 20, 60, 10, 2, '0', 200, 1717210800, 'proxy', 'claude-raw', '');
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
        ('proxy-2', 'provider-b', 'codex', 'gpt-5.4', 10, 3, 8, 0, '0.34', 201, 1717203600, 'proxy', 'gpt-5-request', ''),
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
        cacheCreation: Int = 0,
        cacheRead: Int,
        requestID: String? = nil,
        sessionID: String? = nil
    ) -> String {
        var message: [String: Any] = [
            "usage": [
                "input_tokens": input,
                "output_tokens": output,
                "cache_creation_input_tokens": cacheCreation,
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

    private static func assertApprox(_ actual: Double?, _ expected: Double, _ label: String) throws {
        guard let actual, abs(actual - expected) < 0.000_001 else {
            throw FixtureError.message("\(label): expected \(expected), got \(String(describing: actual))")
        }
    }

    private static func unwrap<T>(_ value: T?, _ label: String) throws -> T {
        guard let value else {
            throw FixtureError.message("\(label): expected value, got nil")
        }
        return value
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
