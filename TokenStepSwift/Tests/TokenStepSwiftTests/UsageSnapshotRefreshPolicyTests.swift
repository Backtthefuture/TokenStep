import Foundation
import XCTest
@testable import TokenStepSwift

final class UsageSnapshotRefreshPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_784_610_000)

    func testOlderAccountingRevisionRefreshesEvenWhenAutomaticRefreshIsDisabled() {
        let snapshot = makeSnapshot(
            accountingRevision: UsageCollector.codexAccountingRevision - 1,
            records: 1
        )

        XCTAssertEqual(
            UsageSnapshotRefreshPolicy.reason(
                snapshot: snapshot,
                refreshIntervalSeconds: 0,
                now: now
            ),
            .accountingRevision
        )
    }

    func testLegacySnapshotWithoutRevisionRefreshesImmediately() {
        let snapshot = makeSnapshot(accountingRevision: nil, records: 1)

        XCTAssertEqual(
            UsageSnapshotRefreshPolicy.reason(
                snapshot: snapshot,
                refreshIntervalSeconds: 300,
                now: now
            ),
            .accountingRevision
        )
    }

    func testCurrentFreshSnapshotDoesNotRefresh() {
        let snapshot = makeSnapshot(
            accountingRevision: UsageCollector.codexAccountingRevision,
            records: 1
        )

        XCTAssertNil(
            UsageSnapshotRefreshPolicy.reason(
                snapshot: snapshot,
                refreshIntervalSeconds: 300,
                now: now
            )
        )
    }

    func testEmptyLegacySnapshotDoesNotCreateARefreshLoop() {
        let snapshot = makeSnapshot(accountingRevision: nil, records: 0)

        XCTAssertNil(
            UsageSnapshotRefreshPolicy.reason(
                snapshot: snapshot,
                refreshIntervalSeconds: 0,
                now: now
            )
        )
    }

    func testSnapshotFromAnotherTimeZoneRecollects() {
        let otherZone = TokenStepClock.identifier == "Pacific/Chatham" ? "Pacific/Marquesas" : "Pacific/Chatham"
        let snapshot = makeSnapshot(
            accountingRevision: UsageCollector.codexAccountingRevision,
            records: 1,
            timezone: otherZone
        )

        XCTAssertEqual(
            UsageSnapshotRefreshPolicy.reason(
                snapshot: snapshot,
                refreshIntervalSeconds: 0,
                now: now
            ),
            .timeZoneChanged
        )
    }

    private func makeSnapshot(
        accountingRevision: Int?,
        records: Int,
        timezone: String = TokenStepClock.identifier
    ) -> UsageSnapshot {
        UsageSnapshot(
            generatedAt: ISO8601DateFormatter().string(from: now),
            timezone: timezone,
            totals: UsageTotals(tokens: 100, cost: 0, activeDays: 1),
            daily: [
                DailyUsage(
                    date: "2026-07-21",
                    tools: ["Codex": 100],
                    models: ["gpt-5.6-sol": 100],
                    totalTokens: 100,
                    cost: 0
                )
            ],
            tools: [],
            models: [],
            sources: [
                "Codex": SourceInfo(
                    status: "ok",
                    files: records > 0 ? 1 : 0,
                    records: records,
                    accountingRevision: accountingRevision
                )
            ]
        )
    }
}
