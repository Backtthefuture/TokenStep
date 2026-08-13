import Foundation

// G-A1：T1 实验源校验（合成样本 + 可选真机只读验证）。
// 真机验证：TOKENSTEP_AGENT_SOURCES_REAL=1 时对真实 $HOME 只读采集并打印计数。
@main
struct AgentSourcesFixtureCheck {
    static func main() {
        do {
            try checkEnabledIDPolicy()
            try checkGemini()
            try checkQwen()
            try checkKimi()
            try checkGrok()
            try checkGeneric()
            try checkOpenCodeFallback()
            if ProcessInfo.processInfo.environment["TOKENSTEP_AGENT_SOURCES_REAL"] == "1" {
                reportRealMachine()
            }
            print("Agent sources fixture checks passed")
        } catch {
            fputs("Agent sources fixture failed: \(error)\n", stderr)
            exit(1)
        }
    }

    // 开关语义（2026-08-13 用户裁决）：主开关开 + 未做逐源选择 → 已安装的源自动纳入。
    private static func checkEnabledIDPolicy() throws {
        let emptyHome = try freshDirectory("policy-empty")
        try expectEqual(
            AgentSourceRegistry.enabledIDs(masterEnabled: false, perSource: nil, homeURL: emptyHome),
            [],
            "master off → empty"
        )
        try expectEqual(
            AgentSourceRegistry.enabledIDs(masterEnabled: true, perSource: nil, homeURL: emptyHome),
            [],
            "master on + nothing installed → empty"
        )
        // 自动纳入：装有 Gemini 数据目录即自动启用 Gemini CLI。
        let geminiHome = try freshDirectory("policy-gemini")
        try FileManager.default.createDirectory(
            at: geminiHome.appendingPathComponent(".gemini/tmp/x/chats", isDirectory: true),
            withIntermediateDirectories: true
        )
        try expectEqual(
            AgentSourceRegistry.enabledIDs(masterEnabled: true, perSource: nil, homeURL: geminiHome),
            ["Gemini CLI"],
            "detected agent auto-enrolls"
        )
        // 显式列表优先于自动纳入（用户可关掉自动源）。
        try expectEqual(
            AgentSourceRegistry.enabledIDs(
                masterEnabled: true,
                perSource: ["Grok Build", "NotARealSource"],
                homeURL: geminiHome
            ),
            ["Grok Build"],
            "explicit list filters unknown ids and overrides auto"
        )
        try expectEqual(
            AgentSourceRegistry.enabledIDs(masterEnabled: false, perSource: ["Gemini CLI"], homeURL: geminiHome),
            [],
            "per-source cannot bypass master switch"
        )
    }

    // Gemini：本机真实 schema（session-*.json，tokens 分量）。
    private static func checkGemini() throws {
        let home = try freshDirectory("gemini")
        let chats = home.appendingPathComponent(".gemini/tmp/hash1/chats", isDirectory: true)
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        let session: [String: Any] = [
            "sessionId": "s1",
            "startTime": "2026-08-13T01:00:00Z",
            "messages": [
                ["type": "user", "content": "hi", "timestamp": "2026-08-13T01:00:01Z"],
                [
                    "type": "gemini",
                    "id": "m1",
                    "model": "gemini-2.5-pro",
                    "timestamp": "2026-08-13T01:01:00Z",
                    "tokens": ["input": 8095, "output": 9, "cached": 100, "thoughts": 33, "tool": 0, "total": 8137]
                ]
            ] as [Any]
        ]
        let data = try JSONSerialization.data(withJSONObject: session, options: [.sortedKeys])
        try data.write(to: chats.appendingPathComponent("session-2026-08-13-x.json"))
        let result = GeminiCLISource.collect(homeURL: home)
        try expectEqual(result.source.status, "ok", "gemini status")
        try expectEqual(result.records.count, 1, "gemini record count")
        try expectEqual(result.records[0].model, "gemini-2.5-pro", "gemini model")
        try expectEqual(result.records[0].usage.totalTokens, 8137, "gemini explicit total")
        try expectEqual(result.records[0].usage.cacheReadInputTokens, 100, "gemini cached")
    }

    // Qwen：usageMetadata（Gemini 分叉 schema，公开情报）。
    private static func checkQwen() throws {
        let home = try freshDirectory("qwen")
        let dir = home.appendingPathComponent(".qwen/tmp/p1", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let line: [String: Any] = [
            "timestamp": 1_800_000_000.0,
            "usageMetadata": [
                "promptTokenCount": 1000,
                "candidatesTokenCount": 100,
                "cachedContentTokenCount": 400,
                "thoughtsTokenCount": 50
            ] as [String: Any]
        ]
        let data = try JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
        try (String(data: data, encoding: .utf8)! + "\n")
            .write(to: dir.appendingPathComponent("session-1.jsonl"), atomically: true, encoding: .utf8)
        let result = QwenCodeSource.collect(homeURL: home)
        try expectEqual(result.source.status, "ok", "qwen status")
        try expectEqual(result.records[0].usage.totalTokens, 1100, "qwen total")
        try expectEqual(result.records[0].usage.cacheReadInputTokens, 400, "qwen cached subset")
    }

    // Kimi：新版 wire usage.record（公开情报）；旧版无 usage 事件 → missing_valid_rows。
    private static func checkKimi() throws {
        let home = try freshDirectory("kimi")
        let wireDir = home.appendingPathComponent(".kimi-code/sessions/wd_a/session_x/agents/main", isDirectory: true)
        try FileManager.default.createDirectory(at: wireDir, withIntermediateDirectories: true)
        let lines = [
            "{\"type\": \"metadata\", \"protocol_version\": \"1.1\"}",
            "{\"timestamp\": 1800000000.5, \"message\": {\"type\": \"UsageRecord\", \"payload\": {\"model\": \"kimi-k2\", \"cwd\": \"/u/p/kimi-app\", \"usage\": {\"input_tokens\": 500, \"output_tokens\": 50, \"cache_read_tokens\": 200}}}}"
        ]
        try lines.joined(separator: "\n").appending("\n")
            .write(to: wireDir.appendingPathComponent("wire.jsonl"), atomically: true, encoding: .utf8)
        let result = KimiCodeSource.collect(homeURL: home)
        try expectEqual(result.source.status, "ok", "kimi status")
        try expectEqual(result.records[0].usage.totalTokens, 750, "kimi total input(+cache)+output")
        try expectEqual(result.records[0].projectName, "kimi-app", "kimi project from cwd")

        // 旧版 .kimi：无 usage 事件，如实无数据。
        let legacyHome = try freshDirectory("kimi-legacy")
        let legacyDir = legacyHome.appendingPathComponent(".kimi/sessions/x/y", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        try "{\"timestamp\":1,\"message\":{\"type\":\"TurnBegin\",\"payload\":{}}}\n"
            .write(to: legacyDir.appendingPathComponent("wire.jsonl"), atomically: true, encoding: .utf8)
        let legacy = KimiCodeSource.collect(homeURL: legacyHome)
        try expectEqual(legacy.source.status, "missing", "legacy .kimi not scanned (no usage events)")
    }

    // Grok：本机真实 schema（updates.jsonl + URL 编码项目目录）。
    private static func checkGrok() throws {
        let home = try freshDirectory("grok")
        let encoded = "%2FUsers%2Fbench%2Fdev%2Fgrok-app"
        let dir = home.appendingPathComponent(".grok/sessions/\(encoded)/019f9153-aaaa", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let line: [String: Any] = [
            "timestamp": 1_800_000_000,
            "method": "_x.ai/session/update",
            "params": [
                "sessionId": "019f9153-aaaa",
                "update": [
                    "sessionUpdate": "turn_completed",
                    "prompt_id": "p1",
                    "usage": [
                        "inputTokens": 958_154,
                        "outputTokens": 15_174,
                        "totalTokens": 973_328,
                        "cachedReadTokens": 855_296,
                        "reasoningTokens": 8_868,
                        "modelUsage": ["grok-4.5-build": ["inputTokens": 1]] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        ]
        let data = try JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
        try (String(data: data, encoding: .utf8)! + "\n")
            .write(to: dir.appendingPathComponent("updates.jsonl"), atomically: true, encoding: .utf8)
        let result = GrokBuildSource.collect(homeURL: home)
        try expectEqual(result.source.status, "ok", "grok status")
        try expectEqual(result.records[0].usage.totalTokens, 973_328, "grok explicit total")
        try expectEqual(result.records[0].model, "grok-4.5-build", "grok model from modelUsage")
        try expectEqual(result.records[0].projectName, "grok-app", "grok project from encoded dir")
        // 重复 prompt_id 去重。
        try (String(data: data, encoding: .utf8)! + "\n")
            .write(to: dir.appendingPathComponent("updates.jsonl"), atomically: true, encoding: .utf8)
        let deduped = GrokBuildSource.collect(homeURL: home)
        try expectEqual(deduped.records.count, 1, "grok dedup by prompt_id")
    }

    // Amp / Droid：通用 usage 行提取。
    private static func checkGeneric() throws {
        let home = try freshDirectory("amp")
        let dir = home.appendingPathComponent(".local/share/amp/threads/t1", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{\"timestamp\":1800000000,\"cwd\":\"/u/p/amp-app\",\"model\":\"amp-1\",\"usage\":{\"input_tokens\":100,\"output_tokens\":10,\"cached_input_tokens\":30}}\n"
            .write(to: dir.appendingPathComponent("events.jsonl"), atomically: true, encoding: .utf8)
        let result = AgentSourceRegistry.collect(enabledIDs: ["Amp"], homeURL: home)["Amp"]
        try expectEqual(result?.source.status, "ok", "amp status")
        try expectEqual(result?.records.first?.usage.totalTokens, 140, "amp total")
        try expectEqual(result?.records.first?.projectName, "amp-app", "amp project")

        let missing = AgentSourceRegistry.collect(enabledIDs: ["Droid"], homeURL: home)["Droid"]
        try expectEqual(missing?.source.status, "missing", "droid missing without factory dir")
    }

    // OpenCode：无 DB → missing_db；真实 DB 走真机验证路径。
    private static func checkOpenCodeFallback() throws {
        let home = try freshDirectory("opencode")
        let result = OpenCodeSource.collect(homeURL: home)
        try expectEqual(result.source.status, "missing_db", "opencode missing db")
    }

    // 真机只读验证（打印计数供 G-A1 证据）。
    private static func reportRealMachine() {
        let observations = AgentSourceRegistry.observeAll()
        for observation in observations {
            print("real \(observation.sourceID)=\(observation.status)")
        }
        let results = AgentSourceRegistry.collect(enabledIDs: AgentSourceRegistry.allSourceIDs)
        for (name, result) in results.sorted(by: { $0.key < $1.key }) {
            let tokens = result.records.reduce(0) { $0 + $1.usage.totalTokens }
            print("real-collect \(name) status=\(result.source.status) records=\(result.records.count) tokens=\(tokens)")
        }
    }

    private static func freshDirectory(_ label: String) throws -> URL {
        let url = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("TokenStepAgentSources-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
    guard actual == expected else {
        throw FixtureFailure("\(label): expected \(expected), got \(actual)")
    }
}

private struct FixtureFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
