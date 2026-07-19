import XCTest
@testable import TokenStepSwift

final class MainWindowNavigationTests: XCTestCase {
    func testPopoverAgentDestinationOverridesExistingSectionWithToday() {
        let navigation = MainWindowNavigation(section: .history)

        navigation.select(PopoverAgentWorkStrip.destination)

        XCTAssertEqual(navigation.section, .today)
    }
}
