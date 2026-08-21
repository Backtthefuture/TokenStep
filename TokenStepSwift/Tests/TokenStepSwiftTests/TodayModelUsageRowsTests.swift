import Foundation
import XCTest
@testable import TokenStepSwift

final class TodayModelUsageRowsTests: XCTestCase {
    func testRowsSortAndUseDailyTotalForPercent() {
        let usage = makeUsage(
            models: ["small": 100, "large": 600, "medium": 300],
            modelCosts: ["large": 4.5, "medium": 1.25],
            totalTokens: 1_200
        )
        let rows = TodayModelUsageRows.make(from: usage)
        XCTAssertEqual(rows.map(\.model), ["large", "medium", "small"])
        let expected = [50.0, 25.0, 100.0 / 12.0]
        for (row, value) in zip(rows, expected) {
            XCTAssertEqual(row.percent, value, accuracy: 0.0001)
        }
        XCTAssertEqual(rows[0].estimatedCost, 4.5)
        XCTAssertNil(rows[2].estimatedCost)
    }

    func testEmptyAndWaitingDetailsProduceNoRows() {
        XCTAssertTrue(TodayModelUsageRows.make(from: makeUsage(models: ["gpt": 10], totalTokens: 0)).isEmpty)
        XCTAssertTrue(TodayModelUsageRows.make(from: makeUsage(models: [:], totalTokens: 100)).isEmpty)
    }

    func testUnknownLongNamesOverflowAndNegligibleRows() {
        let long = "vendor/very-long-model-name-with-version-2026-08-21"
        let models = [long: 9_994, "unknown": 1, "third": 1, "fourth": 1, "fifth": 1, "sixth": 1, "seventh": 1]
        let rows = TodayModelUsageRows.make(from: makeUsage(models: models, totalTokens: 10_000))
        XCTAssertEqual(rows.map(\.model), [long, "fifth"])
        XCTAssertEqual(rows.first?.model, long)
        XCTAssertTrue(rows.contains { $0.model == "fifth" })
    }

    func testMismatchIsRecordedAndPercentClamped() {
        let usage = makeUsage(models: ["unexpected": 150], totalTokens: 100)
        let rows = TodayModelUsageRows.make(from: usage)
        XCTAssertEqual(rows.first?.percent, 100)
        XCTAssertTrue(TodayModelUsageRows.hasTokenTotalMismatch(usage))
        XCTAssertFalse(TodayModelUsageRows.hasTokenTotalMismatch(makeUsage(models: ["a": 60, "b": 40], totalTokens: 100)))
    }

    func testColorSlotIsDeterministicAndBounded() {
        let first = TodayModelUsageRows.colorSlot(for: "gpt-5.2-codex")
        XCTAssertEqual(first, TodayModelUsageRows.colorSlot(for: "GPT-5.2-CODEX"))
        XCTAssertTrue((0..<TodayModelUsageRows.colorSlotCount).contains(first))
    }

    func testLegacyDailyUsageWithoutModelCostsDecodes() throws {
        let data = Data(#"{"date":"2026-08-21","tools":{"Codex":100},"models":{"gpt":100},"total_tokens":100,"cost":1.25}"#.utf8)
        let usage = try JSONDecoder().decode(DailyUsage.self, from: data)
        XCTAssertEqual(usage.models, ["gpt": 100])
        XCTAssertTrue(usage.modelCosts.isEmpty)
    }

    private func makeUsage(
        models: [String: Int],
        modelCosts: [String: Double] = [:],
        totalTokens: Int
    ) -> DailyUsage {
        DailyUsage(
            date: "2026-08-21",
            tools: ["Codex": totalTokens],
            models: models,
            modelCosts: modelCosts,
            totalTokens: totalTokens,
            cost: modelCosts.values.reduce(0, +)
        )
    }
}
