import CryptoKit
import Darwin
import Foundation

// G-E0 / E0-T04：固定语料采集基准。
//
// 目标（PRD_TOKENSTEP_OPTIMIZATION.md §4.6）：
// - Codex：cold / 无变化 warm / append / 来源改写 / 截断尾行 / 损坏缓存，及 incremental 与 full rebuild 的等价性；
// - Claude：当前 full-scan 的 cold / 无变化 / append 基线（不虚构 incremental 对照）。
//
// 语料完全确定性（固定种子 LCG），可重复生成并校验 hash。
// 注意：Claude 走 collectClaudeCodeUsageSnapshotForTests，每次调用使用全新
// CollectorCache，因此测得的是 full-parse 口径；App 内持久 collector-cache 的
// mtime 命中路径不在本钩子覆盖范围内（记录于基准报告，不作为结论依据）。
@main
struct FixedCorpusBenchmark {
    static func main() {
        do {
            let arguments = CommandLine.arguments
            guard arguments.count >= 3 else {
                throw BenchmarkError.message(
                    "Usage: FixedCorpusBenchmark generate <corpusRoot>\n" +
                    "       FixedCorpusBenchmark codex <corpusRoot> <database> <cold|warm|append|rewrite|truncated|corrupt-cache|compare> [warmRuns]\n" +
                    "       FixedCorpusBenchmark claude <corpusRoot> <cold|warm|append> [warmRuns]"
                )
            }
            let command = arguments[1]
            let corpusRoot = URL(fileURLWithPath: arguments[2], isDirectory: true)
            switch command {
            case "generate":
                try generateCorpus(at: corpusRoot)
            case "codex":
                guard arguments.count >= 5 else { throw BenchmarkError.message("codex requires <database> <scenario>") }
                let database = URL(fileURLWithPath: arguments[3])
                let scenario = arguments[4]
                let warmRuns = arguments.count >= 6 ? Int(arguments[5]) ?? 5 : 5
                try runCodexScenario(corpusRoot: corpusRoot, database: database, scenario: scenario, warmRuns: warmRuns)
            case "claude":
                let scenario = arguments[3]
                let warmRuns = arguments.count >= 5 ? Int(arguments[4]) ?? 5 : 5
                try runClaudeScenario(corpusRoot: corpusRoot, scenario: scenario, warmRuns: warmRuns)
            default:
                throw BenchmarkError.message("unknown command \(command)")
            }
        } catch {
            fputs("Fixed corpus benchmark failed: \(error)\n", stderr)
            exit(1)
        }
    }

    // MARK: - 确定性语料

    private struct DeterministicRandom {
        var state: UInt64
        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }

        mutating func next(lessThan bound: Int) -> Int {
            Int(next() % UInt64(max(1, bound)))
        }
    }

    private struct UsageVector {
        var input: Int
        var output: Int
        var cached: Int
        var reasoning: Int

        var dictionary: [String: Any] {
            [
                "input_tokens": input,
                "output_tokens": output,
                "cached_input_tokens": cached,
                "reasoning_output_tokens": reasoning,
                "total_tokens": input + output
            ]
        }
    }

    private static let codexSessionCount = 150
    private static let claudeProjectCount = 40
    private static let claudeSessionsPerProject = 3

    private static func corpusHome(_ corpusRoot: URL) -> URL {
        corpusRoot.appendingPathComponent("home", isDirectory: true)
    }

    private static func generateCorpus(at corpusRoot: URL) throws {
        let home = corpusHome(corpusRoot)
        try FileManager.default.removeItemIfExists(at: home)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try generateCodexCorpus(home: home)
        try generateClaudeCorpus(home: home)

        let manifest = try corpusManifest(at: home)
        print("codex_files=\(manifest.codexFiles)")
        print("codex_bytes=\(manifest.codexBytes)")
        print("claude_files=\(manifest.claudeFiles)")
        print("claude_bytes=\(manifest.claudeBytes)")
        print("corpus_sha256=\(manifest.sha256)")
    }

    private static func generateCodexCorpus(home: URL) throws {
        // 150 个会话铺在 2026-05-15 … 2026-08-12 共 90 天。
        var rng = DeterministicRandom(seed: 0xC0DE_2026_08_13)
        let models = ["gpt-5", "gpt-5.5", "gpt-5.4-codex", "gpt-5.1"]
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy/MM/dd"
        dayFormatter.timeZone = TimeZone(identifier: "UTC")
        dayFormatter.calendar = Calendar(identifier: .gregorian)

        for index in 0..<codexSessionCount {
            let dayOffset = index % 90
            let day = Calendar(identifier: .gregorian)
                .date(byAdding: .day, value: dayOffset, to: isoDate("2026-05-15T00:00:00Z"))!
            let directory = home
                .appendingPathComponent(".codex/sessions/\(dayFormatter.string(from: day))", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let identifier = String(format: "%06d", index)
            let fileURL = directory.appendingPathComponent("rollout-2026-bench-\(identifier).jsonl")

            var lines: [String] = [
                sessionMeta(id: "bench-session-\(identifier)", timestamp: "2026-05-15T00:00:00Z"),
                turnContext(model: models[index % models.count], timestamp: "2026-05-15T00:00:01Z")
            ]
            // 累计计数器：单调递增，事件 30–70 条。
            let eventCount = 30 + rng.next(lessThan: 41)
            var cumulative = UsageVector(input: 0, output: 0, cached: 0, reasoning: 0)
            for event in 0..<eventCount {
                let delta = UsageVector(
                    input: 400 + rng.next(lessThan: 4_000),
                    output: 80 + rng.next(lessThan: 900),
                    cached: 200 + rng.next(lessThan: 2_000),
                    reasoning: 20 + rng.next(lessThan: 200)
                )
                cumulative = UsageVector(
                    input: cumulative.input + delta.input,
                    output: cumulative.output + delta.output,
                    cached: cumulative.cached + delta.cached,
                    reasoning: cumulative.reasoning + delta.reasoning
                )
                // 会话时间戳按天偏移，保持事件先后有序。
                let stamp = isoStamp(day: day, minute: event)
                lines.append(tokenCount(timestamp: stamp, cumulative: cumulative, last: delta))
            }
            try (lines.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private static func generateClaudeCorpus(home: URL) throws {
        var rng = DeterministicRandom(seed: 0xCA1A_2026_08_13)
        let models = ["claude-sonnet-4-5-20250929", "claude-opus-4-6", "claude-haiku-4-5"]

        for project in 0..<claudeProjectCount {
            let projectDirectory = home
                .appendingPathComponent(".claude/projects/-Users-bench-dev-project-\(project)", isDirectory: true)
            try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
            for session in 0..<claudeSessionsPerProject {
                let fileURL = projectDirectory
                    .appendingPathComponent("bench-session-\(project)-\(session).jsonl")
                var lines: [String] = []
                let lineCount = 50 + rng.next(lessThan: 30)
                for line in 0..<lineCount {
                    let dayOffset = (project + session + line) % 90
                    let day = Calendar(identifier: .gregorian)
                        .date(byAdding: .day, value: dayOffset, to: isoDate("2026-05-15T00:00:00Z"))!
                    var message: [String: Any] = [
                        "id": "msg-\(project)-\(session)-\(line)",
                        "model": models[(project + line) % models.count],
                        "usage": [
                            "input_tokens": 300 + rng.next(lessThan: 3_000),
                            "output_tokens": 60 + rng.next(lessThan: 700),
                            "cache_creation_input_tokens": 100 + rng.next(lessThan: 1_000),
                            "cache_read_input_tokens": 500 + rng.next(lessThan: 5_000)
                        ] as [String: Any]
                    ]
                    if line % 4 == 0 {
                        message["stop_reason"] = "tool_use"
                    }
                    var entry: [String: Any] = [
                        "uuid": "u-\(project)-\(session)-\(line)",
                        "sessionId": "bench-claude-\(project)-\(session)",
                        "type": "assistant",
                        "timestamp": isoStamp(day: day, minute: line),
                        "message": message
                    ]
                    if line % 3 == 0 {
                        entry["requestId"] = "req-\(project)-\(session)-\(line)"
                    }
                    lines.append(jsonLine(entry))
                    // 约 5% 追加同 message id 的重复行，覆盖去重路径。
                    if line % 19 == 0 {
                        lines.append(jsonLine(entry))
                    }
                }
                try (lines.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - Codex 场景

    private static func runCodexScenario(corpusRoot: URL, database: URL, scenario: String, warmRuns: Int) throws {
        let home = corpusHome(corpusRoot)
        try? FileManager.default.removeItem(at: database)
        let cold = try collectCodex(home: home, database: database, label: "cold")

        switch scenario {
        case "cold":
            break
        case "warm":
            var samples: [Int] = []
            for run in 0..<max(1, warmRuns) {
                let snapshot = try collectCodex(home: home, database: database, label: "warm[\(run)]")
                samples.append(snapshot.milliseconds)
            }
            printWarmSummary(samples: samples)
        case "append":
            let appended = try appendCodexEvents(home: home, sessionCount: 12)
            print("appended_files=\(appended.files) appended_events=\(appended.events)")
            _ = try collectCodex(home: home, database: database, label: "append")
            try compareAccounting(home: home, database: database)
        case "rewrite":
            let rewritten = try rewriteCodexSession(home: home)
            print("rewritten_file=\(rewritten)")
            _ = try collectCodex(home: home, database: database, label: "rewrite")
            try compareAccounting(home: home, database: database)
        case "truncated":
            let truncated = try truncateCodexTail(home: home)
            print("truncated_file=\(truncated)")
            _ = try collectCodex(home: home, database: database, label: "truncated")
            try compareAccounting(home: home, database: database)
        case "corrupt-cache":
            try corruptDatabase(database)
            _ = try collectCodex(home: home, database: database, label: "corrupt-cache")
            try compareAccounting(home: home, database: database)
        case "compare":
            try compareAccounting(home: home, database: database)
        default:
            throw BenchmarkError.message("unknown codex scenario \(scenario)")
        }
        print("cold_ms=\(cold.milliseconds)")
        print("scenario=\(scenario) status=ok")
    }

    private struct CollectOutcome {
        var milliseconds: Int
        var snapshot: UsageSnapshot
    }

    private static func collectCodex(home: URL, database: URL, label: String) throws -> CollectOutcome {
        let started = ContinuousClock.now
        let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home, cacheURL: database)
        let elapsed = started.duration(to: .now)
        let status = snapshot.sources["Codex"]?.status ?? "missing"
        print("phase=\(label) status=\(status) ms=\(milliseconds(elapsed)) tokens=\(snapshot.totals.tokens)")
        guard status == "ok" else {
            throw BenchmarkError.message("codex collection status \(status) in phase \(label)")
        }
        if let stats = UsageCollector.codexIncrementalCacheStatsForTests(databaseURL: database) {
            print(
                "cache_generation=\(stats.generation) cached_sessions=\(stats.sessions) "
                    + "cached_records=\(stats.records) last_logical_write_bytes=\(stats.lastLogicalWriteBytes)"
            )
        }
        return CollectOutcome(milliseconds: milliseconds(elapsed), snapshot: snapshot)
    }

    private static func compareAccounting(home: URL, database: URL) throws {
        let comparison = try UsageCollector.compareIncrementalCodexAccountingForTests(
            homeURL: home,
            databaseURL: database
        )
        let mismatches = try mismatchSections(comparison.incrementalSnapshot, comparison.referenceSnapshot)
        print("mismatch_sections=\(mismatches.joined(separator: ","))")
        print("mismatched_path_count=\(comparison.mismatchedPathHashes.count)")
        print(
            "record_count_delta=\(comparison.incrementalRecordCount - comparison.referenceRecordCount)"
        )
        guard mismatches.isEmpty, comparison.mismatchedPathHashes.isEmpty else {
            throw BenchmarkError.message("incremental accounting differs from full rebuild")
        }
        print("accounting_match=true")
    }

    // MARK: - Codex 语料变异

    private static func appendCodexEvents(home: URL, sessionCount: Int) throws -> (files: Int, events: Int) {
        let sessionsRoot = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        let files = try jsonlFilesUnder(sessionsRoot).sorted { $0.path < $1.path }
        guard !files.isEmpty else { throw BenchmarkError.message("codex corpus missing") }
        var rng = DeterministicRandom(seed: 0xA00D_2026_08_13)
        var totalEvents = 0
        for file in files.suffix(sessionCount) {
            let content = try String(contentsOf: file, encoding: .utf8)
            guard let lastLine = content.split(separator: "\n", omittingEmptySubsequences: true).last,
                  let data = lastLine.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let timestamp = object["timestamp"] as? String
            else { continue }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            var cumulative = cumulativeTotals(from: object)
            var lines: [String] = []
            for step in 1...5 {
                let delta = UsageVector(
                    input: 500 + rng.next(lessThan: 3_000),
                    output: 90 + rng.next(lessThan: 600),
                    cached: 300 + rng.next(lessThan: 1_500),
                    reasoning: 30 + rng.next(lessThan: 150)
                )
                cumulative = UsageVector(
                    input: cumulative.input + delta.input,
                    output: cumulative.output + delta.output,
                    cached: cumulative.cached + delta.cached,
                    reasoning: cumulative.reasoning + delta.reasoning
                )
                lines.append(tokenCount(timestamp: shifted(timestamp: timestamp, minutes: step), cumulative: cumulative, last: delta))
            }
            try handle.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
            try handle.synchronize()
            totalEvents += lines.count
        }
        return (min(sessionCount, files.count), totalEvents)
    }

    private static func rewriteCodexSession(home: URL) throws -> String {
        let sessionsRoot = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        let files = try jsonlFilesUnder(sessionsRoot).sorted { $0.path < $1.path }
        guard let target = files.first else { throw BenchmarkError.message("codex corpus missing") }
        // 用不同种子重建同一会话：事件数与时间戳都变化，模拟 rewritten timestamps。
        var rng = DeterministicRandom(seed: 0xEB00_2026_08_13)
        let identifier = target.deletingPathExtension().lastPathComponent
        var lines: [String] = [
            sessionMeta(id: "bench-session-\(identifier.suffix(6))", timestamp: "2026-05-15T00:00:00Z"),
            turnContext(model: "gpt-5.5", timestamp: "2026-05-15T00:00:01Z")
        ]
        var cumulative = UsageVector(input: 0, output: 0, cached: 0, reasoning: 0)
        let eventCount = 20 + rng.next(lessThan: 30)
        for event in 0..<eventCount {
            let delta = UsageVector(
                input: 350 + rng.next(lessThan: 2_500),
                output: 70 + rng.next(lessThan: 500),
                cached: 150 + rng.next(lessThan: 1_200),
                reasoning: 15 + rng.next(lessThan: 120)
            )
            cumulative = UsageVector(
                input: cumulative.input + delta.input,
                output: cumulative.output + delta.output,
                cached: cumulative.cached + delta.cached,
                reasoning: cumulative.reasoning + delta.reasoning
            )
            lines.append(tokenCount(timestamp: "2026-06-01T0\(event % 10):00:00Z", cumulative: cumulative, last: delta))
        }
        try (lines.joined(separator: "\n") + "\n").write(to: target, atomically: true, encoding: .utf8)
        return target.lastPathComponent
    }

    private static func truncateCodexTail(home: URL) throws -> String {
        let sessionsRoot = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        let files = try jsonlFilesUnder(sessionsRoot).sorted { $0.path < $1.path }
        guard let target = files.last else { throw BenchmarkError.message("codex corpus missing") }
        let data = try Data(contentsOf: target)
        // 砍掉末行尾部并去掉换行，模拟崩溃时的残缺尾行。
        let truncatedLength = max(1, data.count - 64)
        let truncated = data.prefix(truncatedLength)
        try Data(truncated.dropLast(1)).write(to: target)
        return target.lastPathComponent
    }

    private static func corruptDatabase(_ database: URL) throws {
        guard FileManager.default.fileExists(atPath: database.path) else {
            throw BenchmarkError.message("cache database missing before corruption")
        }
        let data = try Data(contentsOf: database)
        var corrupted = data
        let offset = data.count / 2
        let length = min(2_048, max(64, data.count - offset))
        for index in 0..<length {
            corrupted[offset + index] = UInt8(truncatingIfNeeded: index &* 37)
        }
        try corrupted.write(to: database)
        print("corrupted_bytes=\(length)")
    }

    // MARK: - Claude 场景

    private static func runClaudeScenario(corpusRoot: URL, scenario: String, warmRuns: Int) throws {
        let projects = corpusHome(corpusRoot).appendingPathComponent(".claude/projects", isDirectory: true)

        func scan(_ label: String) throws -> CollectOutcome {
            let started = ContinuousClock.now
            let snapshot = UsageCollector.collectClaudeCodeUsageSnapshot(rootURL: projects)
            let elapsed = started.duration(to: .now)
            let status = snapshot.sources["Claude Code"]?.status ?? "missing"
            print("phase=\(label) status=\(status) ms=\(milliseconds(elapsed)) tokens=\(snapshot.totals.tokens)")
            guard status == "ok" else {
                throw BenchmarkError.message("claude collection status \(status) in phase \(label)")
            }
            return CollectOutcome(milliseconds: milliseconds(elapsed), snapshot: snapshot)
        }

        let cold = try scan("cold")
        switch scenario {
        case "cold":
            break
        case "warm":
            var samples: [Int] = []
            for run in 0..<max(1, warmRuns) {
                samples.append(try scan("warm[\(run)]").milliseconds)
            }
            printWarmSummary(samples: samples)
        case "append":
            let appended = try appendClaudeLines(projects: projects, fileCount: 10)
            print("appended_files=\(appended.files) appended_lines=\(appended.lines)")
            let after = try scan("append")
            guard after.snapshot.totals.tokens > cold.snapshot.totals.tokens else {
                throw BenchmarkError.message("appended claude lines were not recorded")
            }
        default:
            throw BenchmarkError.message("unknown claude scenario \(scenario)")
        }
        print("cold_ms=\(cold.milliseconds)")
        print("scenario=\(scenario) status=ok")
    }

    private static func appendClaudeLines(projects: URL, fileCount: Int) throws -> (files: Int, lines: Int) {
        let files = try jsonlFilesUnder(projects).sorted { $0.path < $1.path }
        guard !files.isEmpty else { throw BenchmarkError.message("claude corpus missing") }
        var rng = DeterministicRandom(seed: 0xCA00_2026_08_13)
        var totalLines = 0
        for (index, file) in files.suffix(fileCount).enumerated() {
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            var lines: [String] = []
            for step in 0..<12 {
                let entry: [String: Any] = [
                    "uuid": "u-append-\(index)-\(step)",
                    "sessionId": "bench-claude-append-\(index)",
                    "type": "assistant",
                    "timestamp": "2026-08-12T2\(step % 4):\(String(format: "%02d", step)):00Z",
                    "message": [
                        "id": "msg-append-\(index)-\(step)",
                        "model": "claude-sonnet-4-5-20250929",
                        "usage": [
                            "input_tokens": 400 + rng.next(lessThan: 2_000),
                            "output_tokens": 80 + rng.next(lessThan: 400),
                            "cache_creation_input_tokens": 120 + rng.next(lessThan: 600),
                            "cache_read_input_tokens": 600 + rng.next(lessThan: 2_000)
                        ] as [String: Any]
                    ] as [String: Any]
                ]
                lines.append(jsonLine(entry))
            }
            try handle.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
            try handle.synchronize()
            totalLines += lines.count
        }
        return (min(fileCount, files.count), totalLines)
    }

    // MARK: - 共用工具

    private static func jsonlFilesUnder(_ root: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        guard let enumerator else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            files.append(url)
        }
        return files
    }

    private struct CorpusManifest {
        var codexFiles: Int
        var codexBytes: Int
        var claudeFiles: Int
        var claudeBytes: Int
        var sha256: String
    }

    private static func corpusManifest(at home: URL) throws -> CorpusManifest {
        let codexFiles = try jsonlFilesUnder(home.appendingPathComponent(".codex/sessions", isDirectory: true))
        let claudeFiles = try jsonlFilesUnder(home.appendingPathComponent(".claude/projects", isDirectory: true))
        var hasher = SHA256()
        var codexBytes = 0
        var claudeBytes = 0
        for file in codexFiles.sorted(by: { $0.path < $1.path }) {
            let data = try Data(contentsOf: file)
            codexBytes += data.count
            hasher.update(data: Data("C:\(file.lastPathComponent):\(data.count):".utf8))
            hasher.update(data: Data(SHA256.hash(data: data)))
        }
        for file in claudeFiles.sorted(by: { $0.path < $1.path }) {
            let data = try Data(contentsOf: file)
            claudeBytes += data.count
            hasher.update(data: Data("L:\(file.lastPathComponent):\(data.count):".utf8))
            hasher.update(data: Data(SHA256.hash(data: data)))
        }
        let digest = hasher.finalize()
        return CorpusManifest(
            codexFiles: codexFiles.count,
            codexBytes: codexBytes,
            claudeFiles: claudeFiles.count,
            claudeBytes: claudeBytes,
            sha256: digest.map { String(format: "%02x", $0) }.joined()
        )
    }

    private static func cumulativeTotals(from eventObject: [String: Any]) -> UsageVector {
        guard let payload = eventObject["payload"] as? [String: Any],
              let info = payload["info"] as? [String: Any],
              let totals = info["total_token_usage"] as? [String: Any]
        else { return UsageVector(input: 0, output: 0, cached: 0, reasoning: 0) }
        return UsageVector(
            input: totals["input_tokens"] as? Int ?? 0,
            output: totals["output_tokens"] as? Int ?? 0,
            cached: totals["cached_input_tokens"] as? Int ?? 0,
            reasoning: totals["reasoning_output_tokens"] as? Int ?? 0
        )
    }

    private static func shifted(timestamp: String, minutes: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let date = isoFormatter.date(from: timestamp) else { return timestamp }
        guard let shifted = calendar.date(byAdding: .minute, value: minutes, to: date) else { return timestamp }
        return isoFormatter.string(from: shifted)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func isoDate(_ string: String) -> Date {
        isoFormatter.date(from: string) ?? Date(timeIntervalSince1970: 0)
    }

    private static func isoStamp(day: Date, minute: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let stamped = calendar.date(byAdding: .minute, value: minute, to: day) ?? day
        return isoFormatter.string(from: stamped)
    }

    private static func sessionMeta(id: String, timestamp: String) -> String {
        jsonLine([
            "type": "session_meta",
            "timestamp": timestamp,
            "payload": ["id": id]
        ])
    }

    private static func turnContext(model: String, timestamp: String) -> String {
        jsonLine([
            "type": "turn_context",
            "timestamp": timestamp,
            "payload": ["model": model]
        ])
    }

    private static func tokenCount(timestamp: String, cumulative: UsageVector, last: UsageVector) -> String {
        jsonLine([
            "type": "event_msg",
            "timestamp": timestamp,
            "payload": [
                "type": "token_count",
                "info": [
                    "total_token_usage": cumulative.dictionary,
                    "last_token_usage": last.dictionary
                ]
            ]
        ])
    }

    private static func jsonLine(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        return Int(components.seconds * 1_000) + Int(components.attoseconds / 1_000_000_000_000_000)
    }

    private static func printWarmSummary(samples: [Int]) {
        let sorted = samples.sorted()
        guard !sorted.isEmpty else { return }
        let median = sorted[sorted.count / 2]
        let p95 = sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.up)) - 1)]
        print("warm_runs=\(samples.count)")
        print("warm_ms=\(samples.map(String.init).joined(separator: ","))")
        print("warm_median_ms=\(median)")
        print("warm_p95_ms=\(p95)")
    }

    private static func mismatchSections(_ lhs: UsageSnapshot, _ rhs: UsageSnapshot) throws -> [String] {
        var mismatches = [String]()
        if try canonical(lhs.totals) != canonical(rhs.totals) { mismatches.append("totals") }
        if try canonical(lhs.daily) != canonical(rhs.daily) { mismatches.append("daily") }
        if try canonical(lhs.rhythms) != canonical(rhs.rhythms) { mismatches.append("rhythms") }
        if try canonical(lhs.agentWork) != canonical(rhs.agentWork) { mismatches.append("agent_work") }
        if try canonical(lhs.tools) != canonical(rhs.tools) { mismatches.append("tools") }
        if try canonical(lhs.models) != canonical(rhs.models) { mismatches.append("models") }
        if try canonical(lhs.sources) != canonical(rhs.sources) { mismatches.append("sources") }
        return mismatches
    }

    private static func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}

private extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        if fileExists(atPath: url.path) {
            try removeItem(at: url)
        }
    }
}

private enum BenchmarkError: Error {
    case message(String)
}
