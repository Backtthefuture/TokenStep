import Darwin
import Foundation

// Checks that resuming Claude Code transcripts after the last complete line gives
// exactly the same accounting as re-reading the whole file.
@main
struct ClaudeIncrementalFixtureCheck {
    static func main() {
        do {
            try checkGrowthWithPartialLines()
            try checkStreamingDuplicateAcrossAppends()
            try checkShorterRewriteIsRescanned()
            try checkPrefixEditIsRescanned()
            try checkMiddleEditNeedsFullValidation()
            print("Claude incremental collector fixture checks passed")
        } catch {
            fputs("Claude incremental collector fixture failed: \(error)\n", stderr)
            exit(1)
        }
    }

    /// Appends a transcript in uneven chunks, many ending mid-line, and compares
    /// the cached collection with a full re-read after every append.
    private static func checkGrowthWithPartialLines() throws {
        try withFixture("growth") { fixture in
            var transcript = ""
            for index in 0..<120 {
                transcript += assistantLine(id: "msg_\(index)", minute: index, input: 100 + index, output: 10)
                transcript += userLine(minute: index)
            }
            let bytes = Array(transcript.utf8)
            var written = 0
            var chunk = 7
            while written < bytes.count {
                let end = min(bytes.count, written + chunk)
                try fixture.append(Data(bytes[written..<end]))
                written = end
                chunk = chunk * 3 % 997 + 11
                try fixture.expectCachedMatchesFull("growth at byte \(written)")
            }
            try expect(fixture.cachedSnapshot().totals.tokens == (0..<120).reduce(0) { $0 + 110 + $1 }, "growth total")
        }
    }

    /// Claude Code can write the same message twice: first without a stop reason,
    /// then complete. The later, complete copy must win even across appends.
    private static func checkStreamingDuplicateAcrossAppends() throws {
        try withFixture("streaming") { fixture in
            try fixture.append(assistantLine(id: "msg_s", minute: 1, input: 50, output: 5, stopReason: nil))
            try fixture.expectCachedMatchesFull("partial message")
            try expect(fixture.cachedSnapshot().totals.tokens == 55, "partial message counted once")
            try fixture.append(assistantLine(id: "msg_s", minute: 2, input: 50, output: 40))
            try fixture.expectCachedMatchesFull("completed message")
            try expect(fixture.cachedSnapshot().totals.tokens == 90, "completed copy replaces partial copy")
        }
    }

    private static func checkShorterRewriteIsRescanned() throws {
        try withFixture("shorter") { fixture in
            try fixture.append(assistantLine(id: "msg_a", minute: 1, input: 100, output: 10))
            try fixture.append(assistantLine(id: "msg_b", minute: 2, input: 200, output: 20))
            _ = try fixture.cachedSnapshot()
            try fixture.replace(assistantLine(id: "msg_c", minute: 3, input: 7, output: 3))
            try fixture.expectCachedMatchesFull("shorter rewrite")
            try expect(fixture.cachedSnapshot().totals.tokens == 10, "shorter rewrite drops old lines")
        }
    }

    private static func checkPrefixEditIsRescanned() throws {
        try withFixture("prefix") { fixture in
            let first = assistantLine(id: "msg_a", minute: 1, input: 100, output: 10)
            try fixture.append(first)
            try fixture.append(assistantLine(id: "msg_b", minute: 2, input: 200, output: 20))
            _ = try fixture.cachedSnapshot()
            // Same length, different count in the first line, plus an append.
            let edited = first.replacingOccurrences(of: "\"input_tokens\":100", with: "\"input_tokens\":900")
            let rest = try String(contentsOf: fixture.file, encoding: .utf8).dropFirst(first.utf8.count)
            try fixture.replace(edited + rest + assistantLine(id: "msg_c", minute: 3, input: 1, output: 1))
            try fixture.expectCachedMatchesFull("prefix edit")
            try expect(fixture.cachedSnapshot().totals.tokens == 910 + 220 + 2, "prefix edit is recounted")
        }
    }

    /// Edits outside the sampled head and tail are not visible to the append check;
    /// the periodic full validation pass is what repairs them.
    private static func checkMiddleEditNeedsFullValidation() throws {
        try withFixture("middle") { fixture in
            var lines: [String] = []
            for index in 0..<200 {
                lines.append(assistantLine(id: "msg_\(index)", minute: index, input: 100, output: 10))
            }
            try fixture.append(lines.joined())
            _ = try fixture.cachedSnapshot()
            lines[100] = lines[100].replacingOccurrences(of: "\"input_tokens\":100", with: "\"input_tokens\":500")
            try fixture.replace(lines.joined())
            let validated = try fixture.cachedSnapshot(forceFullValidation: true)
            try expect(validated.totals.tokens == 200 * 110 + 400, "full validation recounts a middle edit")
            try fixture.expectCachedMatchesFull("after full validation")
        }
    }

    // MARK: - Fixture helpers

    private static func assistantLine(
        id: String,
        minute: Int,
        input: Int,
        output: Int,
        stopReason: String? = "end_turn"
    ) -> String {
        var message: [String: Any] = [
            "id": id,
            "model": "claude-sonnet-4",
            "usage": ["input_tokens": input, "output_tokens": output]
        ]
        if let stopReason {
            message["stop_reason"] = stopReason
        }
        return jsonLine([
            "type": "assistant",
            "timestamp": String(format: "2026-07-13T%02d:%02d:00Z", 1 + minute / 60, minute % 60),
            "sessionId": "fixture",
            "message": message
        ])
    }

    /// A non-assistant line that mentions usage, so it passes the byte pre-filter.
    private static func userLine(minute: Int) -> String {
        jsonLine([
            "type": "user",
            "timestamp": String(format: "2026-07-13T%02d:%02d:30Z", 1 + minute / 60, minute % 60),
            "message": ["content": "please check token usage \(minute)"]
        ])
    }

    private static func jsonLine(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private static func withFixture(_ label: String, body: (Fixture) throws -> Void) throws {
        let dir = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("TokenStepClaude-\(label)-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixture = try Fixture(dir: dir)
        do {
            try body(fixture)
        } catch {
            throw FixtureError("[\(label)] \(error)")
        }
    }

    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw FixtureError(message) }
    }
}

private struct Fixture {
    let root: URL
    let file: URL
    let cache: URL

    init(dir: URL) throws {
        root = dir.appendingPathComponent("projects", isDirectory: true)
        let project = root.appendingPathComponent("p", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        file = project.appendingPathComponent("session.jsonl")
        cache = dir.appendingPathComponent("collector-cache.json")
        FileManager.default.createFile(atPath: file.path, contents: nil)
    }

    func append(_ text: String) throws {
        try append(Data(text.utf8))
    }

    func append(_ data: Data) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try bumpModificationTime()
    }

    func replace(_ text: String) throws {
        try Data(text.utf8).write(to: file)
        try bumpModificationTime()
    }

    /// Guarantees a distinct mtime so the unchanged-file shortcut never masks an edit.
    private func bumpModificationTime() throws {
        let stamp = Date().addingTimeInterval(Double.random(in: 1...1_000_000))
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: file.path)
    }

    func cachedSnapshot(forceFullValidation: Bool = false) throws -> UsageSnapshot {
        UsageCollector.collectClaudeCodeWithCacheForTests(
            rootURL: root,
            cacheURL: cache,
            forceFullValidation: forceFullValidation
        )
    }

    func expectCachedMatchesFull(_ context: String) throws {
        let cached = try signature(cachedSnapshot())
        let full = try signature(UsageCollector.collectClaudeCodeUsageSnapshot(rootURL: root))
        if cached != full {
            let dump = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tokenstep-claude-mismatch")
            try? FileManager.default.createDirectory(at: dump, withIntermediateDirectories: true)
            try? cached.write(to: dump.appendingPathComponent("cached.json"))
            try? full.write(to: dump.appendingPathComponent("full.json"))
            throw FixtureError("\(context): cached collection differs from full re-read (see \(dump.path))")
        }
    }

    private func signature(_ snapshot: UsageSnapshot) throws -> Data {
        var snapshot = snapshot
        snapshot.generatedAt = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }
}

private struct FixtureError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
