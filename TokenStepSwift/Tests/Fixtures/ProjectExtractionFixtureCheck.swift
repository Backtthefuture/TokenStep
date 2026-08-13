import Foundation

// G-B1：项目维度提取与脱敏校验（本地可执行）。
@main
struct ProjectExtractionFixtureCheck {
    static func main() {
        do {
            try checkDisplayName()
            try checkClaudeExtraction()
            try checkCodexExtractionAndInheritance()
            try checkLegacyDecode()
            print("Project extraction fixture checks passed")
        } catch {
            fputs("Project extraction fixture failed: \(error)\n", stderr)
            exit(1)
        }
    }

    // 1. 末级目录名提取与脱敏规则。
    private static func checkDisplayName() throws {
        try expectEqual(
            UsageCollector.projectDisplayName(fromPath: "/Users/x/dev/token-usage-monitor"),
            "token-usage-monitor",
            "last path component"
        )
        try expectEqual(
            UsageCollector.projectDisplayName(fromPath: "/Users/superhuang/Documents/黄叔知识库/项目A"),
            "项目A",
            "CJK last component preserved"
        )
        try expectEqual(
            UsageCollector.projectDisplayName(fromPath: "/Users/x/dev/"),
            "dev",
            "trailing slash still yields the directory name"
        )
        try expectNil(
            UsageCollector.projectDisplayName(fromPath: "/Users/x/dev/-----"),
            "dash-only segment is rejected"
        )
        try expectNil(UsageCollector.projectDisplayName(fromPath: nil), "nil path")
    }

    // 2. Claude：行内 cwd → 项目（端到端）。
    private static func checkClaudeExtraction() throws {
        let home = try freshDirectory("claude-project")
        let projectsRoot = home.appendingPathComponent(".claude/projects/my-app", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        let line: [String: Any] = [
            "uuid": "u1",
            "sessionId": "s1",
            "type": "assistant",
            "cwd": "/Users/bench/dev/my-app",
            "timestamp": "2026-08-13T10:00:00Z",
            "message": [
                "id": "msg-1",
                "model": "claude-sonnet-4-5-20250929",
                "usage": [
                    "input_tokens": 1000,
                    "output_tokens": 200,
                    "cache_creation_input_tokens": 100,
                    "cache_read_input_tokens": 300
                ] as [String: Any]
            ] as [String: Any]
        ]
        let data = try JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
        try (String(data: data, encoding: .utf8)! + "\n")
            .write(to: projectsRoot.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

        let snapshot = UsageCollector.collectClaudeCodeUsageSnapshot(
            rootURL: home.appendingPathComponent(".claude/projects", isDirectory: true)
        )
        let projects = snapshot.daily.first { $0.date == "2026-08-13" }?.projects ?? []
        try expectEqual(projects.first?.name, "my-app", "claude cwd becomes project name")
        try expectEqual(projects.first?.tools["Claude Code"], 1600, "project tool tokens (input+cache+output)")
    }

    // 3. Codex：session_meta.cwd → 项目；tail 追加继承项目名。
    private static func checkCodexExtractionAndInheritance() throws {
        let home = try freshDirectory("codex-project")
        let database = home.appendingPathComponent("cache.sqlite3")
        let sessionDir = home.appendingPathComponent(".codex/sessions/2026/08/13", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let fileURL = sessionDir.appendingPathComponent("rollout-bench.jsonl")

        func metaLine() -> String {
            jsonLine([
                "type": "session_meta",
                "timestamp": "2026-08-13T08:00:00Z",
                "payload": ["id": "bench-1", "cwd": "/Users/bench/work/黄叔知识库/官网重构"]
            ])
        }
        func tokenLine(_ stamp: String, cumulative: Int) -> String {
            jsonLine([
                "type": "event_msg",
                "timestamp": stamp,
                "payload": [
                    "type": "token_count",
                    "info": [
                        "total_token_usage": [
                            "input_tokens": cumulative - 10,
                            "output_tokens": 10,
                            "cached_input_tokens": 5,
                            "reasoning_output_tokens": 1,
                            "total_tokens": cumulative
                        ] as [String: Any],
                        "last_token_usage": [
                            "input_tokens": 90,
                            "output_tokens": 10,
                            "cached_input_tokens": 5,
                            "reasoning_output_tokens": 1,
                            "total_tokens": 100
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ])
        }

        try ([metaLine(), tokenLine("2026-08-13T08:01:00Z", cumulative: 100)] as [String])
            .joined(separator: "\n")
            .appending("\n")
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let first = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home, cacheURL: database)
        let dayProjects = first.daily.first { $0.date == "2026-08-13" }?.projects ?? []
        try expectEqual(dayProjects.first?.name, "官网重构", "codex session_meta cwd becomes project")
        try expectEqual(first.projects.first?.name, "官网重构", "snapshot-level project present")

        // tail 追加：新事件无 session_meta，应继承既有项目名。
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((tokenLine("2026-08-13T08:02:00Z", cumulative: 220) + "\n").utf8))
        try handle.synchronize()

        let second = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home, cacheURL: database)
        try expectEqual(second.totals.tokens, 220, "append adds tokens")
        let appendedProjects = second.daily.first { $0.date == "2026-08-13" }?.projects ?? []
        try expectEqual(
            appendedProjects.map(\.name),
            ["官网重构"],
            "tail append inherits project name (single bucket)"
        )
        try expectEqual(appendedProjects.first?.tokens, 220, "project bucket carries all tokens")
    }

    // 4. 旧快照兼容：无 projects 字段按默认解码。
    private static func checkLegacyDecode() throws {
        let legacyDaily = """
        {"date":"2026-08-13","tools":{},"models":{},"total_tokens":5,"cost":0.1}
        """
        let daily = try JSONDecoder().decode(DailyUsage.self, from: Data(legacyDaily.utf8))
        try expectNil(daily.projects, "legacy daily has no projects")

        let legacySnapshot = """
        {"generated_at":"2026-08-13","timezone":"Asia/Shanghai",
         "totals":{"tokens":5,"cost":0.1,"active_days":1},
         "daily":[],"rhythms":[],"agent_work":[],"tools":[],"models":[],"sources":{}}
        """
        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: Data(legacySnapshot.utf8))
        try expectEqual(snapshot.projects, [], "legacy snapshot projects default empty")
    }

    // MARK: - 工具

    private static func freshDirectory(_ label: String) throws -> URL {
        let url = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("TokenStepProject-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func jsonLine(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
    guard actual == expected else {
        throw FixtureFailure("\(label): expected \(expected), got \(actual)")
    }
}

private func expectNil(_ value: Any?, _ label: String) throws {
    guard value == nil else { throw FixtureFailure("\(label): expected nil") }
}

private struct FixtureFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
