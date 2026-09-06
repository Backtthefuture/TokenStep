import Foundation
import XCTest
@testable import TokenStepSwift

final class AgentWorkRankServiceTests: XCTestCase {
    func testPublicLeaderboardDecodesOnlySupportedRankFields() throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_720_000_000)
        let data = Data("""
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
                "avatar_url": "https://example.com/avatar.png",
                "is_active_member": true
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
            data: data,
            fetchedAt: fetchedAt
        )

        XCTAssertEqual(leaderboard.fetchedAt, fetchedAt)
        XCTAssertEqual(leaderboard.totalRankedUsers, 1)
        XCTAssertEqual(leaderboard.topLimit, 100)
        let entry = try XCTUnwrap(leaderboard.entry(matching: 4))
        XCTAssertEqual(entry.rank, 7)
        XCTAssertEqual(entry.name, "Agent User")
        XCTAssertEqual(entry.totalTokens, 180)
        XCTAssertEqual(entry.clients["workbuddy"], 120)
    }

    func testLocalIdentityIgnoresCredentialsAndEmail() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepRankIdentity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
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

        let identity = try XCTUnwrap(
            AgentWorkRankService.loadLocalIdentity(clientStateURL: stateURL)
        )
        XCTAssertEqual(identity.id, 4)
        XCTAssertEqual(identity.name, "Agent User")
        XCTAssertNotNil(identity.lastSyncedAt)
    }

    private func identity(from json: String) throws -> AgentWorkRankIdentity? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rank-state-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(json.utf8).write(to: url)
        return AgentWorkRankService.loadLocalIdentity(clientStateURL: url)
    }

    func testVersionedStatesReadPayloadIdentityAndSyncTime() throws {
        for version in [2, 3] {
            let result = try XCTUnwrap(identity(from: """
            {
              "schema_version": \(version), "state_revision": 7,
              "checksum": "ignored-by-public-identity-reader",
              "user": {"id": 99, "name": "Stale root identity"},
              "payload": {
                "device_token": "never-decoded",
                "last_successful_sync_at": "2026-09-05T08:00:00Z",
                "user": {"id": 4, "name": "Agent User", "avatar_url": "https://example.com/a.png"}
              }
            }
            """))
            XCTAssertEqual(result.id, 4)
            XCTAssertEqual(result.name, "Agent User")
            XCTAssertEqual(result.avatarURL, "https://example.com/a.png")
            XCTAssertEqual(result.lastSyncedAt, ISO8601DateFormatter().date(from: "2026-09-05T08:00:00Z"))
        }
    }

    func testInvalidEnvelopesNeverFallBackToRootIdentity() throws {
        let rootUser = "\"user\":{\"id\":99,\"name\":\"Stale\"}"
        for fields in [
            "\"schema_version\":4,\"payload\":{}",
            "\"schema_version\":3",
            "\"schema_version\":3,\"payload\":null",
            "\"schema_version\":3,\"payload\":[]",
            "\"schema_version\":3,\"payload\":{}",
            "\"schema_version\":null,\"payload\":{}",
            "\"payload\":{}",
            "\"schema_version\":3,\"payload\":{\"user\":{\"id\":0,\"name\":\"Invalid\"}}"
        ] {
            XCTAssertNil(try identity(from: "{\(rootUser),\(fields)}"), fields)
        }
        XCTAssertNil(try identity(from: "not json"))
        XCTAssertNil(try identity(from: "{}"))
    }

    func testLegacyShengcaiSettingsMigrateToAutomaticAgentWorkRank() throws {
        let data = Data("""
        {
          "show_token_rank": true,
          "token_rank_user_id": "168066"
        }
        """.utf8)
        let settings = try JSONDecoder().decode(TokenStepSettings.self, from: data)
        XCTAssertEqual(settings.agentWorkRankVisibility, .automatic)
    }

    func testLegacyAgentWorkRankBooleanMigratesToThreeStateVisibility() throws {
        let visible = try JSONDecoder().decode(
            TokenStepSettings.self,
            from: Data("{\"show_agent_work_rank\":true}".utf8)
        )
        let automatic = try JSONDecoder().decode(
            TokenStepSettings.self,
            from: Data("{\"show_agent_work_rank\":false}".utf8)
        )

        XCTAssertEqual(visible.agentWorkRankVisibility, .visible)
        XCTAssertEqual(automatic.agentWorkRankVisibility, .automatic)
    }

    func testExplicitHiddenVisibilityWinsOverLegacyBoolean() throws {
        let settings = try JSONDecoder().decode(
            TokenStepSettings.self,
            from: Data("{\"agent_work_rank_visibility\":\"hidden\",\"show_agent_work_rank\":true}".utf8)
        )

        XCTAssertEqual(settings.agentWorkRankVisibility, .hidden)
    }

    func testAutomaticVisibilityRequiresIdentityAndHiddenNeverReadsIt() {
        XCTAssertTrue(AgentWorkRankVisibility.automatic.readsLocalIdentity)
        XCTAssertFalse(AgentWorkRankVisibility.automatic.shouldShow(hasLocalIdentity: false))
        XCTAssertTrue(AgentWorkRankVisibility.automatic.shouldShow(hasLocalIdentity: true))
        XCTAssertTrue(AgentWorkRankVisibility.visible.shouldShow(hasLocalIdentity: false))
        XCTAssertFalse(AgentWorkRankVisibility.hidden.readsLocalIdentity)
        XCTAssertFalse(AgentWorkRankVisibility.hidden.shouldShow(hasLocalIdentity: true))
    }

    func testSettingsEncodeOnlyWritesNewRankVisibilityKey() throws {
        var settings = TokenStepSettings.defaults
        settings.agentWorkRankVisibility = .hidden
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        )

        XCTAssertEqual(object["agent_work_rank_visibility"] as? String, "hidden")
        XCTAssertNil(object["show_agent_work_rank"])
    }
}
