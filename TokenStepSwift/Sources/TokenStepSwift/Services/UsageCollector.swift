import Foundation

enum UsageCollector {
    private static let timezone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    static func collect() -> UsageSnapshot {
        let codex = collectCodex()
        let claude = collectClaudeCode()
        return aggregate(
            records: codex.records + claude.records,
            sources: [
                "Codex": codex.source,
                "Claude Code": claude.source
            ]
        )
    }

    private static func collectCodex() -> CollectorResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent(".codex/sessions", isDirectory: true),
            home.appendingPathComponent(".codex/archived_sessions", isDirectory: true)
        ]
        let paths = roots.flatMap { jsonlFiles(under: $0) }
        var records: [UsageRecord] = []
        var seen = Set<String>()
        var filesRead = 0

        for path in paths.sorted(by: { $0.path < $1.path }) {
            var sessionID = path.deletingPathExtension().lastPathComponent
            var currentModel = "unknown"
            var eventIndex = 0
            guard let handle = try? FileHandle(forReadingFrom: path) else { continue }
            filesRead += 1
            defer { try? handle.close() }

            for line in String(decoding: handle.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true) {
                guard let obj = jsonObject(String(line)) else { continue }
                let type = obj["type"] as? String
                let payload = obj["payload"] as? [String: Any]

                if type == "session_meta", let id = payload?["id"] as? String, !id.isEmpty {
                    sessionID = id
                }
                if type == "turn_context" {
                    currentModel = modelKey(payload?["model"] as? String ?? currentModel)
                }
                guard type == "event_msg",
                      payload?["type"] as? String == "token_count",
                      let info = payload?["info"] as? [String: Any]
                else {
                    continue
                }

                let usage = normalizeUsage(info["last_token_usage"] as? [String: Any])
                guard usage.totalTokens > 0,
                      let timestamp = obj["timestamp"] as? String,
                      let day = dayString(fromISO: timestamp)
                else {
                    continue
                }

                eventIndex += 1
                let key = "\(sessionID)|\(timestamp)|\(eventIndex)|\(usage.totalTokens)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                records.append(
                    UsageRecord(
                        date: day,
                        timestamp: timestamp,
                        tool: "Codex",
                        model: currentModel,
                        usage: usage
                    )
                )
            }
        }

        return CollectorResult(
            records: records,
            source: SourceInfo(
                status: records.isEmpty ? "missing" : "ok",
                files: filesRead,
                records: records.count
            )
        )
    }

    private static func collectClaudeCode() -> CollectorResult {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        let paths = jsonlFiles(under: root)
        var records: [UsageRecord] = []
        var seen = Set<String>()
        var filesRead = 0

        for path in paths.sorted(by: { $0.path < $1.path }) {
            guard let handle = try? FileHandle(forReadingFrom: path) else { continue }
            filesRead += 1
            defer { try? handle.close() }

            var lineNumber = 0
            for line in String(decoding: handle.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true) {
                lineNumber += 1
                guard let obj = jsonObject(String(line)),
                      obj["type"] as? String == "assistant",
                      let message = obj["message"] as? [String: Any]
                else {
                    continue
                }

                let usage = normalizeUsage(message["usage"] as? [String: Any])
                guard usage.totalTokens > 0,
                      let timestamp = obj["timestamp"] as? String,
                      let day = dayString(fromISO: timestamp)
                else {
                    continue
                }

                let unique = (obj["uuid"] as? String) ?? "\(path.path):\(lineNumber)"
                guard !seen.contains(unique) else { continue }
                seen.insert(unique)
                records.append(
                    UsageRecord(
                        date: day,
                        timestamp: timestamp,
                        tool: "Claude Code",
                        model: modelKey(message["model"] as? String),
                        usage: usage
                    )
                )
            }
        }

        return CollectorResult(
            records: records,
            source: SourceInfo(
                status: records.isEmpty ? "missing" : "ok",
                files: filesRead,
                records: records.count
            )
        )
    }

    private static func aggregate(records: [UsageRecord], sources: [String: SourceInfo]) -> UsageSnapshot {
        var daily = [String: DailyAccumulator]()
        var tools = [String: UsageAccumulator]()
        var models = [ModelKey: UsageAccumulator]()

        for record in records {
            let cost = estimateCost(usage: record.usage, tool: record.tool, model: record.model)
            daily[record.date, default: DailyAccumulator(date: record.date)].add(record: record, cost: cost)
            tools[record.tool, default: UsageAccumulator()].add(record.usage, cost: cost)
            models[ModelKey(tool: record.tool, model: record.model), default: UsageAccumulator()].add(record.usage, cost: cost)
        }

        let totalTokens = tools.values.map(\.usage.totalTokens).reduce(0, +)
        let totalCost = tools.values.map(\.cost).reduce(0, +)

        let dailyRows = daily.values
            .sorted { $0.date < $1.date }
            .map { item in
                DailyUsage(
                    date: item.date,
                    tools: item.tools,
                    totalTokens: item.totalTokens,
                    cost: rounded(item.cost, digits: 4)
                )
            }

        let toolRows = tools
            .sorted { $0.value.usage.totalTokens > $1.value.usage.totalTokens }
            .map { tool, item in
                ToolUsage(
                    tool: tool,
                    tokens: item.usage.totalTokens,
                    percent: percent(item.usage.totalTokens, of: totalTokens)
                )
            }

        let modelRows = models
            .sorted { $0.value.usage.totalTokens > $1.value.usage.totalTokens }
            .map { key, item in
                ModelUsage(
                    model: key.model,
                    tool: key.tool,
                    tokens: item.usage.totalTokens,
                    percent: percent(item.usage.totalTokens, of: totalTokens)
                )
            }

        return UsageSnapshot(
            generatedAt: isoFormatter.string(from: Date()),
            timezone: "Asia/Shanghai",
            totals: UsageTotals(
                tokens: totalTokens,
                cost: rounded(totalCost, digits: 2),
                activeDays: dailyRows.filter { $0.totalTokens > 0 }.count
            ),
            daily: dailyRows,
            tools: toolRows,
            models: modelRows,
            sources: sources
        )
    }

    private static func jsonlFiles(under root: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              )
        else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.pathExtension == "jsonl",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else {
                return nil
            }
            return url
        }
    }

    private static func jsonObject(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return nil
        }
        return dictionary
    }

    private static func normalizeUsage(_ raw: [String: Any]?) -> TokenUsageCounts {
        guard let raw else { return TokenUsageCounts() }
        var usage = TokenUsageCounts()
        let aliases = [
            "input": "inputTokens",
            "output": "outputTokens",
            "cached": "cacheReadInputTokens",
            "thoughts": "reasoningOutputTokens",
            "total": "totalTokens",
            "input_tokens": "inputTokens",
            "output_tokens": "outputTokens",
            "cache_creation_input_tokens": "cacheCreationInputTokens",
            "cache_read_input_tokens": "cacheReadInputTokens",
            "cached_input_tokens": "cacheReadInputTokens",
            "reasoning_output_tokens": "reasoningOutputTokens",
            "total_tokens": "totalTokens"
        ]

        for (key, value) in raw {
            guard let mapped = aliases[key] else { continue }
            let intValue = integerValue(value)
            switch mapped {
            case "inputTokens": usage.inputTokens += intValue
            case "outputTokens": usage.outputTokens += intValue
            case "cacheCreationInputTokens": usage.cacheCreationInputTokens += intValue
            case "cacheReadInputTokens": usage.cacheReadInputTokens += intValue
            case "reasoningOutputTokens": usage.reasoningOutputTokens += intValue
            case "totalTokens": usage.totalTokens += intValue
            default: break
            }
        }

        if usage.totalTokens <= 0 {
            usage.totalTokens = usage.inputTokens
                + usage.outputTokens
                + usage.cacheCreationInputTokens
                + usage.cacheReadInputTokens
                + usage.reasoningOutputTokens
        }
        return usage
    }

    private static func integerValue(_ value: Any) -> Int {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    private static func dayString(fromISO value: String) -> String? {
        guard let date = parseISO(value) else { return nil }
        return dayFormatter.string(from: date)
    }

    private static func parseISO(_ value: String) -> Date? {
        if let date = isoFormatterWithFractional.date(from: value) {
            return date
        }
        return isoFormatter.date(from: value)
    }

    private static func modelKey(_ model: String?) -> String {
        let value = (model ?? "unknown").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "unknown" : value
    }

    private static func estimateCost(usage: TokenUsageCounts, tool: String, model: String) -> Double {
        let lower = model.lowercased()
        if lower.contains("opus") {
            return costByParts(usage: usage, input: 15, output: 75, cacheCreation: 18.75, cacheRead: 1.5)
        }
        if lower.contains("sonnet") {
            return costByParts(usage: usage, input: 3, output: 15, cacheCreation: 3.75, cacheRead: 0.3)
        }
        if tool == "Claude Code" {
            return Double(usage.totalTokens) / 1_000_000 * 3
        }
        return Double(usage.totalTokens) / 1_000_000
    }

    private static func costByParts(
        usage: TokenUsageCounts,
        input: Double,
        output: Double,
        cacheCreation: Double,
        cacheRead: Double
    ) -> Double {
        Double(usage.inputTokens) / 1_000_000 * input
            + Double(usage.outputTokens) / 1_000_000 * output
            + Double(usage.cacheCreationInputTokens) / 1_000_000 * cacheCreation
            + Double(usage.cacheReadInputTokens) / 1_000_000 * cacheRead
            + Double(usage.reasoningOutputTokens) / 1_000_000 * output
    }

    private static func percent(_ value: Int, of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return rounded(Double(value) / Double(total) * 100, digits: 2)
    }

    private static func rounded(_ value: Double, digits: Int) -> Double {
        let multiplier = pow(10.0, Double(digits))
        return (value * multiplier).rounded() / multiplier
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct CollectorResult {
    var records: [UsageRecord]
    var source: SourceInfo
}

private struct UsageRecord {
    var date: String
    var timestamp: String?
    var tool: String
    var model: String
    var usage: TokenUsageCounts
}

private struct TokenUsageCounts {
    var inputTokens = 0
    var outputTokens = 0
    var cacheCreationInputTokens = 0
    var cacheReadInputTokens = 0
    var reasoningOutputTokens = 0
    var totalTokens = 0
}

private struct UsageAccumulator {
    var usage = TokenUsageCounts()
    var cost = 0.0

    mutating func add(_ counts: TokenUsageCounts, cost: Double) {
        usage.inputTokens += counts.inputTokens
        usage.outputTokens += counts.outputTokens
        usage.cacheCreationInputTokens += counts.cacheCreationInputTokens
        usage.cacheReadInputTokens += counts.cacheReadInputTokens
        usage.reasoningOutputTokens += counts.reasoningOutputTokens
        usage.totalTokens += counts.totalTokens
        self.cost += cost
    }
}

private struct DailyAccumulator {
    var date: String
    var tools: [String: Int] = [:]
    var totalTokens = 0
    var cost = 0.0

    mutating func add(record: UsageRecord, cost: Double) {
        tools[record.tool, default: 0] += record.usage.totalTokens
        totalTokens += record.usage.totalTokens
        self.cost += cost
    }
}

private struct ModelKey: Hashable {
    var tool: String
    var model: String
}
