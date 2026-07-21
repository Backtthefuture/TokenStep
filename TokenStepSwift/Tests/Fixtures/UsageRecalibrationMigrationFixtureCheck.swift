import Foundation

@main
struct UsageRecalibrationMigrationFixtureCheck {
    static func main() throws {
        let root = AppPaths.appSupportRoot
        try? FileManager.default.removeItem(at: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let currentRevision = UsageCollector.codexAccountingRevision
        let legacy = snapshot(accountingRevision: nil, records: 1)
        let previous = snapshot(accountingRevision: currentRevision - 1, records: 1)
        let current = snapshot(accountingRevision: currentRevision, records: 2)
        let future = snapshot(accountingRevision: currentRevision + 1, records: 1)
        let emptyLegacy = snapshot(accountingRevision: nil, records: 0)
        var missingCodex = current
        missingCodex.sources.removeValue(forKey: "Codex")

        try expect(
            DataService.requiresImmediateCodexRecalibration(legacy),
            "legacy snapshots with Codex records should recalibrate immediately"
        )
        try expect(
            DataService.requiresImmediateCodexRecalibration(previous),
            "older accounting revisions should recalibrate immediately"
        )
        try expect(
            !DataService.requiresImmediateCodexRecalibration(current),
            "the current accounting revision should not recalibrate again"
        )
        try expect(
            !DataService.requiresImmediateCodexRecalibration(future),
            "a future accounting revision should not be downgraded"
        )
        try expect(
            !DataService.requiresImmediateCodexRecalibration(emptyLegacy),
            "an empty legacy source should not trigger a recalibration loop"
        )
        try expect(
            !DataService.requiresImmediateCodexRecalibration(missingCodex),
            "a snapshot without Codex usage should not require Codex recalibration"
        )

        let migrated = try DataService.persistSnapshotForMigrationTests(
            current,
            previousSnapshot: legacy
        )
        try expect(
            migrated.sources["Codex"]?.recalibratedFromRevision == 5,
            "legacy snapshots should be treated as accounting revision 5"
        )
        try expect(
            DataService.hasPendingUsageRecalibrationNotice,
            "successful legacy migration should create the pending notice marker"
        )
        try expect(
            try String(contentsOf: AppPaths.usageRecalibrationNoticeMarker, encoding: .utf8)
                == "\(currentRevision)",
            "pending marker should identify the current accounting revision"
        )

        DataService.acknowledgeUsageRecalibrationNotice()
        try expect(
            !DataService.hasPendingUsageRecalibrationNotice,
            "acknowledging the notice should remove its marker"
        )

        try? FileManager.default.removeItem(at: root)
        _ = try DataService.persistSnapshotForMigrationTests(current, previousSnapshot: nil)
        try expect(
            !DataService.hasPendingUsageRecalibrationNotice,
            "a new installation must not see a migration notice"
        )

        let alreadyCurrent = snapshot(accountingRevision: currentRevision, records: 1)
        _ = try DataService.persistSnapshotForMigrationTests(current, previousSnapshot: alreadyCurrent)
        try expect(
            !DataService.hasPendingUsageRecalibrationNotice,
            "an already-current snapshot must not recreate the notice"
        )

        try? FileManager.default.removeItem(at: root)
        _ = try DataService.persistSnapshotForMigrationTests(legacy, previousSnapshot: nil)
        let failedRecalibration = snapshot(accountingRevision: currentRevision, records: 0)
        do {
            _ = try DataService.persistSnapshotForMigrationTests(
                failedRecalibration,
                previousSnapshot: legacy
            )
            throw NSError(
                domain: "UsageRecalibrationMigrationFixture",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "an empty recalibration must fail"]
            )
        } catch let error as NSError where error.domain == "TokenStepCollector" {
            // Expected: the old snapshot must stay intact until a valid v8 scan exists.
        }
        let preserved = try DataService.loadSnapshot()
        try expect(
            preserved.totals.tokens == legacy.totals.tokens,
            "a failed recalibration must preserve the previous usage snapshot"
        )
        try expect(
            !DataService.hasPendingUsageRecalibrationNotice,
            "a failed recalibration must not create a migration notice"
        )

        let sqliteFallback = snapshot(
            accountingRevision: nil,
            records: 1,
            status: "ok_sqlite"
        )
        do {
            _ = try DataService.persistSnapshotForMigrationTests(
                sqliteFallback,
                previousSnapshot: legacy
            )
            throw NSError(
                domain: "UsageRecalibrationMigrationFixture",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "a SQLite fallback must not complete recalibration"]
            )
        } catch let error as NSError where error.domain == "TokenStepCollector" {
            // Expected: an approximate fallback cannot overwrite an older exact snapshot.
        }
        let preservedAfterFallback = try DataService.loadSnapshot()
        try expect(
            preservedAfterFallback.totals.tokens == legacy.totals.tokens,
            "a SQLite fallback must preserve the previous usage snapshot"
        )
        try expect(
            !DataService.hasPendingUsageRecalibrationNotice,
            "a SQLite fallback must not create a migration notice"
        )

        print("PASS: usage recalibration migration marker and failure preservation")
    }

    private static func snapshot(
        accountingRevision: Int?,
        records: Int,
        status: String = "ok"
    ) -> UsageSnapshot {
        UsageSnapshot(
            generatedAt: "2026-07-13T00:00:00Z",
            timezone: "Asia/Shanghai",
            totals: UsageTotals(tokens: records * 100, cost: 0, activeDays: records > 0 ? 1 : 0),
            daily: [],
            tools: [],
            models: [],
            sources: [
                "Codex": SourceInfo(
                    status: status,
                    files: records > 0 ? 1 : 0,
                    records: records,
                    accountingRevision: accountingRevision
                )
            ]
        )
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else {
            throw NSError(
                domain: "UsageRecalibrationMigrationFixture",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}
