import Foundation
import XCTest
@testable import TokenStepSwift

final class TraeQuotaServiceTests: XCTestCase {
    // Trae CN：credits 口径，汇总所有额度包
    func testTraeCNWindowsSumCreditPacks() {
        let payload: [String: Any] = [
            "code": 0,
            "user_entitlement_pack_list": [
                [
                    "entitlement_base_info": [
                        "quota": ["credits_limit": 1000],
                        "end_time": 1_900_000_000
                    ],
                    "usage": ["credits_amount": 250]
                ],
                [
                    "entitlement_base_info": [
                        "quota": ["credits_limit": 500],
                        "end_time": 1_950_000_000
                    ],
                    "usage": ["credits_amount": 50]
                ]
            ]
        ]
        let windows = TraeCNQuotaService.windows(from: payload)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].kind, .monthlyCredits)
        XCTAssertEqual(windows[0].total ?? -1, 1500, accuracy: 0.01)
        XCTAssertEqual(windows[0].remaining ?? -1, 1200, accuracy: 0.01)
        XCTAssertEqual(windows[0].usedPercent, 20, accuracy: 0.01)
        XCTAssertEqual(windows[0].resetsAt, Date(timeIntervalSince1970: 1_900_000_000))
    }

    // Trae CN：存在不限量包（credits_limit = -1）时不显示额度窗
    func testTraeCNWindowsSkipUnlimitedPacks() {
        let payload: [String: Any] = [
            "user_entitlement_pack_list": [
                [
                    "entitlement_base_info": ["quota": ["credits_limit": -1]],
                    "usage": ["credits_amount": 10]
                ]
            ]
        ]
        XCTAssertTrue(TraeCNQuotaService.windows(from: payload).isEmpty)
    }

    // Trae CN：未认证响应（code 1001，已用真实未认证请求验证此结构）不产出窗口
    func testTraeCNWindowsEmptyForUnauthenticatedPayload() {
        let payload: [String: Any] = [
            "code": 1001,
            "message": "not authenticated",
            "usage_summary": [:] as [String: Any],
            "user_entitlement_pack_list": [] as [Any]
        ]
        XCTAssertTrue(TraeCNQuotaService.windows(from: payload).isEmpty)
    }

    // Trae 国际版：美元口径 basic + bonus
    func testTraeGlobalWindowsSumBasicAndBonus() {
        let payload: [String: Any] = [
            "user_entitlement_pack_list": [
                [
                    "display_desc": "Pro",
                    "entitlement_base_info": [
                        "quota": [
                            "basic_usage_limit": 10,
                            "bonus_usage_limit": 5
                        ],
                        "end_time": 1_900_000_000
                    ],
                    "usage": [
                        "basic_usage_amount": 3,
                        "bonus_usage_amount": 1.5
                    ]
                ]
            ]
        ]
        let windows = TraeQuotaService.windows(from: payload)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].kind, .spend)
        XCTAssertEqual(windows[0].total ?? -1, 15, accuracy: 0.01)
        XCTAssertEqual(windows[0].remaining ?? -1, 10.5, accuracy: 0.01)
        XCTAssertEqual(windows[0].usedPercent, 30, accuracy: 0.01)
    }

    // Trae 国际版：没有额度包时不产出窗口
    func testTraeGlobalWindowsEmptyWithoutPacks() {
        XCTAssertTrue(TraeQuotaService.windows(from: ["user_entitlement_pack_list": []]).isEmpty)
        XCTAssertTrue(TraeQuotaService.windows(from: [:]).isEmpty)
    }

    // 两个 provider 都走手动凭证（令牌只进钥匙串），设置页据此渲染输入框与引导
    func testTraeProvidersNeedManualCredential() {
        XCTAssertTrue(QuotaProviderID.trae.needsManualCredential)
        XCTAssertTrue(QuotaProviderID.traeCN.needsManualCredential)
        XCTAssertEqual(QuotaProviderID.trae.secretAccount, .traeAccessToken)
        XCTAssertEqual(QuotaProviderID.traeCN.secretAccount, .traeCNAccessToken)
    }

    // 引导文案依赖 displayName / credentialHint 非空
    func testTraeProvidersHaveDisplayCopy() {
        XCTAssertEqual(QuotaProviderID.trae.displayName, "Trae")
        XCTAssertEqual(QuotaProviderID.traeCN.displayName, "Trae CN")
        XCTAssertFalse(QuotaProviderID.trae.credentialHint.isEmpty)
        XCTAssertFalse(QuotaProviderID.traeCN.credentialHint.isEmpty)
    }

    // 毫秒时间戳也应被正确换算
    func testTraeCNWindowsParseMillisecondEndTime() {
        let payload: [String: Any] = [
            "user_entitlement_pack_list": [
                [
                    "entitlement_base_info": [
                        "quota": ["credits_limit": 100],
                        "end_time": 1_900_000_000_000
                    ],
                    "usage": ["credits_amount": 10]
                ]
            ]
        ]
        let windows = TraeCNQuotaService.windows(from: payload)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].resetsAt, Date(timeIntervalSince1970: 1_900_000_000))
    }
}
