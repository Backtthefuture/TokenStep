import Foundation

enum UsageCollector {
    private static let timezone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    private static let maxRelevantLineBytes = 1_048_576
    private static let ccSwitchSourceName = "CC Switch Proxy"

    static func collect(
        historyDays: Int = TokenStepSettings.defaults.historyDays,
        includeCCSwitchProxyUsage: Bool = true,
        ccSwitchDatabaseURL: URL? = nil
    ) -> UsageSnapshot {
        var cache = loadCache()
        var livePaths = Set<String>()
        let sourceCutoff = sourceFileCutoffDate(historyDays: historyDays)
        let codex = collectCodex(cache: &cache, livePaths: &livePaths, modifiedSince: sourceCutoff)
        let claude = collectClaudeCode(cache: &cache, livePaths: &livePaths, modifiedSince: sourceCutoff)
        var ccSwitch = includeCCSwitchProxyUsage
            ? collectCCSwitchProxyUsage(databaseURL: ccSwitchDatabaseURL)
            : CollectorResult(records: [], source: SourceInfo(status: "disabled", files: nil, records: 0))
        cache.files = cache.files.filter { livePaths.contains($0.key) }
        saveCache(cache)

        let nativeRecords = codex.records + claude.records
        let deduped = deduplicateCrossSource(
            nativeRecords: nativeRecords,
            proxyRecords: ccSwitch.records
        )
        if includeCCSwitchProxyUsage {
            ccSwitch.source = sourceInfo(ccSwitch.source, annotatedWith: deduped)
        }
        return aggregate(
            records: deduped.records,
            sources: [
                "Codex": codex.source,
                "Claude Code": claude.source,
                ccSwitchSourceName: ccSwitch.source
            ]
        )
    }

    static func collectCCSwitchProxyUsageSnapshot(databaseURL: URL) -> UsageSnapshot {
        let result = collectCCSwitchProxyUsage(databaseURL: databaseURL)
        return aggregate(
            records: result.records,
            sources: [ccSwitchSourceName: result.source]
        )
    }

    static func collectClaudeCodeUsageSnapshot(rootURL: URL) -> UsageSnapshot {
        var cache = CollectorCache()
        var livePaths = Set<String>()
        let result = collectClaudeCode(cache: &cache, livePaths: &livePaths, rootURL: rootURL, modifiedSince: nil)
        return aggregate(records: result.records, sources: ["Claude Code": result.source])
    }

    static func collectCodexUsageSnapshotForTests(homeURL: URL) -> UsageSnapshot {
        var cache = CollectorCache()
        var livePaths = Set<String>()
        let result = collectCodexFromJSONL(
            cache: &cache,
            livePaths: &livePaths,
            modifiedSince: nil,
            homeURL: homeURL
        )
        return aggregate(records: result.records, sources: ["Codex": result.source])
    }

    static func collectUsageSnapshotForTests(
        codexRoots: [URL] = [],
        claudeRootURL: URL? = nil,
        ccSwitchDatabaseURL: URL? = nil
    ) -> UsageSnapshot {
        var cache = CollectorCache()
        var livePaths = Set<String>()
        let codex = codexRoots.isEmpty
            ? CollectorResult(records: [], source: SourceInfo(status: "disabled", files: nil, records: 0))
            : collectCodexFromJSONL(
                cache: &cache,
                livePaths: &livePaths,
                modifiedSince: nil,
                roots: codexRoots
            )
        let claude = claudeRootURL.map {
            collectClaudeCode(cache: &cache, livePaths: &livePaths, rootURL: $0, modifiedSince: nil)
        } ?? CollectorResult(records: [], source: SourceInfo(status: "disabled", files: nil, records: 0))
        var ccSwitch = ccSwitchDatabaseURL.map {
            collectCCSwitchProxyUsage(databaseURL: $0)
        } ?? CollectorResult(records: [], source: SourceInfo(status: "disabled", files: nil, records: 0))
        let deduped = deduplicateCrossSource(
            nativeRecords: codex.records + claude.records,
            proxyRecords: ccSwitch.records
        )
        ccSwitch.source = sourceInfo(ccSwitch.source, annotatedWith: deduped)
        return aggregate(
            records: deduped.records,
            sources: [
                "Codex": codex.source,
                "Claude Code": claude.source,
                ccSwitchSourceName: ccSwitch.source
            ]
        )
    }

    private static func collectCodex(cache: inout CollectorCache, livePaths: inout Set<String>, modifiedSince cutoffDate: Date?) -> CollectorResult {
        let jsonlResult = collectCodexFromJSONL(cache: &cache, livePaths: &livePaths, modifiedSince: cutoffDate)
        if jsonlResult.source.status == "ok" {
            return jsonlResult
        }
        return collectCodexFromSQLite() ?? jsonlResult
    }

    private static func collectCodexFromSQLite() -> CollectorResult? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".codex/state_5.sqlite"),
            home.appendingPathComponent(".codex/sqlite/state_5.sqlite")
        ]
        guard let database = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return nil
        }

        let query = "select created_at, model, tokens_used from threads where tokens_used > 0"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", database.path, query]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        let records = rows.compactMap { row -> UsageRecord? in
            let tokens = integerValue(row["tokens_used"] as Any)
            guard tokens > 0,
                  let day = dayString(fromEpoch: row["created_at"] as Any)
            else {
                return nil
            }
            var usage = TokenUsageCounts()
            usage.totalTokens = tokens
            return UsageRecord(
                date: day,
                timestamp: nil,
                tool: "Codex",
                model: modelKey(row["model"] as? String),
                usage: usage,
                source: .nativeCodexSQLite
            )
        }

        guard !records.isEmpty else { return nil }
        return CollectorResult(
            records: records,
            source: SourceInfo(
                status: "ok_sqlite",
                files: 1,
                records: records.count
            )
        )
    }

    private static func collectCodexFromJSONL(
        cache: inout CollectorCache,
        livePaths: inout Set<String>,
        modifiedSince cutoffDate: Date?,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        roots: [URL]? = nil
    ) -> CollectorResult {
        let roots = roots ?? defaultCodexSessionRoots(homeURL: homeURL)
        let paths = roots.flatMap { jsonlFiles(under: $0, modifiedSince: cutoffDate) }
        var records: [UsageRecord] = []
        var seen = Set<String>()

        for path in paths.sorted(by: { $0.path < $1.path }) {
            livePaths.insert(path.path)
            if let cached = cachedRecords(for: path, tool: "Codex", cache: cache) {
                records.append(contentsOf: cached)
                continue
            }

            var fileRecords: [UsageRecord] = []
            var sessionID = path.deletingPathExtension().lastPathComponent
            var currentModel = "unknown"
            var eventIndex = 0
            var lineNumber = 0
            guard FileManager.default.isReadableFile(atPath: path.path) else { continue }

            try? forEachLine(in: path, matchingAny: ["session_meta", "turn_context", "token_count"]) { line in
                autoreleasepool {
                    lineNumber += 1
                    guard let obj = jsonObject(line) else { return }
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
                        return
                    }

                    let usage = normalizeUsage(info["last_token_usage"] as? [String: Any])
                    guard usage.totalTokens > 0,
                          let timestamp = obj["timestamp"] as? String,
                          let day = dayString(fromISO: timestamp)
                    else {
                        return
                    }

                    eventIndex += 1
                    let key = "\(sessionID)|\(timestamp)|\(eventIndex)|\(usage.totalTokens)"
                    guard !seen.contains(key) else { return }
                    seen.insert(key)
                    fileRecords.append(
                        UsageRecord(
                            date: day,
                            timestamp: timestamp,
                            tool: "Codex",
                            model: currentModel,
                            usage: usage,
                            source: .nativeCodex,
                            requestID: key,
                            sessionID: sessionID,
                            sourcePath: path.path,
                            lineNumber: lineNumber
                        )
                    )
                }
            }
            records.append(contentsOf: fileRecords)
            updateCache(path: path, tool: "Codex", records: fileRecords, cache: &cache)
        }

        return CollectorResult(
            records: records,
            source: SourceInfo(
                status: records.isEmpty ? "missing" : "ok",
                files: paths.count,
                records: records.count
            )
        )
    }

    private static func defaultCodexSessionRoots(homeURL: URL) -> [URL] {
        // archived_sessions may contain restored historical logs with rewritten timestamps.
        // Only live Codex sessions should count as current usage.
        [
            homeURL.appendingPathComponent(".codex/sessions", isDirectory: true)
        ]
    }

    private static func collectClaudeCode(
        cache: inout CollectorCache,
        livePaths: inout Set<String>,
        rootURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true),
        modifiedSince cutoffDate: Date?
    ) -> CollectorResult {
        let root = rootURL
        let paths = jsonlFiles(under: root, modifiedSince: cutoffDate)
        var records: [UsageRecord] = []

        for path in paths.sorted(by: { $0.path < $1.path }) {
            livePaths.insert(path.path)
            if let cached = cachedRecords(for: path, tool: "Claude Code", cache: cache) {
                records.append(contentsOf: cached)
                continue
            }

            var fileRecords: [UsageRecord] = []
            var responses = [String: ClaudeUsageCandidate]()
            guard FileManager.default.isReadableFile(atPath: path.path) else { continue }

            var lineNumber = 0

            try? forEachLine(in: path, matchingAny: ["usage"]) { line in
                autoreleasepool {
                    lineNumber += 1
                    guard let obj = jsonObject(line),
                          obj["type"] as? String == "assistant",
                          let message = obj["message"] as? [String: Any]
                    else {
                        return
                    }

                    let usage = normalizeUsage(message["usage"] as? [String: Any])
                    guard usage.totalTokens > 0,
                          let timestamp = obj["timestamp"] as? String,
                          let day = dayString(fromISO: timestamp)
                    else {
                        return
                    }

                    let identity = claudeIdentity(obj: obj, message: message, path: path, lineNumber: lineNumber)
                    let candidate = ClaudeUsageCandidate(
                        date: day,
                        timestamp: timestamp,
                        model: modelKey(message["model"] as? String),
                        usage: usage,
                        hasStopReason: hasStopReason(message["stop_reason"]),
                        lineNumber: lineNumber,
                        requestID: identity.requestID,
                        responseID: identity.responseID,
                        sessionID: identity.sessionID,
                        sourcePath: path.path
                    )
                    if let existing = responses[identity.deduplicationKey],
                       !candidate.isPreferred(over: existing) {
                        return
                    }
                    responses[identity.deduplicationKey] = candidate
                }
            }
            fileRecords = responses.values.map(\.record)
            records.append(contentsOf: fileRecords)
            updateCache(path: path, tool: "Claude Code", records: fileRecords, cache: &cache)
        }

        return CollectorResult(
            records: records,
            source: SourceInfo(
                status: records.isEmpty ? "missing" : "ok",
                files: paths.count,
                records: records.count
            )
        )
    }

    private static func collectCCSwitchProxyUsage(databaseURL: URL? = nil) -> CollectorResult {
        let database = databaseURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cc-switch/cc-switch.db")

        guard FileManager.default.fileExists(atPath: database.path) else {
            return CollectorResult(
                records: [],
                source: SourceInfo(status: "missing_db", files: 0, records: 0)
            )
        }

        guard FileManager.default.isReadableFile(atPath: database.path) else {
            return CollectorResult(
                records: [],
                source: SourceInfo(status: "unreadable_db", files: 1, records: 0)
            )
        }

        guard let columns = sqliteJSONRows(
            database: database,
            query: "pragma table_info(proxy_request_logs)"
        ) else {
            return CollectorResult(
                records: [],
                source: SourceInfo(status: "schema_unreadable", files: 1, records: 0)
            )
        }

        guard !columns.isEmpty else {
            return CollectorResult(
                records: [],
                source: SourceInfo(status: "missing_table", files: 1, records: 0)
            )
        }

        let availableColumns = Set(columns.compactMap { $0["name"] as? String })
        let requiredColumns: Set<String> = [
            "request_id",
            "app_type",
            "provider_id",
            "model",
            "request_model",
            "pricing_model",
            "input_tokens",
            "output_tokens",
            "cache_read_tokens",
            "cache_creation_tokens",
            "total_cost_usd",
            "status_code",
            "created_at"
        ]
        guard requiredColumns.isSubset(of: availableColumns) else {
            return CollectorResult(
                records: [],
                source: SourceInfo(status: "schema_mismatch", files: 1, records: 0)
            )
        }
        guard availableColumns.contains("data_source") else {
            return CollectorResult(
                records: [],
                source: SourceInfo(status: "schema_missing_data_source", files: 1, records: 0)
            )
        }

        let sessionColumn = availableColumns.contains("session_id") ? "session_id" : "null"
        let query = """
        select
            request_id,
            \(sessionColumn) as session_id,
            data_source,
            created_at,
            app_type,
            coalesce(nullif(pricing_model, ''), nullif(model, ''), nullif(request_model, ''), 'unknown') as display_model,
            coalesce(input_tokens, 0) as input_tokens,
            coalesce(output_tokens, 0) as output_tokens,
            coalesce(cache_read_tokens, 0) as cache_read_tokens,
            coalesce(cache_creation_tokens, 0) as cache_creation_tokens,
            cast(coalesce(nullif(total_cost_usd, ''), '0') as real) as total_cost_usd
        from proxy_request_logs
        where status_code >= 200
            and status_code < 300
            and lower(data_source) = 'proxy'
            and (
                coalesce(input_tokens, 0)
                + coalesce(output_tokens, 0)
                + coalesce(cache_read_tokens, 0)
                + coalesce(cache_creation_tokens, 0)
            ) > 0
        order by created_at, request_id
        """

        guard let rows = sqliteJSONRows(database: database, query: query) else {
            return CollectorResult(
                records: [],
                source: SourceInfo(status: "query_failed", files: 1, records: 0)
            )
        }

        let records = rows.compactMap { row -> UsageRecord? in
            guard let day = dayString(fromEpoch: row["created_at"] as Any) else {
                return nil
            }

            var usage = TokenUsageCounts()
            usage.inputTokens = integerValue(row["input_tokens"] as Any)
            usage.outputTokens = integerValue(row["output_tokens"] as Any)
            usage.cacheReadInputTokens = integerValue(row["cache_read_tokens"] as Any)
            usage.cacheCreationInputTokens = integerValue(row["cache_creation_tokens"] as Any)
            usage.totalTokens = usage.inputTokens
                + usage.outputTokens
                + usage.cacheReadInputTokens
                + usage.cacheCreationInputTokens
            guard usage.totalTokens > 0 else { return nil }

            return UsageRecord(
                date: day,
                timestamp: isoString(fromEpoch: row["created_at"] as Any),
                tool: ccSwitchToolName(appType: row["app_type"] as? String),
                model: modelKey(row["display_model"] as? String),
                usage: usage,
                costUSD: doubleValue(row["total_cost_usd"] as Any),
                source: .ccSwitchProxy,
                requestID: nonEmptyString(row["request_id"] as? String),
                sessionID: nonEmptyString(row["session_id"] as? String),
                dataSource: nonEmptyString(row["data_source"] as? String)
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

    private static func deduplicateCrossSource(
        nativeRecords: [UsageRecord],
        proxyRecords: [UsageRecord]
    ) -> CrossSourceDedupeResult {
        var enrichedNativeRecords = nativeRecords
        var keptProxyRecords: [UsageRecord] = []
        var dedupedProxyRecords = 0
        let skippedProxyRecords = 0

        for proxyRecord in proxyRecords {
            guard isDeduplicableProxyRecord(proxyRecord) else {
                keptProxyRecords.append(proxyRecord)
                continue
            }

            if let nativeIndex = nativeRecords.firstIndex(where: { isDuplicate(proxyRecord: proxyRecord, nativeRecord: $0) }) {
                enrichedNativeRecords[nativeIndex] = enrichedRecord(
                    enrichedNativeRecords[nativeIndex],
                    withProxyCostFrom: proxyRecord
                )
                dedupedProxyRecords += 1
            } else {
                keptProxyRecords.append(proxyRecord)
            }
        }

        return CrossSourceDedupeResult(
            records: enrichedNativeRecords + keptProxyRecords,
            rawProxyRecords: proxyRecords.count,
            keptProxyRecords: keptProxyRecords.count,
            dedupedProxyRecords: dedupedProxyRecords,
            skippedProxyRecords: skippedProxyRecords
        )
    }

    private static func sourceInfo(
        _ source: SourceInfo,
        annotatedWith result: CrossSourceDedupeResult
    ) -> SourceInfo {
        var annotated = source
        annotated.rawRecords = result.rawProxyRecords
        annotated.dedupedRecords = result.dedupedProxyRecords
        annotated.skippedRecords = result.skippedProxyRecords
        annotated.strategy = "request_level_dedupe"
        annotated.records = result.keptProxyRecords
        if source.status == "ok",
           result.rawProxyRecords > 0,
           result.keptProxyRecords == 0,
           result.dedupedProxyRecords > 0 {
            annotated.status = "all_deduped"
        }
        return annotated
    }

    private static func isDeduplicableProxyRecord(_ record: UsageRecord) -> Bool {
        guard record.source == .ccSwitchProxy else { return false }
        guard let family = toolFamily(for: record.tool) else { return false }
        return family == "claude" || family == "codex"
    }

    private static func isDuplicate(proxyRecord: UsageRecord, nativeRecord: UsageRecord) -> Bool {
        guard proxyRecord.date == nativeRecord.date,
              let proxyFamily = toolFamily(for: proxyRecord.tool),
              let nativeFamily = toolFamily(for: nativeRecord.tool),
              proxyFamily == nativeFamily,
              nativeRecord.source != .ccSwitchProxy
        else {
            return false
        }

        if hasExactIdentityMatch(proxyRecord: proxyRecord, nativeRecord: nativeRecord) {
            return true
        }

        return hasStrongUsageMatch(proxyRecord: proxyRecord, nativeRecord: nativeRecord)
    }

    private static func hasExactIdentityMatch(proxyRecord: UsageRecord, nativeRecord: UsageRecord) -> Bool {
        let proxyIDs = Set([proxyRecord.requestID, proxyRecord.responseID].compactMap(nonEmptyString))
        let nativeIDs = Set([nativeRecord.requestID, nativeRecord.responseID].compactMap(nonEmptyString))
        if !proxyIDs.isDisjoint(with: nativeIDs) {
            return true
        }

        guard let proxySessionID = nonEmptyString(proxyRecord.sessionID),
              let nativeSessionID = nonEmptyString(nativeRecord.sessionID),
              proxySessionID == nativeSessionID,
              areTimestampsClose(proxyRecord.timestamp, nativeRecord.timestamp, seconds: 10),
              modelsCompatible(proxyRecord.model, nativeRecord.model),
              usageVectorsClose(proxyRecord.usage, nativeRecord.usage)
        else {
            return false
        }
        return true
    }

    private static func hasStrongUsageMatch(proxyRecord: UsageRecord, nativeRecord: UsageRecord) -> Bool {
        areTimestampsClose(proxyRecord.timestamp, nativeRecord.timestamp, seconds: 30)
            && modelsCompatible(proxyRecord.model, nativeRecord.model)
            && usageVectorsClose(proxyRecord.usage, nativeRecord.usage)
    }

    private static func enrichedRecord(
        _ nativeRecord: UsageRecord,
        withProxyCostFrom proxyRecord: UsageRecord
    ) -> UsageRecord {
        var record = nativeRecord
        if record.costUSD == nil,
           let proxyCost = proxyRecord.costUSD,
           proxyCost > 0 {
            record.costUSD = proxyCost
        }
        return record
    }

    private static func toolFamily(for tool: String) -> String? {
        let value = tool.lowercased()
        if value.contains("claude") { return "claude" }
        if value.contains("codex") { return "codex" }
        if value.contains("gemini") { return "gemini" }
        return nil
    }

    private static func areTimestampsClose(_ lhs: String?, _ rhs: String?, seconds: TimeInterval) -> Bool {
        guard let lhs,
              let rhs,
              let lhsDate = parseISO(lhs),
              let rhsDate = parseISO(rhs)
        else {
            return false
        }
        return abs(lhsDate.timeIntervalSince(rhsDate)) <= seconds
    }

    private static func modelsCompatible(_ lhs: String, _ rhs: String) -> Bool {
        let left = canonicalModel(lhs)
        let right = canonicalModel(rhs)
        if left == right { return true }
        guard left != "unknown",
              right != "unknown",
              min(left.count, right.count) >= 8
        else {
            return false
        }
        return left.contains(right) || right.contains(left)
    }

    private static func canonicalModel(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
    }

    private static func usageVectorsClose(_ lhs: TokenUsageCounts, _ rhs: TokenUsageCounts) -> Bool {
        guard tokenValuesClose(lhs.totalTokens, rhs.totalTokens) else { return false }
        let pairs = [
            (lhs.inputTokens, rhs.inputTokens),
            (lhs.outputTokens, rhs.outputTokens),
            (lhs.cacheCreationInputTokens, rhs.cacheCreationInputTokens),
            (lhs.cacheReadInputTokens, rhs.cacheReadInputTokens),
            (lhs.reasoningOutputTokens, rhs.reasoningOutputTokens)
        ]
        return pairs.allSatisfy { pair in
            let left = pair.0
            let right = pair.1
            return left == 0 && right == 0 || tokenValuesClose(left, right)
        }
    }

    private static func tokenValuesClose(_ lhs: Int, _ rhs: Int) -> Bool {
        if lhs == rhs { return true }
        let baseline = max(lhs, rhs)
        guard baseline > 0 else { return true }
        let tolerance = max(4, Int((Double(baseline) * 0.01).rounded(.up)))
        return abs(lhs - rhs) <= tolerance
    }

    private static func aggregate(records: [UsageRecord], sources: [String: SourceInfo]) -> UsageSnapshot {
        var daily = [String: DailyAccumulator]()
        var rhythms = [String: RhythmAccumulator]()
        var tools = [String: UsageAccumulator]()
        var models = [ModelKey: UsageAccumulator]()

        for record in records {
            let cost = record.costUSD ?? estimateCost(usage: record.usage, tool: record.tool, model: record.model)
            daily[record.date, default: DailyAccumulator(date: record.date)].add(record: record, cost: cost)
            if let hour = hour(fromISO: record.timestamp) {
                rhythms[record.date, default: RhythmAccumulator(date: record.date)]
                    .add(tokens: record.usage.totalTokens, hour: hour)
            }
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
                    models: item.models,
                    totalTokens: item.totalTokens,
                    cost: rounded(item.cost, digits: 4)
                )
            }

        let rhythmRows = rhythms.values
            .map(\.dailyRhythm)
            .filter { $0.totalTokens > 0 }
            .sorted { $0.date < $1.date }

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
            rhythms: rhythmRows,
            tools: toolRows,
            models: modelRows,
            sources: sources
        )
    }

    private static func jsonlFiles(under root: URL, modifiedSince cutoffDate: Date? = nil) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
              )
        else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true
            else {
                return nil
            }
            if let cutoffDate,
               let modificationDate = values.contentModificationDate,
               modificationDate < cutoffDate {
                return nil
            }
            return url
        }
    }

    private static func cachedRecords(for url: URL, tool: String, cache: CollectorCache) -> [UsageRecord]? {
        guard let metadata = fileMetadata(for: url),
              let cached = cache.files[url.path],
              cached.tool == tool,
              cached.size == metadata.size,
              abs(cached.modificationTime - metadata.modificationTime) < 0.001
        else {
            return nil
        }
        return cached.records
    }

    private static func updateCache(path: URL, tool: String, records: [UsageRecord], cache: inout CollectorCache) {
        guard let metadata = fileMetadata(for: path) else { return }
        cache.files[path.path] = CachedUsageFile(
            tool: tool,
            size: metadata.size,
            modificationTime: metadata.modificationTime,
            records: records
        )
    }

    private static func fileMetadata(for url: URL) -> (size: UInt64, modificationTime: TimeInterval)? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize,
              let modificationDate = values.contentModificationDate
        else {
            return nil
        }
        return (UInt64(max(0, size)), modificationDate.timeIntervalSince1970)
    }

    private static func loadCache() -> CollectorCache {
        guard let data = try? Data(contentsOf: AppPaths.collectorCacheJSON),
              let cache = try? JSONDecoder().decode(CollectorCache.self, from: data),
              cache.version == CollectorCache.currentVersion
        else {
            return CollectorCache()
        }
        return cache
    }

    private static func saveCache(_ cache: CollectorCache) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(cache)
            try FileManager.default.createDirectory(
                at: AppPaths.collectorCacheJSON.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: AppPaths.collectorCacheJSON, options: .atomic)
        } catch {
            // Cache misses should never prevent the app from showing fresh usage.
        }
    }

    private static func sourceFileCutoffDate(historyDays: Int) -> Date? {
        Calendar.current.date(byAdding: .day, value: -max(7, historyDays + 1), to: Date())
    }

    private static func forEachLine(in url: URL, matchingAny markers: [String] = [], _ body: (String) -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let newline = Data([0x0A])
        let markerData = markers.map { Data($0.utf8) }
        var buffer = Data()
        buffer.reserveCapacity(128 * 1024)
        var discardingOversizedLine = false

        func processLine(_ lineData: Data) {
            guard lineMatches(lineData, markers: markerData),
                  let line = String(data: lineData, encoding: .utf8),
                  !line.isEmpty
            else {
                return
            }
            body(line)
        }

        while true {
            guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else {
                break
            }
            buffer.append(chunk)

            var consumedEnd = buffer.startIndex
            var lineStart = buffer.startIndex
            var searchRange = buffer.startIndex..<buffer.endIndex
            while let range = buffer.range(of: newline, options: [], in: searchRange) {
                let lineEnd = range.lowerBound
                if discardingOversizedLine {
                    discardingOversizedLine = false
                } else if lineEnd > lineStart {
                    let lineData = buffer.subdata(in: lineStart..<lineEnd)
                    processLine(lineData)
                }
                consumedEnd = range.upperBound
                lineStart = range.upperBound
                searchRange = lineStart..<buffer.endIndex
            }

            if consumedEnd > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<consumedEnd)
            }

            if buffer.count > maxRelevantLineBytes {
                discardingOversizedLine = true
                buffer.removeAll(keepingCapacity: true)
            }
        }

        if !discardingOversizedLine,
           !buffer.isEmpty,
           buffer.count <= maxRelevantLineBytes {
            processLine(buffer)
        }
    }

    private static func lineMatches(_ data: Data, markers: [Data]) -> Bool {
        markers.isEmpty || markers.contains { data.range(of: $0) != nil }
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

    private static func doubleValue(_ value: Any) -> Double {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) ?? 0 }
        return 0
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func dayString(fromISO value: String) -> String? {
        guard let date = parseISO(value) else { return nil }
        return dayFormatter.string(from: date)
    }

    private static func hour(fromISO value: String?) -> Int? {
        guard let value, let date = parseISO(value) else { return nil }
        return calendar.component(.hour, from: date)
    }

    private static func dayString(fromEpoch value: Any?) -> String? {
        guard let seconds = epochSeconds(value) else { return nil }
        return dayFormatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private static func isoString(fromEpoch value: Any?) -> String? {
        guard let seconds = epochSeconds(value) else { return nil }
        return isoFormatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private static func epochSeconds(_ value: Any?) -> Double? {
        var seconds: Double
        if let int = value as? Int {
            seconds = Double(int)
        } else if let double = value as? Double {
            seconds = double
        } else if let string = value as? String, let parsed = Double(string) {
            seconds = parsed
        } else {
            return nil
        }
        if seconds > 10_000_000_000 {
            seconds /= 1_000
        }
        return seconds
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

    private static func claudeIdentity(
        obj: [String: Any],
        message: [String: Any],
        path: URL,
        lineNumber: Int
    ) -> ClaudeIdentity {
        let responseID = nonEmptyString(message["id"] as? String)
        let requestID = [
            obj["requestId"] as? String,
            obj["request_id"] as? String,
            message["requestId"] as? String,
            message["request_id"] as? String
        ].compactMap(nonEmptyString).first
        let sessionID = [
            obj["sessionId"] as? String,
            obj["session_id"] as? String,
            obj["sessionID"] as? String
        ].compactMap(nonEmptyString).first
        let uuid = nonEmptyString(obj["uuid"] as? String)

        let deduplicationKey: String
        if let responseID {
            deduplicationKey = "response:\(responseID)"
        } else if let requestID {
            deduplicationKey = "request:\(requestID)"
        } else if let uuid {
            deduplicationKey = "uuid:\(uuid)"
        } else {
            deduplicationKey = "line:\(path.path):\(lineNumber)"
        }
        return ClaudeIdentity(
            deduplicationKey: deduplicationKey,
            requestID: requestID,
            responseID: responseID,
            sessionID: sessionID
        )
    }

    private static func hasStopReason(_ value: Any?) -> Bool {
        guard let text = value as? String else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func ccSwitchToolName(appType: String?) -> String {
        let value = (appType ?? "unknown").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = value.lowercased()
        switch normalized {
        case "claude":
            return "Claude Code via CC Switch"
        case "codex":
            return "Codex via CC Switch"
        case "gemini":
            return "Gemini via CC Switch"
        default:
            return "\(value.isEmpty ? "unknown" : value) via CC Switch (experimental)"
        }
    }

    private static func sqliteJSONRows(database: URL, query: String) -> [[String: Any]]? {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenstep-sqlite-\(UUID().uuidString).json")
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        guard let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            return nil
        }
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", database.path, query]
        process.standardOutput = outputHandle
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        guard !data.isEmpty else { return [] }
        return try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    }

    private static func estimateCost(usage: TokenUsageCounts, tool: String, model: String) -> Double {
        let lower = model.lowercased()
        if tool == "Codex", lower.contains("gpt-5.5") {
            return openAICostByParts(usage: usage, input: 5, cachedInput: 0.5, output: 30)
        }
        if tool == "Codex", lower.contains("gpt-5.4") {
            return openAICostByParts(usage: usage, input: 2.5, cachedInput: 0.25, output: 15)
        }
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

    private static func openAICostByParts(
        usage: TokenUsageCounts,
        input: Double,
        cachedInput: Double,
        output: Double
    ) -> Double {
        let cached = max(0, usage.cacheReadInputTokens)
        let uncachedInput = max(0, usage.inputTokens - cached)
        return Double(uncachedInput + usage.cacheCreationInputTokens) / 1_000_000 * input
            + Double(cached) / 1_000_000 * cachedInput
            + Double(usage.outputTokens + usage.reasoningOutputTokens) / 1_000_000 * output
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

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        return calendar
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

private struct CollectorCache: Codable {
    static let currentVersion = 4

    var version = currentVersion
    var files: [String: CachedUsageFile] = [:]
}

private struct CachedUsageFile: Codable {
    var tool: String
    var size: UInt64
    var modificationTime: TimeInterval
    var records: [UsageRecord]
}

private struct UsageRecord: Codable {
    var date: String
    var timestamp: String?
    var tool: String
    var model: String
    var usage: TokenUsageCounts
    var costUSD: Double? = nil
    var source: UsageRecordSource = .unknown
    var requestID: String? = nil
    var sessionID: String? = nil
    var responseID: String? = nil
    var sourcePath: String? = nil
    var lineNumber: Int? = nil
    var dataSource: String? = nil
}

private enum UsageRecordSource: String, Codable {
    case nativeCodex
    case nativeCodexSQLite
    case nativeClaudeCode
    case ccSwitchProxy
    case unknown
}

private struct CrossSourceDedupeResult {
    var records: [UsageRecord]
    var rawProxyRecords: Int
    var keptProxyRecords: Int
    var dedupedProxyRecords: Int
    var skippedProxyRecords: Int
}

private struct ClaudeIdentity {
    var deduplicationKey: String
    var requestID: String?
    var responseID: String?
    var sessionID: String?
}

private struct ClaudeUsageCandidate {
    var date: String
    var timestamp: String
    var model: String
    var usage: TokenUsageCounts
    var hasStopReason: Bool
    var lineNumber: Int
    var requestID: String?
    var responseID: String?
    var sessionID: String?
    var sourcePath: String

    var record: UsageRecord {
        UsageRecord(
            date: date,
            timestamp: timestamp,
            tool: "Claude Code",
            model: model,
            usage: usage,
            source: .nativeClaudeCode,
            requestID: requestID,
            sessionID: sessionID,
            responseID: responseID,
            sourcePath: sourcePath,
            lineNumber: lineNumber
        )
    }

    func isPreferred(over other: ClaudeUsageCandidate) -> Bool {
        if hasStopReason != other.hasStopReason {
            return hasStopReason
        }
        if timestamp != other.timestamp {
            return timestamp > other.timestamp
        }
        return lineNumber > other.lineNumber
    }
}

private struct TokenUsageCounts: Codable {
    var inputTokens = 0
    var outputTokens = 0
    var cacheCreationInputTokens = 0
    var cacheReadInputTokens = 0
    var reasoningOutputTokens = 0
    var totalTokens = 0

    mutating func add(_ other: TokenUsageCounts) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheCreationInputTokens += other.cacheCreationInputTokens
        cacheReadInputTokens += other.cacheReadInputTokens
        reasoningOutputTokens += other.reasoningOutputTokens
        totalTokens += other.totalTokens
    }
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
    var models: [String: Int] = [:]
    var totalTokens = 0
    var cost = 0.0

    mutating func add(record: UsageRecord, cost: Double) {
        tools[record.tool, default: 0] += record.usage.totalTokens
        models[record.model, default: 0] += record.usage.totalTokens
        totalTokens += record.usage.totalTokens
        self.cost += cost
    }
}

private struct RhythmAccumulator {
    var date: String
    var hourlyTokens = Array(repeating: 0, count: 24)

    mutating func add(tokens: Int, hour: Int) {
        guard tokens > 0, (0..<hourlyTokens.count).contains(hour) else { return }
        hourlyTokens[hour] += tokens
    }

    var dailyRhythm: DailyRhythm {
        let buckets = hourlyTokens.enumerated().map { hour, tokens in
            HourlyTokenBucket(hour: hour, tokens: tokens)
        }
        let totalTokens = hourlyTokens.reduce(0, +)
        let peak = hourlyTokens.enumerated().max { left, right in
            if left.element == right.element {
                return left.offset > right.offset
            }
            return left.element < right.element
        }
        let peakHour = (peak?.element ?? 0) > 0 ? peak?.offset : nil
        let peakTokens = peak?.element ?? 0
        let activeThreshold = Self.significantTokenThreshold(totalTokens: totalTokens, peakTokens: peakTokens)
        let significantHourlyTokens = hourlyTokens.map { $0 >= activeThreshold ? $0 : 0 }
        let activeHours = significantHourlyTokens.filter { $0 > 0 }.count
        let firstActiveHour = significantHourlyTokens.firstIndex { $0 > 0 }
        let lastActiveHour = significantHourlyTokens.lastIndex { $0 > 0 }
        let primaryTag = Self.classify(
            hourlyTokens: hourlyTokens,
            significantHourlyTokens: significantHourlyTokens,
            totalTokens: totalTokens,
            peakHour: peakHour,
            peakTokens: peakTokens,
            activeHours: activeHours,
            firstActiveHour: firstActiveHour
        )

        return DailyRhythm(
            date: date,
            buckets: buckets,
            totalTokens: totalTokens,
            peakHour: peakHour,
            peakTokens: peakTokens,
            activeHours: activeHours,
            firstActiveHour: firstActiveHour,
            lastActiveHour: lastActiveHour,
            primaryTag: primaryTag,
            companionTag: Self.companionTag(for: primaryTag)
        )
    }

    private static func classify(
        hourlyTokens: [Int],
        significantHourlyTokens: [Int],
        totalTokens: Int,
        peakHour: Int?,
        peakTokens: Int,
        activeHours: Int,
        firstActiveHour: Int?
    ) -> RhythmTag {
        guard totalTokens > 0 else { return .quietDay }
        let peakShare = share(peakTokens, of: totalTokens)
        if isDoublePeak(hourlyTokens: significantHourlyTokens, peakTokens: peakTokens) {
            return .doublePeak
        }
        if peakShare >= 0.50 {
            return .oneShot
        }

        let nightShare = share(tokens(in: [21, 22, 23, 0, 1, 2], hourlyTokens: significantHourlyTokens), of: totalTokens)
        if nightShare >= 0.35 || (peakHour.map { $0 >= 21 || $0 <= 2 } == true && nightShare >= 0.25) {
            return .nightAgent
        }

        let eveningShare = share(tokens(in: [19, 20], hourlyTokens: significantHourlyTokens), of: totalTokens)
        if peakHour.map({ (19...20).contains($0) }) == true || eveningShare >= 0.30 {
            return .eveningSprint
        }

        let afternoonShare = share(tokens(in: Array(14...18), hourlyTokens: significantHourlyTokens), of: totalTokens)
        if afternoonShare >= 0.35 || peakHour.map({ (14...18).contains($0) }) == true && afternoonShare >= 0.25 {
            return .afternoonBurst
        }

        let earlyShare = share(tokens(in: Array(5...9), hourlyTokens: significantHourlyTokens), of: totalTokens)
        if firstActiveHour.map({ $0 <= 8 }) == true && earlyShare >= 0.25 {
            return .earlyStarter
        }

        let morningShare = share(tokens(in: Array(8...12), hourlyTokens: significantHourlyTokens), of: totalTokens)
        if morningShare >= 0.35 || peakHour.map({ (8...12).contains($0) }) == true && morningShare >= 0.25 {
            return .morningPlanner
        }

        if activeHours >= 6 && peakShare < 0.35 {
            return .fragmented
        }
        if activeHours >= 4 {
            return .steadyCruise
        }
        return .quietDay
    }

    private static func companionTag(for tag: RhythmTag) -> RhythmTag {
        switch tag {
        case .earlyStarter:
            return .nightAgent
        case .morningPlanner:
            return .afternoonBurst
        case .afternoonBurst:
            return .morningPlanner
        case .eveningSprint:
            return .steadyCruise
        case .nightAgent:
            return .earlyStarter
        case .doublePeak:
            return .steadyCruise
        case .fragmented:
            return .oneShot
        case .oneShot:
            return .fragmented
        case .steadyCruise:
            return .doublePeak
        case .quietDay:
            return .morningPlanner
        }
    }

    private static func isDoublePeak(hourlyTokens: [Int], peakTokens: Int) -> Bool {
        guard peakTokens > 0 else { return false }
        let peaks = localPeakCandidates(hourlyTokens: hourlyTokens)
            .filter { Double($0.tokens) >= Double(peakTokens) * 0.45 }
            .sorted { $0.tokens > $1.tokens }
            .prefix(5)
        for left in peaks {
            for right in peaks where abs(left.hour - right.hour) >= 4 {
                return true
            }
        }
        return false
    }

    private static func localPeakCandidates(hourlyTokens: [Int]) -> [(hour: Int, tokens: Int)] {
        hourlyTokens.enumerated().compactMap { hour, tokens in
            guard tokens > 0 else { return nil }
            let previous = hour > 0 ? hourlyTokens[hour - 1] : 0
            let next = hour < hourlyTokens.count - 1 ? hourlyTokens[hour + 1] : 0
            guard tokens >= previous && tokens >= next else { return nil }
            return (hour, tokens)
        }
    }

    private static func tokens(in hours: [Int], hourlyTokens: [Int]) -> Int {
        hours.reduce(0) { total, hour in
            guard hourlyTokens.indices.contains(hour) else { return total }
            return total + hourlyTokens[hour]
        }
    }

    private static func share(_ value: Int, of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(value) / Double(total)
    }

    private static func significantTokenThreshold(totalTokens: Int, peakTokens: Int) -> Int {
        guard totalTokens > 0 else { return 1 }
        let totalBased = Double(totalTokens) * 0.03
        let peakBased = Double(peakTokens) * 0.30
        return max(1, Int(max(totalBased, peakBased).rounded()))
    }
}

private struct ModelKey: Hashable {
    var tool: String
    var model: String
}
