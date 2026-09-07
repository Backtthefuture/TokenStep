import Foundation
import XCTest

@testable import TokenStepSwift

final class GLMQuotaServiceTests: XCTestCase {
    func testLimitPayloadProducesWindows() throws {
        let payload: [String: Any] = [
            "code": 200,
            "msg": "Operation successful",
            "success": true,
            "level": "pro",
            "data": [
                "limits": [
                    [
                        "type": "TOKENS_LIMIT",
                        "unit": 3,
                        "number": 5,
                        "percentage": 7,
                        "nextResetTime": 1787803109941
                    ],
                    [
                        "type": "TOKENS_LIMIT",
                        "unit": 6,
                        "number": 1,
                        "percentage": 1,
                        "nextResetTime": 1787806941998
                    ],
                    [
                        "type": "TIME_LIMIT",
                        "unit": 5,
                        "number": 1,
                        "usage": 1000,
                        "currentValue": 7,
                        "remaining": 993,
                        "percentage": 1,
                        "usageDetails": [["modelCode": "search-prime", "usage": 4]]
                    ]
                ]
            ]
        ]
        let windows = GLMQuotaService.windows(from: payload)
        XCTAssertEqual(windows.count, 3)
        XCTAssertEqual(windows[0].kind, .fiveHour)
        XCTAssertEqual(windows[0].usedPercent, 7, accuracy: 0.01)
        let expectedFirstReset = Date(timeIntervalSince1970: 1787803109.941)
        XCTAssertEqual(try XCTUnwrap(windows[0].resetsAt).timeIntervalSince1970, expectedFirstReset.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(windows[1].kind, .sevenDay)
        XCTAssertEqual(windows[1].usedPercent, 1, accuracy: 0.01)
        XCTAssertEqual(windows[2].kind, .monthlyCredits)
    }

    func testEmptyLimitsFallsBackToLegacyParsing() {
        let legacy: [String: Any] = ["data": ["daily": ["used_percent": 42]]]
        let windows = GLMQuotaService.windows(from: legacy)
        XCTAssertFalse(windows.isEmpty)
    }
}
