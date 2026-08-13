import XCTest
@testable import TokenStepSwift

/// G-V1 / V1-T01：统一新鲜度与失败状态模型（PRD §5.3 验收 fixtures）。
final class FreshnessModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let collectionTTL: TimeInterval = 300
    private let quotaTTL = FreshnessPolicy.quotaNormalTTL

    // 1. 首次启动：从未成功（无论是否已尝试）。
    func testNeverSucceededWhenNoSuccess() {
        let untouched = FreshnessPolicy.classify(
            enabled: true, record: RefreshAttemptRecord(), normalTTL: collectionTTL, now: now
        )
        XCTAssertEqual(untouched.kind, .neverSucceeded)

        let attemptedButFailed = RefreshAttemptRecord().attempting(at: now)
            .failing(kind: .collectionFailed, at: now)
        let failedOnce = FreshnessPolicy.classify(
            enabled: true, record: attemptedButFailed, normalTTL: collectionTTL, now: now
        )
        XCTAssertEqual(failedOnce.kind, .neverSucceeded)
        XCTAssertEqual(failedOnce.errorKind, .collectionFailed)
        XCTAssertNil(failedOnce.lastSucceededAt)
    }

    // 2. 刚成功：fresh。
    func testFreshAfterRecentSuccess() {
        let record = RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-10))
        let freshness = FreshnessPolicy.classify(
            enabled: true, record: record, normalTTL: collectionTTL, now: now
        )
        XCTAssertEqual(freshness.kind, .fresh)
        XCTAssertEqual(freshness.lastSucceededAt, record.lastSucceededAt)
    }

    // 3. 数据老化：超过正常 TTL 但不足 2×，且最近尝试没有明确失败。
    func testAgingBeyondNormalTTL() {
        let record = RefreshAttemptRecord(
            lastSucceededAt: now.addingTimeInterval(-collectionTTL - 1)
        )
        let freshness = FreshnessPolicy.classify(
            enabled: true, record: record, normalTTL: collectionTTL, now: now
        )
        XCTAssertEqual(freshness.kind, .aging)
    }

    // 3b. 超过 2×TTL：无论尝试成败都视为 stale。
    func testStaleBeyondDoubleTTL() {
        let record = RefreshAttemptRecord(
            lastSucceededAt: now.addingTimeInterval(-collectionTTL * 2 - 1)
        )
        let freshness = FreshnessPolicy.classify(
            enabled: true, record: record, normalTTL: collectionTTL, now: now
        )
        XCTAssertEqual(freshness.kind, .stale)
        XCTAssertNil(freshness.errorKind)
    }

    // 4. 请求失败有旧值：stale，保留最后成功时间与安全错误分类。
    func testStaleWhenAttemptFailedWithOldValue() {
        let succeededAt = now.addingTimeInterval(-30)
        var record = RefreshAttemptRecord(lastSucceededAt: succeededAt)
        record = record.attempting(at: now.addingTimeInterval(-5))
        record = record.failing(kind: .networkFailed, at: now.addingTimeInterval(-5))
        let freshness = FreshnessPolicy.classify(
            enabled: true, record: record, normalTTL: collectionTTL, now: now
        )
        XCTAssertEqual(freshness.kind, .stale)
        XCTAssertEqual(freshness.lastSucceededAt, succeededAt)
        XCTAssertEqual(freshness.errorKind, .networkFailed)
    }

    // 4b. 失败后再次成功：清除错误分类。
    func testSuccessClearsErrorKind() {
        var record = RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-600))
        record = record.failing(kind: .networkFailed, at: now.addingTimeInterval(-60))
        record = record.succeeding(at: now.addingTimeInterval(-10))
        let freshness = FreshnessPolicy.classify(
            enabled: true, record: record, normalTTL: collectionTTL, now: now
        )
        XCTAssertEqual(freshness.kind, .fresh)
        XCTAssertNil(freshness.errorKind)
    }

    // 5. 采集失败有旧快照：记录保留旧成功时间（UI 展示失败 + 最后成功时间）。
    func testCollectionFailureKeepsLastSucceededAt() {
        let succeededAt = now.addingTimeInterval(-120)
        var record = RefreshAttemptRecord(lastSucceededAt: succeededAt)
        record = record.failing(kind: .collectionFailed, at: now)
        XCTAssertEqual(record.lastSucceededAt, succeededAt)
        XCTAssertEqual(record.lastErrorKind, .collectionFailed)
        XCTAssertTrue(record.lastAttemptFailed)
    }

    // 6. Codex 成功但 Claude 失败：两个通道互不掩盖。
    func testQuotaChannelsAreIndependent() {
        let codex = FreshnessPolicy.classify(
            enabled: true,
            record: RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-10)),
            normalTTL: quotaTTL,
            now: now
        )
        var claudeRecord = RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-60))
        claudeRecord = claudeRecord.failing(kind: .unauthorized, at: now.addingTimeInterval(-1))
        let claude = FreshnessPolicy.classify(
            enabled: true, record: claudeRecord, normalTTL: quotaTTL, now: now
        )
        XCTAssertEqual(codex.kind, .fresh)
        XCTAssertEqual(claude.kind, .stale)
        XCTAssertEqual(claude.errorKind, .unauthorized)
    }

    // 7. 部分本地源失败：partial，附成功/失败来源清单（仅显示名）。
    func testPartialWhenMixedSourceStatuses() {
        let record = RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-10))
        let freshness = FreshnessPolicy.classify(
            enabled: true,
            record: record,
            normalTTL: collectionTTL,
            now: now,
            sourceStatuses: [
                "Codex": "ok",
                "Claude Code": "ok",
                "CC Switch via proxy": "incremental_cache_error",
                "ZCode": "disabled"
            ]
        )
        XCTAssertEqual(freshness.kind, .partial)
        XCTAssertEqual(freshness.successfulSources, ["Claude Code", "Codex"])
        XCTAssertEqual(freshness.failedSources, ["CC Switch via proxy"])
    }

    // 7b. 缺席来源（disabled / missing 各形态）不算失败：不误报 partial。
    func testNotPartialWhenAbsentSourcesOnly() {
        let record = RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-10))
        let freshness = FreshnessPolicy.classify(
            enabled: true,
            record: record,
            normalTTL: collectionTTL,
            now: now,
            sourceStatuses: [
                "Codex": "ok",
                "ZCode": "disabled",
                "CC Switch Proxy": "missing_valid_rows"
            ]
        )
        XCTAssertEqual(freshness.kind, .fresh)
    }

    // 8. 功能关闭：disabled（额度开关关闭时）。
    func testDisabledWhenFeatureOff() {
        let record = RefreshAttemptRecord(lastSucceededAt: now)
        let freshness = FreshnessPolicy.classify(
            enabled: false, record: record, normalTTL: quotaTTL, now: now
        )
        XCTAssertEqual(freshness.kind, .disabled)
    }

    // 9. 旧快照读取：缺失 source_attempt 的 JSON 按 nil 解码；新字段可往返。
    func testLegacySnapshotDecodesWithoutAttemptField() throws {
        let legacyJSON = """
        {
          "generated_at": "2026-08-13",
          "timezone": "Asia/Shanghai",
          "totals": {"tokens": 10, "cost": 0.1, "active_days": 1},
          "daily": [],
          "tools": [],
          "models": [],
          "sources": {}
        }
        """
        let legacy = try JSONDecoder().decode(UsageSnapshot.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(legacy.sourceAttempt)
        XCTAssertEqual(legacy.totals.tokens, 10)

        var modern = legacy
        modern.sourceAttempt = RefreshAttemptRecord(lastSucceededAt: now)
        let data = try JSONEncoder().encode(modern)
        let roundTripped = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        XCTAssertEqual(roundTripped.sourceAttempt, modern.sourceAttempt)
    }

    // 9b. 旧 freshness-state 读取：缺失字段取默认值。
    func testLegacyFreshnessStateDefaults() throws {
        let legacy = try JSONDecoder().decode(
            FreshnessState.self,
            from: Data("{}".utf8)
        )
        XCTAssertEqual(legacy, FreshnessState())
        XCTAssertNil(legacy.collection.lastSucceededAt)
        XCTAssertEqual(legacy.stateVersion, 1)

        let partialJSON = """
        {"collection": {"lastSucceededAt": 800000000}, "stateVersion": 2}
        """
        let decoded = try JSONDecoder().decode(FreshnessState.self, from: Data(partialJSON.utf8))
        XCTAssertNotNil(decoded.collection.lastSucceededAt)
        XCTAssertNil(decoded.codexQuota.lastAttemptedAt)
        XCTAssertEqual(decoded.stateVersion, 2)
    }

    // 10. 错误安全分类：不保留正文，只保留类别。
    func testErrorClassificationIsSafe() {
        XCTAssertEqual(
            FreshnessPolicy.classify(error: URLError(.timedOut)),
            .timeout
        )
        XCTAssertEqual(
            FreshnessPolicy.classify(error: URLError(.notConnectedToInternet)),
            .networkFailed
        )
        XCTAssertEqual(
            FreshnessPolicy.classify(
                error: NSError(domain: NSURLErrorDomain, code: 401)
            ),
            .unauthorized
        )
        let keychainError = TokenStepError.message("无法读取钥匙串凭据（/Users/x/secret）")
        let kind = FreshnessPolicy.classify(error: keychainError)
        XCTAssertEqual(kind, .unauthorized)
        // 分类结果本身不携带任何路径或正文。
        let encoded = kind.rawValue
        XCTAssertFalse(encoded.contains("/Users"))
        XCTAssertFalse(encoded.contains("secret"))
    }

    // 11. 阈值集中在 policy：collection TTL 受用户刷新间隔与自动重试下限约束。
    func testCollectionTTLFollowsPolicy() {
        XCTAssertEqual(
            FreshnessPolicy.collectionNormalTTL(refreshIntervalSeconds: 600),
            600
        )
        XCTAssertEqual(
            FreshnessPolicy.collectionNormalTTL(refreshIntervalSeconds: 30),
            EnergyRefreshPolicy.minimumAutomaticRetryTTL
        )
        XCTAssertEqual(
            FreshnessPolicy.staleTTL(normalTTL: 600),
            1200
        )
    }
}
