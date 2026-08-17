import Foundation
import XCTest
@testable import TokenStepSwift

final class SettingsMigrationTests: XCTestCase {
    func testLegacyShowCodexQuotaTrueMigratesToCodexAndClaude() throws {
        let json = """
        {"show_codex_quota": true}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(TokenStepSettings.self, from: json)
        XCTAssertEqual(settings.enabledQuotaProviders, [.codex, .claude])
        XCTAssertTrue(settings.showCodexQuota)
        XCTAssertFalse(settings.cursorQuotaEnabled)
        XCTAssertFalse(settings.cursorCodeSignalEnabled)
    }

    func testLegacyShowCodexQuotaFalseMigratesToEmptySet() throws {
        let json = """
        {"show_codex_quota": false}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(TokenStepSettings.self, from: json)
        XCTAssertTrue(settings.enabledQuotaProviders.isEmpty)
        XCTAssertFalse(settings.showCodexQuota)
    }

    func testRoundTripKeepsNewFields() throws {
        var settings = TokenStepSettings.defaults
        settings.enabledQuotaProviders = [.codex, .cursor, .glm]
        settings.cursorQuotaEnabled = true
        settings.cursorCodeSignalEnabled = true
        settings.historyDays = 90
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(TokenStepSettings.self, from: data)
        XCTAssertEqual(decoded.enabledQuotaProviders, [.codex, .cursor, .glm])
        XCTAssertTrue(decoded.cursorQuotaEnabled)
        XCTAssertTrue(decoded.cursorCodeSignalEnabled)
        XCTAssertEqual(decoded.historyDays, 90)
        XCTAssertTrue(decoded.showCodexQuota)
    }

    func testCursorFlagStaysInSyncWithProviderSet() {
        var settings = TokenStepSettings.defaults
        settings.setQuotaProvider(.cursor, enabled: true)
        XCTAssertTrue(settings.cursorQuotaEnabled)
        XCTAssertTrue(settings.enabledQuotaProviders.contains(.cursor))
        settings.setQuotaProvider(.cursor, enabled: false)
        XCTAssertFalse(settings.cursorQuotaEnabled)
        XCTAssertFalse(settings.enabledQuotaProviders.contains(.cursor))
    }
}
