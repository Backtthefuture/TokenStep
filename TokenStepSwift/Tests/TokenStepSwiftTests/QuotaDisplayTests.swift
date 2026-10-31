import Foundation
import XCTest
@testable import TokenStepSwift

final class QuotaDisplayTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let calendar = Calendar(identifier: .gregorian)

    // Trae CN：积分口径渲染的是绝对值，不是“本月额度 4%”
    func testCreditsWindowRendersAbsoluteCreditAmounts() {
        let window = QuotaWindow(
            kind: .monthlyCredits,
            usedPercent: 163.12 / 4_600 * 100,
            remaining: 4_600 - 163.12,
            total: 4_600,
            resetsAt: now.addingTimeInterval(86_400),
            unit: .credits
        )
        XCTAssertEqual(window.resolvedUnit, .credits)
        XCTAssertEqual(window.title, L("积分额度"))

        let row = CompactPopoverModel.windowRow(window, now: now, calendar: calendar)
        let expectedUsage = LFormat(
            "已用 %@ / %@ 积分",
            TokenStepFormat.whole(163),
            TokenStepFormat.whole(4_600)
        )
        XCTAssertEqual(row.unit, .credits)
        XCTAssertEqual(row.creditUsageText, expectedUsage)
        XCTAssertEqual(
            row.creditRemainingText,
            LFormat("剩余 %@ 积分", TokenStepFormat.whole(4_437))
        )
        // Credits have no fixed window length, so no pace tick is invented.
        XCTAssertNil(row.elapsedFraction)
        XCTAssertFalse(row.runsOutEarly)
        XCTAssertEqual(row.usedPercent, 163.12 / 4_600 * 100, accuracy: 0.0001)
    }

    // 原有 percent provider 完全不受影响
    func testPercentWindowKeepsExistingRendering() {
        let window = QuotaWindow(
            kind: .fiveHour,
            usedPercent: 42,
            remaining: 58,
            total: 100,
            resetsAt: now.addingTimeInterval(2 * 60 * 60)
        )
        XCTAssertEqual(window.resolvedUnit, .percent)
        XCTAssertEqual(window.title, L("5 小时"))
        XCTAssertNil(window.creditAmounts)

        let row = CompactPopoverModel.windowRow(window, now: now, calendar: calendar)
        XCTAssertEqual(row.unit, .percent)
        XCTAssertNil(row.creditUsageText)
        XCTAssertNil(row.creditRemainingText)
        XCTAssertEqual(row.usedPercent, 42, accuracy: 0.001)
        XCTAssertNotNil(row.elapsedFraction)
    }

    // 共用 monthlyCredits 的 GLM/Cursor/Grok 不会被积分语义带偏
    func testMonthlyCreditsWithoutUnitStaysPercentLabel() {
        let window = QuotaWindow(
            kind: .monthlyCredits,
            usedPercent: 20,
            remaining: 800,
            total: 1_000,
            resetsAt: now.addingTimeInterval(86_400)
        )
        XCTAssertEqual(window.resolvedUnit, .percent)
        XCTAssertEqual(window.title, L("本月额度"))
        XCTAssertNil(window.creditAmounts)
    }

    // 美元口径保留「花费」语义
    func testUsdWindowKeepsSpendSemantics() {
        let window = QuotaWindow(
            kind: .spend,
            usedPercent: 30,
            remaining: 7,
            total: 10,
            resetsAt: nil,
            unit: .usd
        )
        XCTAssertEqual(window.title, L("花费"))
        XCTAssertNil(window.creditAmounts)
        let row = CompactPopoverModel.windowRow(window, now: now, calendar: calendar)
        XCTAssertNil(row.creditUsageText)
        XCTAssertEqual(row.usedPercent, 30, accuracy: 0.001)
    }

    // 仪表盘列出所有已启用 provider，未读取到的也要有可读原因
    func testDisplayQuotasIncludesEnabledProvidersWithReason() {
        let codex = ProviderQuota(
            provider: .codex,
            windows: [
                QuotaWindow(kind: .fiveHour, usedPercent: 40, remaining: 60, total: 100)
            ],
            status: .available,
            fetchedAt: now,
            message: nil
        )
        let quotas = QuotaPresentation.displayQuotas(
            enabled: [.codex, .traeCN],
            quotas: [.codex: codex]
        )
        XCTAssertEqual(quotas.map(\.provider), [.codex, .traeCN])
        XCTAssertTrue(quotas[0].isAvailable)
        XCTAssertFalse(quotas[1].isAvailable)
        XCTAssertEqual(
            QuotaPresentation.unavailableReason(quotas[1], isRefreshing: false),
            L("尚未读取到额度，稍后会自动重试")
        )
        XCTAssertEqual(
            QuotaPresentation.unavailableReason(quotas[1], isRefreshing: true),
            L("正在读取额度…")
        )
    }

    // 失败原因优先使用服务端点名的具体文案
    func testUnavailableReasonSurfacesProviderMessage() {
        let quota = ProviderQuota.unavailable(
            .traeCN,
            status: .unavailable,
            message: "Trae 鉴权失败（HTTP 401，code 1001）：登录已过期或令牌无效，请点「用浏览器登录」重新授权"
        )
        XCTAssertEqual(QuotaPresentation.unavailableReason(quota, isRefreshing: false), quota.message)

        let signedOut = ProviderQuota.unavailable(.glm, status: .notLoggedIn)
        XCTAssertEqual(
            QuotaPresentation.unavailableReason(signedOut, isRefreshing: false),
            L("未登录，请在设置里授权")
        )
    }

    // 未启用的 provider 不出现在仪表盘
    func testDisplayQuotasSkipsDisabledProviders() {
        let quotas = QuotaPresentation.displayQuotas(enabled: [.traeCN], quotas: [:])
        XCTAssertEqual(quotas.map(\.provider), [.traeCN])
    }

    // 英文表构建时会校验重复键；这条确保积分文案真的有翻译
    func testEnglishTranslationsLoadForCreditsCopy() {
        TokenStepLocalization.apply(.en)
        defer { TokenStepLocalization.apply(.system) }
        XCTAssertEqual(L("积分额度"), "Credit balance")
        XCTAssertTrue(L("订阅额度").contains("Quota"))
    }
}
