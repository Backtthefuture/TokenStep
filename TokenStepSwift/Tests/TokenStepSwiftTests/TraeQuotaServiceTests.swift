import Foundation
import XCTest
@testable import TokenStepSwift

final class TraeQuotaServiceTests: XCTestCase {
    /// 形状合法的占位 JWT，只用于断言请求头，不含真实令牌。
    private let sampleJWT = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0cmFlIn0.signature"

    override func tearDown() {
        HTTPJSONClient.resetTransport()
        super.tearDown()
    }

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
        XCTAssertEqual(windows[0].unit, .credits)
        XCTAssertEqual(windows[0].total ?? -1, 1500, accuracy: 0.01)
        XCTAssertEqual(windows[0].remaining ?? -1, 1200, accuracy: 0.01)
        XCTAssertEqual(windows[0].usedPercent, 20, accuracy: 0.01)
        XCTAssertEqual(windows[0].resetsAt, Date(timeIntervalSince1970: 1_900_000_000))
    }

    // Trae CN：usage_summary 与 consumption_ratio 是 IDE 面板口径，优先于额度包汇总
    func testTraeCNPrefersUsageSummaryOverPackSums() {
        let payload: [String: Any] = [
            "usage_summary": [
                "consumed_amount": 200.0,
                "total_amount": 1000.0,
                "consumption_ratio": 0.2
            ],
            "user_entitlement_pack_list": [
                [
                    "entitlement_base_info": ["quota": ["credits_limit": 1000]],
                    "usage": ["credits_amount": 10]
                ]
            ]
        ]
        let windows = TraeCNQuotaService.windows(from: payload)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].unit, .credits)
        XCTAssertEqual(windows[0].total ?? -1, 1000, accuracy: 0.01)
        XCTAssertEqual(windows[0].remaining ?? -1, 800, accuracy: 0.01)
        XCTAssertEqual(windows[0].usedPercent, 20, accuracy: 0.01)
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
        XCTAssertEqual(windows[0].unit, .usd)
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

    // MARK: - 鉴权方式（真实联调结论：Bearer 401，Cloud-IDE-JWT 200）

    /// 真实账号响应的裁剪样本：三个有额度的包（4000 / 500 / 100），
    /// 已用 151.0772 credits；另一个包的 quota 为空，应被跳过。
    private let liveCNPayload = #"""
    {
      "is_credits_billing": true,
      "is_dollar_usage_billing": false,
      "usage_summary": {"consumed_amount": 151.0772, "consumption_ratio": 0.03284347826086957, "total_amount": 4600},
      "user_entitlement_pack_list": [
        {"entitlement_base_info": {"quota": {"credits_limit": 4000}, "end_time": 1796047504}},
        {"entitlement_base_info": {"quota": {}, "end_time": 1793462399}},
        {"entitlement_base_info": {"quota": {"credits_limit": 500}, "end_time": 1793462399}, "usage": {"credits_amount": 151.0772}},
        {"entitlement_base_info": {"quota": {"credits_limit": 100}, "end_time": 1796086160}}
      ]
    }
    """#

    func testTraeCNRequestUsesCloudIDEJWTHeaderAndParsesLivePayload() throws {
        var seen: URLRequest?
        HTTPJSONClient.transport = { request in
            seen = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(self.liveCNPayload.utf8), response)
        }
        let payload = try TraeCNQuotaService.fetchPayload(token: sampleJWT)
        XCTAssertEqual(seen?.value(forHTTPHeaderField: "Authorization"), "Cloud-IDE-JWT \(sampleJWT)")
        XCTAssertEqual(seen?.url?.absoluteString, "https://api.trae.cn/trae/api/v2/pay/ide_user_ent_usage")
        let body = try XCTUnwrap(seen?.httpBody)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["require_usage"] as? Bool, true)
        XCTAssertEqual(object["req_source"] as? Int, 0)

        let windows = TraeCNQuotaService.windows(from: payload)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].unit, .credits)
        XCTAssertEqual(windows[0].total ?? -1, 4600, accuracy: 0.01)
        XCTAssertEqual(windows[0].remaining ?? -1, 4448.9228, accuracy: 0.01)
        XCTAssertEqual(windows[0].usedPercent, 3.2843, accuracy: 0.01)
        XCTAssertEqual(windows[0].resetsAt, Date(timeIntervalSince1970: 1_793_462_399))
    }

    func testTraeGlobalRequestUsesCloudIDEJWTHeader() throws {
        var seen: URLRequest?
        HTTPJSONClient.transport = { request in
            seen = request
            let body = #"""
            {"user_entitlement_pack_list":[{"entitlement_base_info":{"quota":{"basic_usage_limit":10,"bonus_usage_limit":5},"end_time":1900000000},"usage":{"basic_usage_amount":3,"bonus_usage_amount":1.5}}]}
            """#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
        let payload = try TraeQuotaService.fetchPayload(token: sampleJWT)
        XCTAssertEqual(seen?.value(forHTTPHeaderField: "Authorization"), "Cloud-IDE-JWT \(sampleJWT)")
        XCTAssertEqual(seen?.url?.host, "api-sg-central.trae.ai")
        XCTAssertEqual(TraeQuotaService.windows(from: payload).first?.total ?? -1, 15, accuracy: 0.01)
    }

    // 401 不是笼统错误：要带上状态与业务 code，并继续走自动刷新
    func testTraeCNUnauthorizedIsClassifiedAsAuthFailure() {
        HTTPJSONClient.transport = { request in
            let body = #"{"code":1001,"message":"not able to authenticate you"}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
        XCTAssertThrowsError(try TraeCNQuotaService.fetchPayload(token: sampleJWT)) { error in
            let text = error.localizedDescription
            XCTAssertTrue(text.contains("HTTP 401"))
            XCTAssertTrue(text.contains("code 1001"))
            XCTAssertTrue(text.contains("用浏览器登录"))
            XCTAssertTrue(TraeQuotaAuth.isAuthFailure(error))
        }
    }

    // 服务端 5xx 不属于鉴权问题，不能被刷新掩盖
    func testTraeCNServerErrorIsNotAuthFailure() {
        HTTPJSONClient.transport = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        }
        XCTAssertThrowsError(try TraeCNQuotaService.fetchPayload(token: sampleJWT)) { error in
            XCTAssertTrue(error.localizedDescription.contains("HTTP 500"))
            XCTAssertFalse(TraeQuotaAuth.isAuthFailure(error))
        }
    }

    // 手动粘贴里混入非 JWT 值时不发请求，直接提示令牌类型不对
    func testTraeCNRejectsNonJWTBeforeRequesting() {
        var calls = 0
        HTTPJSONClient.transport = { request in
            calls += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(self.liveCNPayload.utf8), response)
        }
        XCTAssertThrowsError(try TraeCNQuotaService.fetchPayload(token: "api-key-not-a-jwt")) { error in
            XCTAssertTrue(error.localizedDescription.contains("不是 Trae IDE 版 JWT"))
            XCTAssertTrue(TraeQuotaAuth.isAuthFailure(error))
        }
        XCTAssertEqual(calls, 0)
    }
}

