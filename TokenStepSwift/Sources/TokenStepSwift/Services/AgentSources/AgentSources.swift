import Foundation

// G-A1：T1 实验数据源（默认关闭，逐源开关，只读 usage 字段）。
// 每个源的 schema 依据公开情报 + 本机真实样本核验（docs/agents/*.md）。
// 纪律：不读正文/代码/凭据；解析失败只影响该源状态，不阻塞其他源。
//
// 注意：本文件有意合并了全部 T1 Provider，避免继续扩张
// Helper/fixture 的显式编译清单维护成本（G-V2 审计已记录该成本）；
// 每源以 MARK 分节，G-A2 扩容时若拆分需同步全部编译入口。

struct AgentSourceObservation {
    var sourceID: String
    var status: String
    var files: Int
    var records: Int
}

enum AgentSourceRegistry {
    static let geminiCLI = "Gemini CLI"
    static let qwenCode = "Qwen Code"
    static let kimiCode = "Kimi Code"
    static let openCode = "OpenCode"
    static let amp = "Amp"
    static let droid = "Droid"
    static let grokBuild = "Grok Build"

    static let allSourceIDs: [String] = [
        geminiCLI, qwenCode, kimiCode, openCode, amp, droid, grokBuild
    ]

    /// 启用语义（2026-08-13 用户裁决）：
    /// - 主开关关 → 一律不采集（隐私默认不变）；
    /// - 主开关开 + 用户未做逐源选择（nil）→ **检测到已安装的源自动纳入统计**；
    /// - 用户做过任何逐源操作（显式列表）→ 以列表为准（可关掉自动纳入的源）。
    static func enabledIDs(
        masterEnabled: Bool,
        perSource: [String]?,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        guard masterEnabled else { return [] }
        if let perSource, !perSource.isEmpty {
            return perSource.filter { allSourceIDs.contains($0) || ["ZCode", "Hermes Agent", "WorkBuddy"].contains($0) }
        }
        return allSourceIDs.filter { detectorStatus(for: $0, homeURL: homeURL) == "installed" }
    }

    /// 探测：不解析 usage，只看目录/文件是否存在（设置页三态展示用）。
    static func observeAll(homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AgentSourceObservation] {
        allSourceIDs.map { id in
            AgentSourceObservation(
                sourceID: id,
                status: detectorStatus(for: id, homeURL: homeURL),
                files: 0,
                records: 0
            )
        }
    }

    /// 采集：只跑启用源；每源独立降级。
    static func collect(
        enabledIDs: [String],
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String: CollectorResult] {
        var results: [String: CollectorResult] = [:]
        guard !enabledIDs.isEmpty else { return results }
        for id in enabledIDs where allSourceIDs.contains(id) {
            results[id] = collectSource(id: id, homeURL: homeURL)
        }
        return results
    }

    private static func collectSource(id: String, homeURL: URL) -> CollectorResult {
        switch id {
        case geminiCLI:
            return GeminiCLISource.collect(homeURL: homeURL)
        case qwenCode:
            return QwenCodeSource.collect(homeURL: homeURL)
        case kimiCode:
            return KimiCodeSource.collect(homeURL: homeURL)
        case openCode:
            return OpenCodeSource.collect(homeURL: homeURL)
        case amp:
            return GenericJSONLSource.collect(
                tool: amp,
                roots: [homeURL.appendingPathComponent(".local/share/amp/threads", isDirectory: true)]
            )
        case droid:
            return GenericJSONLSource.collect(
                tool: droid,
                roots: [homeURL.appendingPathComponent(".factory/sessions", isDirectory: true)]
            )
        case grokBuild:
            return GrokBuildSource.collect(homeURL: homeURL)
        default:
            return CollectorResult(records: [], source: SourceInfo(status: "disabled", files: nil, records: 0))
        }
    }

    private static func detectorStatus(for id: String, homeURL: URL) -> String {
        let roots: [(String, [URL])] = [
            (geminiCLI, [homeURL.appendingPathComponent(".gemini/tmp", isDirectory: true)]),
            (qwenCode, [
                homeURL.appendingPathComponent(".qwen/tmp", isDirectory: true),
                homeURL.appendingPathComponent(".qwen/projects", isDirectory: true)
            ]),
            (kimiCode, [
                homeURL.appendingPathComponent(".kimi-code/sessions", isDirectory: true),
                homeURL.appendingPathComponent(".kimi/sessions", isDirectory: true)
            ]),
            (openCode, [homeURL.appendingPathComponent(".local/share/opencode/opencode.db")]),
            (amp, [homeURL.appendingPathComponent(".local/share/amp/threads", isDirectory: true)]),
            (droid, [homeURL.appendingPathComponent(".factory/sessions", isDirectory: true)]),
            (grokBuild, [homeURL.appendingPathComponent(".grok/sessions", isDirectory: true)])
        ]
        guard let entry = roots.first(where: { $0.0 == id }) else { return "missing" }
        return entry.1.contains { FileManager.default.fileExists(atPath: $0.path) } ? "installed" : "missing"
    }
}

// MARK: - 共用工具

enum AgentSourceSupport {
    static let maxLineBytes = 4_000_000

    static func jsonlFiles(under root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    static func allFiles(under root: URL, extensions: [String]) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where extensions.contains(url.pathExtension) {
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    static func jsonObject(from line: String) -> [String: Any]? {
        guard line.utf8.count <= maxLineBytes,
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return nil }
        return dictionary
    }

    static func dayKey(fromEpoch epoch: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter.string(from: Date(timeIntervalSince1970: epoch))
    }

    static func dayKey(fromISO iso: String?) -> String? {
        guard let iso else { return nil }
        let formatter = ISO8601DateFormatter()
        return dayKey(fromEpoch: formatter.date(from: iso)?.timeIntervalSince1970 ?? 0)
    }

    static func fileDay(_ url: URL) -> String? {
        let epoch = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?
            .timeIntervalSince1970
        guard let epoch else { return nil }
        return dayKey(fromEpoch: epoch)
    }

    static func int(_ value: Any?) -> Int {
        max(0, (value as? Int) ?? (value as? Double).map(Int.init) ?? (value as? NSNumber)?.intValue ?? 0)
    }

    static func nonEmpty(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    static func counts(
        input: Int,
        output: Int,
        cacheRead: Int = 0,
        cacheCreation: Int = 0,
        reasoning: Int = 0,
        inputIncludesCached: Bool,
        explicitTotal: Int? = nil
    ) -> TokenUsageCounts {
        var counts = TokenUsageCounts()
        let cached = min(cacheRead, inputIncludesCached ? input : .max)
        counts.inputTokens = inputIncludesCached ? max(0, input) : input + cacheRead + cacheCreation
        counts.cacheReadInputTokens = inputIncludesCached ? cached : cacheRead
        counts.cacheCreationInputTokens = cacheCreation
        counts.reasoningOutputTokens = reasoning
        counts.outputTokens = output
        counts.totalTokens = explicitTotal ?? (counts.inputTokens + counts.outputTokens)
        return counts
    }

    static func record(
        tool: String,
        model: String,
        day: String,
        epoch: TimeInterval?,
        usage: TokenUsageCounts,
        requestID: String,
        sessionID: String?,
        projectName: String? = nil
    ) -> UsageRecord {
        UsageRecord(
            date: day,
            timestamp: epoch.map { ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: $0)) },
            timestampEpoch: epoch,
            tool: tool,
            model: model,
            usage: usage,
            source: .experimentalAgent,
            requestID: requestID,
            sessionID: sessionID,
            projectName: projectName
        )
    }
}

// MARK: - Gemini CLI（本机真实样本核验：session-*.json 单文档 + tokens 分量）

enum GeminiCLISource {
    static func collect(homeURL: URL) -> CollectorResult {
        let root = homeURL.appendingPathComponent(".gemini/tmp", isDirectory: true)
        let files = AgentSourceSupport.allFiles(under: root, extensions: ["json", "jsonl"])
        var records: [UsageRecord] = []
        var seen = Set<String>()
        for file in files where file.lastPathComponent.hasPrefix("session-") {
            if file.pathExtension == "jsonl" {
                collectJSONL(file, seen: &seen, records: &records)
            } else {
                collectSingleDoc(file, seen: &seen, records: &records)
            }
        }
        return CollectorResult(
            records: records,
            source: SourceInfo(
                status: records.isEmpty
                    ? (files.isEmpty ? "missing" : "missing_valid_rows")
                    : "ok",
                files: files.count,
                records: records.count
            )
        )
    }

    private static func collectSingleDoc(_ file: URL, seen: inout Set<String>, records: inout [UsageRecord]) {
        guard let data = try? Data(contentsOf: file),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }
        let sessionID = AgentSourceSupport.nonEmpty(object["sessionId"])
        for (index, raw) in ((object["messages"] as? [Any]) ?? []).enumerated() {
            guard let message = raw as? [String: Any],
                  message["type"] as? String == "gemini",
                  let tokens = message["tokens"] as? [String: Any]
            else { continue }
            let usage = usage(fromTokens: tokens)
            guard usage.totalTokens > 0 else { continue }
            let epoch = (message["timestamp"] as? String).flatMap {
                ISO8601DateFormatter().date(from: $0)?.timeIntervalSince1970
            }
            let day = AgentSourceSupport.dayKey(fromISO: message["timestamp"] as? String)
                ?? AgentSourceSupport.fileDay(file)
                ?? AgentSourceSupport.dayKey(fromEpoch: epoch ?? Date().timeIntervalSince1970)
            let identity = "gemini:\(sessionID ?? file.lastPathComponent):\(AgentSourceSupport.nonEmpty(message["id"]) ?? String(index))"
            guard seen.insert(identity).inserted else { continue }
            records.append(
                AgentSourceSupport.record(
                    tool: AgentSourceRegistry.geminiCLI,
                    model: AgentSourceSupport.nonEmpty(message["model"]) ?? "gemini-unknown",
                    day: day,
                    epoch: epoch,
                    usage: usage,
                    requestID: identity,
                    sessionID: sessionID
                )
            )
        }
    }

    private static func collectJSONL(_ file: URL, seen: inout Set<String>, records: inout [UsageRecord]) {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return }
        let sessionID = file.deletingPathExtension().lastPathComponent
        for (index, line) in content.split(separator: "\n").enumerated() {
            guard let object = AgentSourceSupport.jsonObject(from: String(line)) else { continue }
            // 新版 JSONL：usageMetadata（promptTokenCount 含 cachedContentTokenCount）。
            if let metadata = object["usageMetadata"] as? [String: Any] {
                let prompt = AgentSourceSupport.int(metadata["promptTokenCount"])
                let output = AgentSourceSupport.int(metadata["candidatesTokenCount"])
                let cached = AgentSourceSupport.int(metadata["cachedContentTokenCount"])
                let thoughts = AgentSourceSupport.int(metadata["thoughtsTokenCount"])
                let usage = AgentSourceSupport.counts(
                    input: prompt,
                    output: output,
                    cacheRead: cached,
                    reasoning: thoughts,
                    inputIncludesCached: true,
                    explicitTotal: AgentSourceSupport.int(metadata["totalTokenCount"]) > 0
                        ? AgentSourceSupport.int(metadata["totalTokenCount"])
                        : nil
                )
                guard usage.totalTokens > 0 else { continue }
                let identity = "gemini:\(sessionID):\(index)"
                guard seen.insert(identity).inserted else { continue }
                let epoch = object["timestamp"] as? Double ?? fileModification(file)
                records.append(
                    AgentSourceSupport.record(
                        tool: AgentSourceRegistry.geminiCLI,
                        model: AgentSourceSupport.nonEmpty(object["model"]) ?? "gemini-unknown",
                        day: AgentSourceSupport.dayKey(fromEpoch: epoch),
                        epoch: epoch,
                        usage: usage,
                        requestID: identity,
                        sessionID: sessionID
                    )
                )
            }
        }
    }

    private static func usage(fromTokens tokens: [String: Any]) -> TokenUsageCounts {
        let input = AgentSourceSupport.int(tokens["input"])
        let output = AgentSourceSupport.int(tokens["output"])
        let cached = AgentSourceSupport.int(tokens["cached"])
        let thoughts = AgentSourceSupport.int(tokens["thoughts"])
        let toolTokens = AgentSourceSupport.int(tokens["tool"])
        let total = AgentSourceSupport.int(tokens["total"])
        return AgentSourceSupport.counts(
            input: input + toolTokens,
            output: output,
            cacheRead: cached,
            reasoning: thoughts,
            inputIncludesCached: true,
            explicitTotal: total > 0 ? total : nil
        )
    }

    private static func fileModification(_ url: URL) -> TimeInterval {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?
            .timeIntervalSince1970 ?? Date().timeIntervalSince1970
    }
}

// MARK: - Qwen Code（Gemini 分叉：usageMetadata；无本机样本，按公开 schema）

enum QwenCodeSource {
    static func collect(homeURL: URL) -> CollectorResult {
        let roots = [
            homeURL.appendingPathComponent(".qwen/tmp", isDirectory: true),
            homeURL.appendingPathComponent(".qwen/projects", isDirectory: true)
        ]
        var records: [UsageRecord] = []
        var seen = Set<String>()
        var files = 0
        for root in roots {
            let jsonlFiles = AgentSourceSupport.jsonlFiles(under: root)
            files += jsonlFiles.count
            for file in jsonlFiles {
                guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let sessionID = file.deletingPathExtension().lastPathComponent
                for (index, line) in content.split(separator: "\n").enumerated() {
                    guard let object = AgentSourceSupport.jsonObject(from: String(line)),
                          let metadata = object["usageMetadata"] as? [String: Any]
                    else { continue }
                    let prompt = AgentSourceSupport.int(metadata["promptTokenCount"])
                    let output = AgentSourceSupport.int(metadata["candidatesTokenCount"])
                    guard prompt + output > 0 else { continue }
                    let identity = "qwen:\(sessionID):\(index)"
                    guard seen.insert(identity).inserted else { continue }
                    let epoch = (object["timestamp"] as? Double)
                        ?? ISO8601DateFormatter().date(from: AgentSourceSupport.nonEmpty(object["timestamp"]) ?? "")?
                            .timeIntervalSince1970
                        ?? fileModification(file)
                    let usage = AgentSourceSupport.counts(
                        input: prompt,
                        output: output,
                        cacheRead: AgentSourceSupport.int(metadata["cachedContentTokenCount"]),
                        reasoning: AgentSourceSupport.int(metadata["thoughtsTokenCount"]),
                        inputIncludesCached: true
                    )
                    records.append(
                        AgentSourceSupport.record(
                            tool: AgentSourceRegistry.qwenCode,
                            model: AgentSourceSupport.nonEmpty(object["model"]) ?? "qwen-unknown",
                            day: AgentSourceSupport.dayKey(fromEpoch: epoch),
                            epoch: epoch,
                            usage: usage,
                            requestID: identity,
                            sessionID: sessionID
                        )
                    )
                }
            }
        }
        return CollectorResult(
            records: records,
            source: SourceInfo(
                status: records.isEmpty ? (files == 0 ? "missing" : "missing_valid_rows") : "ok",
                files: files,
                records: records.count
            )
        )
    }

    private static func fileModification(_ url: URL) -> TimeInterval {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?
            .timeIntervalSince1970 ?? Date().timeIntervalSince1970
    }
}

// MARK: - Kimi Code（新版 wire.jsonl usage.record；旧版 .kimi 无 usage 事件，如实报无数据）

enum KimiCodeSource {
    static func collect(homeURL: URL) -> CollectorResult {
        let roots = [
            homeURL.appendingPathComponent(".kimi-code/sessions", isDirectory: true)
        ]
        var records: [UsageRecord] = []
        var seen = Set<String>()
        var files = 0
        for root in roots {
            let wireFiles = AgentSourceSupport.allFiles(under: root, extensions: ["jsonl"])
                .filter { $0.lastPathComponent == "wire.jsonl" }
            files += wireFiles.count
            for file in wireFiles {
                guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let sessionDirectory = file.deletingLastPathComponent().deletingLastPathComponent()
                let sessionID = sessionDirectory.lastPathComponent
                for (index, line) in content.split(separator: "\n").enumerated() {
                    guard let object = AgentSourceSupport.jsonObject(from: String(line)),
                          let message = object["message"] as? [String: Any],
                          let type = message["type"] as? String,
                          type.lowercased().contains("usagerecord"),
                          let payload = message["payload"] as? [String: Any]
                    else { continue }
                    let usagePayload = (payload["usage"] as? [String: Any]) ?? payload
                    let input = AgentSourceSupport.int(usagePayload["input_tokens"] ?? usagePayload["inputTokens"])
                    let output = AgentSourceSupport.int(usagePayload["output_tokens"] ?? usagePayload["outputTokens"])
                    guard input + output > 0 else { continue }
                    let identity = "kimi:\(sessionID):\(index)"
                    guard seen.insert(identity).inserted else { continue }
                    let epoch = object["timestamp"] as? Double
                        ?? AgentSourceSupport.int(object["timestamp"]).toDouble
                    let usage = AgentSourceSupport.counts(
                        input: input,
                        output: output,
                        cacheRead: AgentSourceSupport.int(
                            usagePayload["cached_tokens"] ?? usagePayload["cachedInputTokens"]
                                ?? usagePayload["cache_read_tokens"]
                        ),
                        cacheCreation: AgentSourceSupport.int(
                            usagePayload["cache_creation_tokens"] ?? usagePayload["cacheCreationTokens"]
                        ),
                        reasoning: AgentSourceSupport.int(
                            usagePayload["reasoning_tokens"] ?? usagePayload["reasoningTokens"]
                        ),
                        inputIncludesCached: false
                    )
                    records.append(
                        AgentSourceSupport.record(
                            tool: AgentSourceRegistry.kimiCode,
                            model: AgentSourceSupport.nonEmpty(payload["model"]) ?? "kimi-unknown",
                            day: AgentSourceSupport.dayKey(fromEpoch: epoch),
                            epoch: epoch,
                            usage: usage,
                            requestID: identity,
                            sessionID: sessionID,
                            projectName: UsageCollector.projectDisplayName(
                                fromPath: AgentSourceSupport.nonEmpty(payload["cwd"])
                            )
                        )
                    )
                }
            }
        }
        return CollectorResult(
            records: records,
            source: SourceInfo(
                status: records.isEmpty ? (files == 0 ? "missing" : "missing_valid_rows") : "ok",
                files: files,
                records: records.count
            )
        )
    }
}

// MARK: - OpenCode（SQLite：message.data JSON 的 tokens 分量；本机真实样本核验）

enum OpenCodeSource {
    static func collect(homeURL: URL) -> CollectorResult {
        let database = homeURL.appendingPathComponent(".local/share/opencode/opencode.db")
        guard FileManager.default.fileExists(atPath: database.path) else {
            return CollectorResult(records: [], source: SourceInfo(status: "missing_db", files: 0, records: 0))
        }
        let query = """
        select time_created,
               json_extract(data, '$.modelID'),
               json_extract(data, '$.tokens.input'),
               json_extract(data, '$.tokens.output'),
               json_extract(data, '$.tokens.reasoning'),
               json_extract(data, '$.tokens.cache.read'),
               json_extract(data, '$.tokens.cache.write'),
               json_extract(data, '$.path.cwd')
        from message
        where json_extract(data, '$.role') = 'assistant'
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", database.path, query]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else {
            return CollectorResult(records: [], source: SourceInfo(status: "query_failed", files: 1, records: 0))
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else {
            return CollectorResult(records: [], source: SourceInfo(status: "query_failed", files: 1, records: 0))
        }
        var records: [UsageRecord] = []
        for row in payload {
            let created = AgentSourceSupport.int(row["time_created"])
            let epoch = created > 10_000_000_000 ? TimeInterval(created) / 1000 : TimeInterval(created)
            let input = AgentSourceSupport.int(row["json_extract(data, '$.tokens.input')"])
            let outputTokens = AgentSourceSupport.int(row["json_extract(data, '$.tokens.output')"])
            let cacheRead = AgentSourceSupport.int(row["json_extract(data, '$.tokens.cache.read')"])
            let cacheWrite = AgentSourceSupport.int(row["json_extract(data, '$.tokens.cache.write')"])
            let reasoning = AgentSourceSupport.int(row["json_extract(data, '$.tokens.reasoning')"])
            guard input + outputTokens + cacheRead + cacheWrite > 0, epoch > 0 else { continue }
            let usage = AgentSourceSupport.counts(
                input: input,
                output: outputTokens,
                cacheRead: cacheRead,
                cacheCreation: cacheWrite,
                reasoning: reasoning,
                inputIncludesCached: false
            )
            records.append(
                AgentSourceSupport.record(
                    tool: AgentSourceRegistry.openCode,
                    model: AgentSourceSupport.nonEmpty(row["json_extract(data, '$.modelID')"]) ?? "opencode-unknown",
                    day: AgentSourceSupport.dayKey(fromEpoch: epoch),
                    epoch: epoch,
                    usage: usage,
                    requestID: "opencode:\(AgentSourceSupport.int(row["time_created"])):\(usage.totalTokens)",
                    sessionID: nil,
                    projectName: UsageCollector.projectDisplayName(
                        fromPath: AgentSourceSupport.nonEmpty(row["json_extract(data, '$.path.cwd')"])
                    )
                )
            )
        }
        return CollectorResult(
            records: records,
            source: SourceInfo(
                status: records.isEmpty ? "missing_valid_rows" : "ok",
                files: 1,
                records: records.count
            )
        )
    }
}

// MARK: - Grok Build（本机真实样本核验：updates.jsonl turn_completed.usage + URL 编码项目目录）

enum GrokBuildSource {
    static func collect(homeURL: URL) -> CollectorResult {
        let root = homeURL.appendingPathComponent(".grok/sessions", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else {
            return CollectorResult(records: [], source: SourceInfo(status: "missing", files: 0, records: 0))
        }
        var records: [UsageRecord] = []
        var seen = Set<String>()
        let files = AgentSourceSupport.jsonlFiles(under: root).filter { $0.lastPathComponent == "updates.jsonl" }
        for file in files {
            // 项目目录名：sessions/<URL-encoded-cwd>/<session-id>/updates.jsonl
            let sessionDirectory = file.deletingLastPathComponent()
            let encodedProject = sessionDirectory.deletingLastPathComponent().lastPathComponent
            let projectName = UsageCollector.projectDisplayName(
                fromPath: encodedProject.removingPercentEncoding
            )
            let sessionID = sessionDirectory.lastPathComponent
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (index, line) in content.split(separator: "\n").enumerated() {
                guard let object = AgentSourceSupport.jsonObject(from: String(line)),
                      let params = object["params"] as? [String: Any],
                      let update = params["update"] as? [String: Any],
                      update["sessionUpdate"] as? String == "turn_completed",
                      let usagePayload = update["usage"] as? [String: Any]
                else { continue }
                let usage = usage(from: usagePayload)
                guard usage.totalTokens > 0 else { continue }
                let promptID = AgentSourceSupport.nonEmpty(update["prompt_id"]) ?? String(index)
                let identity = "grok:\(AgentSourceSupport.nonEmpty(params["sessionId"]) ?? sessionID):\(promptID)"
                guard seen.insert(identity).inserted else { continue }
                let epoch = AgentSourceSupport.int(object["timestamp"]).toDouble
                guard epoch > 0 else { continue }
                records.append(
                    AgentSourceSupport.record(
                        tool: AgentSourceRegistry.grokBuild,
                        model: model(from: usagePayload),
                        day: AgentSourceSupport.dayKey(fromEpoch: epoch),
                        epoch: epoch,
                        usage: usage,
                        requestID: identity,
                        sessionID: AgentSourceSupport.nonEmpty(params["sessionId"]) ?? sessionID,
                        projectName: projectName
                    )
                )
            }
        }
        return CollectorResult(
            records: records,
            source: SourceInfo(
                status: records.isEmpty
                    ? (files.isEmpty ? "missing" : "missing_valid_rows")
                    : "ok",
                files: files.count,
                records: records.count
            )
        )
    }

    private static func usage(from payload: [String: Any]) -> TokenUsageCounts {
        let input = AgentSourceSupport.int(payload["inputTokens"])
        let output = AgentSourceSupport.int(payload["outputTokens"])
        let cached = AgentSourceSupport.int(payload["cachedReadTokens"])
        let reasoning = AgentSourceSupport.int(payload["reasoningTokens"])
        return AgentSourceSupport.counts(
            input: input,
            output: output,
            cacheRead: cached,
            reasoning: reasoning,
            inputIncludesCached: true,
            explicitTotal: AgentSourceSupport.int(payload["totalTokens"]) > 0
                ? AgentSourceSupport.int(payload["totalTokens"])
                : nil
        )
    }

    private static func model(from payload: [String: Any]) -> String {
        if let modelUsage = payload["modelUsage"] as? [String: Any],
           let first = modelUsage.keys.sorted().first {
            return first
        }
        return "grok-unknown"
    }
}

// MARK: - Amp / Droid（无本机样本：通用 usage 行提取，找不到即如实无数据）

enum GenericJSONLSource {
    static func collect(tool: String, roots: [URL]) -> CollectorResult {
        var records: [UsageRecord] = []
        var seen = Set<String>()
        var files = 0
        for root in roots {
            let jsonlFiles = AgentSourceSupport.jsonlFiles(under: root)
            files += jsonlFiles.count
            for file in jsonlFiles {
                guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let sessionID = file.deletingPathExtension().lastPathComponent
                for (index, line) in content.split(separator: "\n").enumerated() {
                    guard let object = AgentSourceSupport.jsonObject(from: String(line)) else { continue }
                    let usagePayload = (object["usage"] as? [String: Any])
                        ?? ((object["payload"] as? [String: Any])?["usage"] as? [String: Any])
                        ?? ((object["update"] as? [String: Any])?["usage"] as? [String: Any])
                    guard let usagePayload else { continue }
                    let input = AgentSourceSupport.int(
                        usagePayload["input_tokens"] ?? usagePayload["inputTokens"] ?? usagePayload["input"]
                    )
                    let output = AgentSourceSupport.int(
                        usagePayload["output_tokens"] ?? usagePayload["outputTokens"] ?? usagePayload["output"]
                    )
                    guard input + output > 0 else { continue }
                    let identity = "\(tool):\(sessionID):\(index)"
                    guard seen.insert(identity).inserted else { continue }
                    let epoch = (object["timestamp"] as? Double)
                        ?? AgentSourceSupport.int(object["timestamp"]).toDouble
                    let usage = AgentSourceSupport.counts(
                        input: input,
                        output: output,
                        cacheRead: AgentSourceSupport.int(
                            usagePayload["cache_read_tokens"] ?? usagePayload["cachedReadTokens"]
                                ?? usagePayload["cached_input_tokens"]
                        ),
                        inputIncludesCached: false
                    )
                    records.append(
                        AgentSourceSupport.record(
                            tool: tool,
                            model: AgentSourceSupport.nonEmpty(object["model"])
                                ?? AgentSourceSupport.nonEmpty(usagePayload["model"])
                                ?? "\(tool)-unknown",
                            day: AgentSourceSupport.dayKey(fromEpoch: epoch),
                            epoch: epoch,
                            usage: usage,
                            requestID: identity,
                            sessionID: sessionID,
                            projectName: UsageCollector.projectDisplayName(
                                fromPath: AgentSourceSupport.nonEmpty(object["cwd"])
                            )
                        )
                    )
                }
            }
        }
        return CollectorResult(
            records: records,
            source: SourceInfo(
                status: records.isEmpty ? (files == 0 ? "missing" : "missing_valid_rows") : "ok",
                files: files,
                records: records.count
            )
        )
    }
}

private extension Int {
    var toDouble: TimeInterval {
        TimeInterval(self)
    }
}
