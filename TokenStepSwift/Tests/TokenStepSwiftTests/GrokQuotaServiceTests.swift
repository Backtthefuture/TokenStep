import Foundation
import XCTest
@testable import TokenStepSwift

final class GrokQuotaServiceTests: XCTestCase {
    func testReadsIssuerScopedKeyFromCurrentAuthJSON() {
        let payload: [String: Any] = [
            "https://auth.x.ai::client-id": [
                "key": "eyJhbGciOiJIUzI1NiJ9.payload.sig",
                "auth_mode": "oidc",
                "refresh_token": "refresh-token-value"
            ]
        ]
        XCTAssertEqual(
            GrokQuotaService.sessionToken(from: payload),
            "eyJhbGciOiJIUzI1NiJ9.payload.sig"
        )
    }

    func testParsesWeeklyCreditsPercent() {
        let payload: [String: Any] = [
            "config": [
                "creditUsagePercent": 13,
                "currentPeriod": [
                    "type": "USAGE_PERIOD_TYPE_WEEKLY",
                    "end": "2026-08-24T00:00:00.000Z"
                ]
            ]
        ]
        let windows = GrokQuotaService.windows(from: payload)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].kind, .weekly)
        XCTAssertEqual(windows[0].usedPercent, 13, accuracy: 0.01)
        XCTAssertEqual(windows[0].remainingPercent, 87, accuracy: 0.01)
    }

    func testParsesMonthlyCentValuesWhenLimitExists() {
        let payload: [String: Any] = [
            "config": [
                "monthlyLimit": ["val": 6000],
                "used": ["val": 1740],
                "billingPeriodEnd": "2026-09-01T00:00:00Z"
            ]
        ]
        let windows = GrokQuotaService.windows(from: payload)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].kind, .monthlyCredits)
        XCTAssertEqual(windows[0].usedPercent, 29, accuracy: 0.01)
    }

    func testIgnoresZeroMonthlyLimit() {
        let payload: [String: Any] = [
            "config": [
                "monthlyLimit": ["val": 0],
                "used": ["val": 12]
            ]
        ]
        XCTAssertTrue(GrokQuotaService.windows(from: payload).isEmpty)
    }

    func testIgnoresDeviceCodeAndPlainXAIKey() {
        XCTAssertFalse(GrokQuotaService.looksLikeSessionToken("ABCD-EFGH"))
        XCTAssertFalse(GrokQuotaService.looksLikeSessionToken("xai-plain-key"))
        XCTAssertTrue(GrokQuotaService.looksLikeSessionToken("eyJhbGciOiJIUzI1NiJ9.payload.sig"))
        XCTAssertNil(
            GrokQuotaService.sessionToken(from: [
                "api_key": "xai-plain-key",
                "key": "xai-plain-key"
            ])
        )
    }
}
