import XCTest
@testable import TokenStepSwift

final class TodaySourceRowsTests: XCTestCase {
    func testGroupsOverflowSources() {
        let rows = TodaySourceRows.make(
            tools: [
                "Codex": 62,
                "Claude Code": 21,
                "ZCode": 9,
                "Hermes Agent": 5,
                "WorkBuddy": 3
            ],
            maxNamed: 3
        )

        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0].name, "Codex")
        XCTAssertEqual(rows[1].name, "Claude Code")
        XCTAssertEqual(rows[2].name, "ZCode")
        XCTAssertEqual(rows[3].tokens, 8)
        XCTAssertTrue(rows[3].name.contains("2"))
    }

    func testEmptyToolsReturnsNoRows() {
        XCTAssertTrue(TodaySourceRows.make(tools: [:]).isEmpty)
    }
}
