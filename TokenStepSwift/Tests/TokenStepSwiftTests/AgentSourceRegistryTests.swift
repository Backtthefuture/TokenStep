import XCTest
@testable import TokenStepSwift

final class AgentSourceRegistryTests: XCTestCase {
    func testKnownToolsResolveWithoutHardcodedSwitch() {
        XCTAssertEqual(AgentSourceRegistry.descriptor(for: "Codex")?.id, "codex")
        XCTAssertEqual(AgentSourceRegistry.descriptor(for: "Claude Code")?.id, "claude")
        XCTAssertEqual(AgentSourceRegistry.descriptor(for: "zcode")?.displayName, "ZCode")
        XCTAssertEqual(AgentSourceRegistry.displayName(for: "hermes"), "Hermes Agent")
        XCTAssertEqual(AgentSourceRegistry.displayName(for: "workbuddy"), "WorkBuddy")
    }

    func testLedgerSourcesDoNotIncludeQuotaOrSignalTiers() {
        XCTAssertTrue(AgentSourceRegistry.ledgerSources.allSatisfy { $0.tier == .ledger })
        XCTAssertTrue(AgentSourceRegistry.quotaSources.contains(where: { $0.id == "cursor" }))
        XCTAssertTrue(AgentSourceRegistry.signalSources.contains(where: { $0.id == "cursor-code" }))
    }

    func testUniqueToolNamesFallbackUsesRegistry() {
        let names = uniqueToolNames(in: [])
        XCTAssertEqual(names, AgentSourceRegistry.defaultLegendNames)
    }
}
