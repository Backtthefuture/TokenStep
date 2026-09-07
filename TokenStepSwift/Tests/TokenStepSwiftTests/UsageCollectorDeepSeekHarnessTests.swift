import Foundation
import XCTest
@testable import TokenStepSwift

final class UsageCollectorDeepSeekHarnessTests: XCTestCase {
    func testHarnessUsageUsesFinalMessageOverChunkAndDeduplicatesCopiedSessions() throws {
        let desktopRoot = try makeRoot(prefix: "TokenStepHarnessDesktop")
        let cliRoot = try makeRoot(prefix: "TokenStepHarnessCLI")
        let desktopFile = desktopRoot
            .appendingPathComponent("sessions/workspace/session-shared/session.jsonl.zstd")
        let cliFile = cliRoot
            .appendingPathComponent("sessions/workspace/session-shared/session.jsonl.zstd")
        let compressed = try XCTUnwrap(Data(base64Encoded: fixtureBase64))
        try FileManager.default.createDirectory(at: desktopFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cliFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try compressed.write(to: desktopFile)
        try compressed.write(to: cliFile)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: desktopRoot)
            try? FileManager.default.removeItem(at: cliRoot)
        }

        let snapshot = UsageCollector.collectUsageSnapshotForTests(
            deepSeekHarnessRootURLs: [desktopRoot, cliRoot],
            includeExperimentalAgentSources: true
        )

        XCTAssertEqual(snapshot.sources["DeepSeek Harness"]?.status, "ok")
        XCTAssertEqual(snapshot.sources["DeepSeek Harness"]?.records, 2)
        XCTAssertEqual(snapshot.totals.tokens, 32)
        XCTAssertEqual(snapshot.daily.reduce(0) { $0 + ($1.tools["DeepSeek Harness"] ?? 0) }, 32)
        let harnessModels = snapshot.models.filter { $0.tool == "DeepSeek Harness" }
        var harnessModelTokens = 0
        for model in harnessModels {
            harnessModelTokens += model.tokens
        }
        XCTAssertEqual(harnessModelTokens, 32)
    }

    func testHarnessCollectorReadsConcatenatedFramesAndChunkUsageEnvelope() throws {
        let root = try makeRoot(prefix: "TokenStepHarnessMultiFrame")
        let file = root.appendingPathComponent("sessions/workspace/session-multi/session.jsonl.zstd")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(Data(base64Encoded: multiFrameFixtureBase64)).write(to: file)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let snapshot = UsageCollector.collectUsageSnapshotForTests(
            deepSeekHarnessRootURLs: [root],
            includeExperimentalAgentSources: true
        )

        XCTAssertEqual(snapshot.sources["DeepSeek Harness"]?.status, "ok")
        XCTAssertEqual(snapshot.sources["DeepSeek Harness"]?.records, 2)
        XCTAssertEqual(snapshot.totals.tokens, 16)
    }

    func testHarnessCollectorRejectsMalformedJsonSource() throws {
        let root = try makeRoot(prefix: "TokenStepHarnessMalformed")
        let file = root.appendingPathComponent("sessions/workspace/session-bad/session.jsonl.zstd")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(Data(base64Encoded: malformedFixtureBase64)).write(to: file)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let snapshot = UsageCollector.collectUsageSnapshotForTests(
            deepSeekHarnessRootURLs: [root],
            includeExperimentalAgentSources: true
        )

        XCTAssertEqual(snapshot.sources["DeepSeek Harness"]?.status, "unreadable_source")
        XCTAssertEqual(snapshot.sources["DeepSeek Harness"]?.records, 0)
        XCTAssertEqual(snapshot.totals.tokens, 0)
    }

    func testCollectionStateTracksHarnessSessionFiles() throws {
        let root = try makeRoot(prefix: "TokenStepHarnessState")
        let file = root.appendingPathComponent("sessions/workspace/session-state/session.jsonl.zstd")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(Data(base64Encoded: fixtureBase64)).write(to: file)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let state = UsageCollector.collectionState(
            historyDays: 180,
            includeExperimentalAgentSources: true,
            deepSeekHarnessRootURLs: [root],
            homeURL: FileManager.default.temporaryDirectory
        )

        XCTAssertTrue(state.files.contains { $0.path == file.path })
    }

    func testHarnessCollectorReportsIncompleteCompressedTail() throws {
        let root = try makeRoot(prefix: "TokenStepHarnessPartial")
        let file = root.appendingPathComponent("sessions/workspace/session-partial/session.jsonl.zstd")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var compressed = try XCTUnwrap(Data(base64Encoded: multiFrameFixtureBase64))
        compressed.removeLast(5)
        try compressed.write(to: file)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let snapshot = UsageCollector.collectUsageSnapshotForTests(
            deepSeekHarnessRootURLs: [root],
            includeExperimentalAgentSources: true
        )

        XCTAssertEqual(snapshot.sources["DeepSeek Harness"]?.status, "partial_tail")
        XCTAssertGreaterThan(snapshot.sources["DeepSeek Harness"]?.records ?? 0, 0)
    }

    private func makeRoot(prefix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private var fixtureBase64: String {
        "KLUv/QRYTQgAUo8tIGBnqwNmdTRBtiZcdXRZ0gI/AoASCQt9JYISjRyCJ4EThBjj1z7XEqywWE4pKNa7dFvw8922m1MJOSDeMjyOlChKQg6IhAQkFCPaZo8gLV2BXZSqH4CG7udAeW5b4AYaMo29yRPj1cgb7HKKn6uRf7vYgXuMetDxm+RV/HwTypDZ5h+Ubw/2m7y2rp8jJShB+VWw/nlBg4sydNNmxqyEeGPt04WfX+znb5fuYmiOMS8/v8yi3wQkIMACKar1FOFvQK+Q46ZZE6kWuSFzFoBef2N9AuqbZhMZcm02Ct4Lba7OGS2+YM4/EIjeM0sjdIERTDIcBzXVe7zSfIcLuUSTZjdVhkGmnzkhNSY="
    }

    private var multiFrameFixtureBase64: String {
        "KLUv/QRYlQQAQooeHIA3zRitKxKxsrTJfMeQeBVSpsFHbl0g5iRFKgSE1lozLEtfAK4oEWlgmULmA699xo0s6Xyr8ZXFHKSlPvBcsgIJYqhc31lAlKHK1a/A0WL7gZMl5QMwHIpDgecx+41AzICgsIisGlVCaJs12Bkv5hslo5o6niqxHwEHAGiaJlYzUKGwVmOz3CYuO4xCPQFDEZRXKLUv/QRYlQQA8skeHlCHxA1EcUjwrRmKMcpfgAbGjBWFVyB9CvIxZhbRa4P33vZhjWJ0FxuQaHI0dFNHRJ7TCihGt5XOXbbje0fPD6xR6Pj1PFtzCBRbd/lNWFN8l8eSX9t8PPKJtb7La6s5Fg4JxYEUpOQXnT5+AZR5EaGTNh9mfX5XQd8FBwA4i97MDClC0ZgYi6+GK8oMgB6n3DDF"
    }

    private var malformedFixtureBase64: String {
        "KLUv/QRYSQEAeyJ0eXBlIjoic2Vzc2lvbiIsImlkIjoiYmFkIn0Ke25vdC1qc29ufQoQLJMP"
    }
}
