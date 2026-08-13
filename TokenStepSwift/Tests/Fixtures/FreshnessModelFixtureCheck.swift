import Foundation

// G-V1 / V1-T01：统一新鲜度状态模型的本地可执行校验（无 Xcode 环境亦可跑）。
// 与 FreshnessModelTests 保持同一套口径；CI 上以 XCTest 全量为准。
@main
struct FreshnessModelFixtureCheck {
    static func main() {
        do {
            try checkSixStates()
            try checkQuotaChannelIndependence()
            try checkPartialSources()
            try checkLegacyDecode()
            try checkErrorClassification()
            try checkRecordTransitions()
            print("Freshness model fixture checks passed")
        } catch {
            fputs("Freshness model fixture failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let ttl: TimeInterval = 300

    private static func classify(
        _ record: RefreshAttemptRecord,
        enabled: Bool = true,
        sourceStatuses: [String: String]? = nil
    ) -> UsageFreshness {
        FreshnessPolicy.classify(
            enabled: enabled,
            record: record,
            normalTTL: ttl,
            now: now,
            sourceStatuses: sourceStatuses
        )
    }

    private static func checkSixStates() throws {
        // 首次启动（未尝试 / 尝试过但从未成功）。
        try expectEqual(classify(RefreshAttemptRecord()).kind, .neverSucceeded, "untouched is neverSucceeded")
        let failedNoValue = RefreshAttemptRecord().attempting(at: now).failing(kind: .collectionFailed, at: now)
        try expectEqual(classify(failedNoValue).kind, .neverSucceeded, "failed-without-value is neverSucceeded")

        // 刚成功 → fresh；超过 TTL 但不足 2× → aging；超过 2× → stale。
        try expectEqual(
            classify(RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-10))).kind,
            .fresh,
            "recent success is fresh"
        )
        try expectEqual(
            classify(RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-ttl - 1))).kind,
            .aging,
            "beyond TTL without failure is aging"
        )
        try expectEqual(
            classify(RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-ttl * 2 - 1))).kind,
            .stale,
            "beyond 2x TTL is stale"
        )

        // 失败有旧值 → stale 且保留成功时间与错误分类。
        let staleRecord = RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-30))
            .attempting(at: now.addingTimeInterval(-5))
            .failing(kind: .networkFailed, at: now.addingTimeInterval(-5))
        let stale = classify(staleRecord)
        try expectEqual(stale.kind, .stale, "failed with old value is stale")
        try expectEqual(stale.errorKind, .networkFailed, "stale keeps error kind")
        try expectNotNil(stale.lastSucceededAt, "stale keeps lastSucceededAt")

        // 功能关闭 → disabled。
        try expectEqual(
            classify(RefreshAttemptRecord(lastSucceededAt: now), enabled: false).kind,
            .disabled,
            "disabled when feature off"
        )
    }

    private static func checkQuotaChannelIndependence() throws {
        let quotaTTL = FreshnessPolicy.quotaNormalTTL
        let codex = FreshnessPolicy.classify(
            enabled: true,
            record: RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-10)),
            normalTTL: quotaTTL,
            now: now
        )
        let claude = FreshnessPolicy.classify(
            enabled: true,
            record: RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-60))
                .failing(kind: .unauthorized, at: now.addingTimeInterval(-1)),
            normalTTL: quotaTTL,
            now: now
        )
        try expectEqual(codex.kind, .fresh, "codex quota stays fresh")
        try expectEqual(claude.kind, .stale, "claude quota failure does not leak into codex")
        try expectEqual(claude.errorKind, .unauthorized, "claude keeps its own error kind")
    }

    private static func checkPartialSources() throws {
        let record = RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-10))
        let partial = classify(
            record,
            sourceStatuses: [
                "Codex": "ok",
                "Claude Code": "ok_sqlite",
                "CC Switch via proxy": "incremental_cache_error",
                "ZCode": "disabled"
            ]
        )
        try expectEqual(partial.kind, .partial, "mixed sources are partial")
        try expectEqual(partial.successfulSources ?? [], ["Claude Code", "Codex"], "successful source names")
        try expectEqual(partial.failedSources ?? [], ["CC Switch via proxy"], "failed source names exclude absent")

        let allGood = classify(
            record,
            sourceStatuses: ["Codex": "ok", "ZCode": "disabled", "CC Switch Proxy": "missing_valid_rows"]
        )
        try expectEqual(allGood.kind, .fresh, "absent-only mix stays fresh")
    }

    private static func checkLegacyDecode() throws {
        let legacyJSON = """
        {
          "generated_at": "2026-08-13",
          "timezone": "Asia/Shanghai",
          "totals": {"tokens": 10, "cost": 0.1, "active_days": 1},
          "daily": [], "tools": [], "models": [], "sources": {}
        }
        """
        let legacy = try JSONDecoder().decode(UsageSnapshot.self, from: Data(legacyJSON.utf8))
        try expectNil(legacy.sourceAttempt, "legacy snapshot decodes without source_attempt")

        var modern = legacy
        modern.sourceAttempt = RefreshAttemptRecord(lastSucceededAt: now)
        let roundTripped = try JSONDecoder().decode(
            UsageSnapshot.self,
            from: try JSONEncoder().encode(modern)
        )
        try expectEqual(roundTripped.sourceAttempt, modern.sourceAttempt, "source_attempt round-trips")

        let emptyState = try JSONDecoder().decode(FreshnessState.self, from: Data("{}".utf8))
        try expectEqual(emptyState, FreshnessState(), "empty freshness state uses defaults")
    }

    private static func checkErrorClassification() throws {
        try expectEqual(FreshnessPolicy.classify(error: URLError(.timedOut)), .timeout, "URLError timedOut")
        try expectEqual(
            FreshnessPolicy.classify(error: URLError(.notConnectedToInternet)),
            .networkFailed,
            "URLError offline"
        )
        try expectEqual(
            FreshnessPolicy.classify(error: FixtureMessageError("无法读取钥匙串凭据（/Users/x/secret）")),
            .unauthorized,
            "keychain message maps to unauthorized"
        )
        // 用户可见文案必须是安全分类，不含路径/正文。
        let summary = UsageErrorKind.collectionFailed.localizedSummary
        try expectTrue(!summary.isEmpty, "summary is non-empty")
    }

    private static func checkRecordTransitions() throws {
        var record = RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-600))
        record = record.failing(kind: .networkFailed, at: now.addingTimeInterval(-60))
        try expectTrue(record.lastAttemptFailed, "failed attempt detected")
        record = record.succeeding(at: now.addingTimeInterval(-10))
        try expectNil(record.lastErrorKind, "success clears error kind")
        try expectTrue(!record.lastAttemptFailed, "success clears failure flag")
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
    guard actual == expected else {
        throw FixtureFailure("\(label): expected \(expected), got \(actual)")
    }
}

private func expectNotNil(_ value: Any?, _ label: String) throws {
    guard value != nil else { throw FixtureFailure("\(label): expected non-nil") }
}

private func expectNil(_ value: Any?, _ label: String) throws {
    guard value == nil else { throw FixtureFailure("\(label): expected nil") }
}

private func expectTrue(_ value: Bool, _ label: String) throws {
    guard value else { throw FixtureFailure("\(label): expected true") }
}

private struct FixtureMessageError: LocalizedError {
    var message: String
    var errorDescription: String? { message }

    init(_ message: String) {
        self.message = message
    }
}

private struct FixtureFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
