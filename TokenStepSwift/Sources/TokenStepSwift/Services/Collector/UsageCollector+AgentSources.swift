import Foundation

extension UsageCollector {
    static func collectCCSwitchProxyUsage(databaseURL: URL? = nil) -> CollectorResult {
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
        let inputSemanticsColumn = availableColumns.contains("input_token_semantics")
            ? "coalesce(input_token_semantics, 0)"
            : "0"
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
            \(inputSemanticsColumn) as input_token_semantics,
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

            let appType = row["app_type"] as? String
            let rawInputTokens = integerValue(row["input_tokens"] as Any)
            let cacheReadTokens = integerValue(row["cache_read_tokens"] as Any)
            let cacheCreationTokens = integerValue(row["cache_creation_tokens"] as Any)
            let freshInputTokens = ccSwitchFreshInputTokens(
                rawInputTokens: rawInputTokens,
                cacheReadTokens: cacheReadTokens,
                cacheCreationTokens: cacheCreationTokens,
                appType: appType,
                inputTokenSemantics: integerValue(row["input_token_semantics"] as Any)
            )
            let usage = canonicalUsageCounts(
                rawInputTokens: freshInputTokens,
                outputTokens: integerValue(row["output_tokens"] as Any),
                cacheCreationInputTokens: cacheCreationTokens,
                cacheReadInputTokens: cacheReadTokens,
                inputIncludesCachedTokens: false
            )
            guard usage.totalTokens > 0 else { return nil }

            return UsageRecord(
                date: day,
                timestamp: isoString(fromEpoch: row["created_at"] as Any),
                tool: ccSwitchToolName(appType: appType),
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

    static func collectZCodeUsage(databaseURL: URL? = nil) -> CollectorResult {
        let database = databaseURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zcode/cli/db/db.sqlite")

        guard FileManager.default.fileExists(atPath: database.path) else {
            return CollectorResult(records: [], source: SourceInfo(status: "missing_db", files: 0, records: 0))
        }
        guard FileManager.default.isReadableFile(atPath: database.path) else {
            return CollectorResult(records: [], source: SourceInfo(status: "unreadable_db", files: 1, records: 0))
        }
        guard let columns = sqliteJSONRows(database: database, query: "pragma table_info(model_usage)") else {
            return CollectorResult(records: [], source: SourceInfo(status: "schema_unreadable", files: 1, records: 0))
        }
        guard !columns.isEmpty else {
            return CollectorResult(records: [], source: SourceInfo(status: "missing_table", files: 1, records: 0))
        }

        let availableColumns = Set(columns.compactMap { $0["name"] as? String })
        let requiredColumns: Set<String> = [
            "id",
            "session_id",
            "status",
            "started_at",
            "model_id",
            "input_tokens",
            "output_tokens",
            "reasoning_tokens",
            "cache_creation_input_tokens",
            "cache_read_input_tokens",
            "computed_total_tokens",
            "tool_call_count"
        ]
        guard requiredColumns.isSubset(of: availableColumns) else {
            return CollectorResult(records: [], source: SourceInfo(status: "schema_mismatch", files: 1, records: 0))
        }

        let providerTotalExpression = availableColumns.contains("provider_total_tokens")
            ? "coalesce(provider_total_tokens, 0)"
            : "0"
        let query = """
        select
            id,
            session_id,
            started_at,
            coalesce(nullif(model_id, ''), 'unknown') as display_model,
            coalesce(input_tokens, 0) as input_tokens,
            coalesce(output_tokens, 0) as output_tokens,
            coalesce(reasoning_tokens, 0) as reasoning_tokens,
            coalesce(cache_creation_input_tokens, 0) as cache_creation_input_tokens,
            coalesce(cache_read_input_tokens, 0) as cache_read_input_tokens,
            coalesce(computed_total_tokens, 0) as computed_total_tokens,
            \(providerTotalExpression) as provider_total_tokens,
            coalesce(tool_call_count, 0) as tool_call_count
        from model_usage
        where status = 'completed'
            and (
                coalesce(computed_total_tokens, 0) > 0
                or \(providerTotalExpression) > 0
                or (
                    coalesce(input_tokens, 0)
                    + coalesce(output_tokens, 0)
                    + coalesce(reasoning_tokens, 0)
                    + coalesce(cache_creation_input_tokens, 0)
                    + coalesce(cache_read_input_tokens, 0)
                ) > 0
            )
        order by started_at, id
        """

        guard let rows = sqliteJSONRows(database: database, query: query) else {
            return CollectorResult(records: [], source: SourceInfo(status: "query_failed", files: 1, records: 0))
        }

        let records = rows.compactMap { row -> UsageRecord? in
            guard let day = dayString(fromEpoch: row["started_at"] as Any) else { return nil }
            let computedTotal = integerValue(row["computed_total_tokens"] as Any)
            let providerTotal = integerValue(row["provider_total_tokens"] as Any)
            let usage = canonicalUsageCounts(
                rawInputTokens: integerValue(row["input_tokens"] as Any),
                outputTokens: integerValue(row["output_tokens"] as Any),
                cacheCreationInputTokens: integerValue(row["cache_creation_input_tokens"] as Any),
                cacheReadInputTokens: integerValue(row["cache_read_input_tokens"] as Any),
                reasoningOutputTokens: integerValue(row["reasoning_tokens"] as Any),
                inputIncludesCachedTokens: true,
                explicitTotalTokens: computedTotal > 0 ? computedTotal : providerTotal
            )
            guard usage.totalTokens > 0 else { return nil }

            return UsageRecord(
                date: day,
                timestamp: isoString(fromEpoch: row["started_at"] as Any),
                tool: "ZCode",
                model: modelKey(row["display_model"] as? String),
                usage: usage,
                source: .zcode,
                requestID: nonEmptyString(row["id"] as? String),
                sessionID: nonEmptyString(row["session_id"] as? String),
                modelRequestCount: 1,
                toolCallCount: integerValue(row["tool_call_count"] as Any)
            )
        }

        return CollectorResult(
            records: records,
            source: SourceInfo(status: records.isEmpty ? "missing_valid_rows" : "ok", files: 1, records: records.count)
        )
    }

    static func collectHermesUsage(databaseURL: URL? = nil) -> CollectorResult {
        let database = databaseURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes/state.db")

        guard FileManager.default.fileExists(atPath: database.path) else {
            return CollectorResult(records: [], source: SourceInfo(status: "missing_db", files: 0, records: 0))
        }
        guard FileManager.default.isReadableFile(atPath: database.path) else {
            return CollectorResult(records: [], source: SourceInfo(status: "unreadable_db", files: 1, records: 0))
        }
        guard let columns = sqliteJSONRows(database: database, query: "pragma table_info(sessions)") else {
            return CollectorResult(records: [], source: SourceInfo(status: "schema_unreadable", files: 1, records: 0))
        }
        guard !columns.isEmpty else {
            return CollectorResult(records: [], source: SourceInfo(status: "missing_table", files: 1, records: 0))
        }

        let availableColumns = Set(columns.compactMap { $0["name"] as? String })
        let requiredColumns: Set<String> = [
            "id",
            "source",
            "model",
            "started_at",
            "input_tokens",
            "output_tokens",
            "cache_read_tokens",
            "cache_write_tokens",
            "reasoning_tokens",
            "tool_call_count",
            "api_call_count",
            "actual_cost_usd",
            "estimated_cost_usd",
            "cost_status"
        ]
        guard requiredColumns.isSubset(of: availableColumns) else {
            return CollectorResult(records: [], source: SourceInfo(status: "schema_mismatch", files: 1, records: 0))
        }

        let query = """
        select
            id,
            source,
            model,
            started_at,
            coalesce(input_tokens, 0) as input_tokens,
            coalesce(output_tokens, 0) as output_tokens,
            coalesce(cache_read_tokens, 0) as cache_read_tokens,
            coalesce(cache_write_tokens, 0) as cache_write_tokens,
            coalesce(reasoning_tokens, 0) as reasoning_tokens,
            coalesce(tool_call_count, 0) as tool_call_count,
            coalesce(api_call_count, 0) as api_call_count,
            coalesce(actual_cost_usd, 0) as actual_cost_usd,
            coalesce(estimated_cost_usd, 0) as estimated_cost_usd,
            coalesce(cost_status, '') as cost_status
        from sessions
        where (
            coalesce(input_tokens, 0)
            + coalesce(output_tokens, 0)
            + coalesce(cache_read_tokens, 0)
            + coalesce(cache_write_tokens, 0)
            + coalesce(reasoning_tokens, 0)
        ) > 0
        order by started_at, id
        """

        guard let rows = sqliteJSONRows(database: database, query: query) else {
            return CollectorResult(records: [], source: SourceInfo(status: "query_failed", files: 1, records: 0))
        }

        let records = rows.compactMap { row -> UsageRecord? in
            guard let day = dayString(fromEpoch: row["started_at"] as Any) else { return nil }
            let usage = canonicalUsageCounts(
                rawInputTokens: integerValue(row["input_tokens"] as Any),
                outputTokens: integerValue(row["output_tokens"] as Any),
                cacheCreationInputTokens: integerValue(row["cache_write_tokens"] as Any),
                cacheReadInputTokens: integerValue(row["cache_read_tokens"] as Any),
                reasoningOutputTokens: integerValue(row["reasoning_tokens"] as Any),
                inputIncludesCachedTokens: false
            )
            guard usage.totalTokens > 0 else { return nil }

            let actualCost = doubleValue(row["actual_cost_usd"] as Any)
            let estimatedCost = doubleValue(row["estimated_cost_usd"] as Any)
            let cost: Double?
            if actualCost > 0 {
                cost = actualCost
            } else if estimatedCost > 0 {
                cost = estimatedCost
            } else {
                cost = nil
            }
            let requestCount = integerValue(row["api_call_count"] as Any)

            return UsageRecord(
                date: day,
                timestamp: isoString(fromEpoch: row["started_at"] as Any),
                tool: "Hermes Agent",
                model: modelKey(row["model"] as? String),
                usage: usage,
                costUSD: cost,
                source: .hermes,
                requestID: nonEmptyString(row["id"] as? String),
                sessionID: nonEmptyString(row["id"] as? String),
                dataSource: nonEmptyString(row["source"] as? String),
                modelRequestCount: requestCount,
                toolCallCount: integerValue(row["tool_call_count"] as Any)
            )
        }

        return CollectorResult(
            records: records,
            source: SourceInfo(status: records.isEmpty ? "missing_valid_rows" : "ok", files: 1, records: records.count)
        )
    }

    static func collectWorkBuddyUsage(
        rootURLs: [URL]? = nil,
        modifiedSince cutoffDate: Date?
    ) -> CollectorResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = rootURLs ?? [
            home.appendingPathComponent(".workbuddy/projects", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/WorkBuddyExtension", isDirectory: true)
        ]
        let discoveredRoots = roots.filter { FileManager.default.fileExists(atPath: $0.path) }
        let files = discoveredRoots.flatMap { jsonlFiles(under: $0, modifiedSince: cutoffDate) }
        var records: [UsageRecord] = []

        for file in files {
            var lineNumber = 0
            try? forEachLine(in: file, matchingAny: ["\"usage\"", "\"rawUsage\""]) { line in
                lineNumber += 1
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let timestamp = object["timestamp"],
                      let day = dayString(fromEpoch: timestamp),
                      let usage = workBuddyUsage(from: object),
                      usage.totalTokens > 0
                else {
                    return
                }

                let providerData = object["providerData"] as? [String: Any]
                let recordType = object["type"] as? String
                records.append(UsageRecord(
                    date: day,
                    timestamp: isoString(fromEpoch: timestamp),
                    tool: "WorkBuddy",
                    model: modelKey(
                        providerData?["requestModelId"] as? String
                            ?? providerData?["requestModelName"] as? String
                            ?? providerData?["model"] as? String
                    ),
                    usage: usage,
                    source: .workbuddy,
                    requestID: nonEmptyString(providerData?["conversationRequestId"] as? String),
                    sessionID: nonEmptyString(object["sessionId"] as? String),
                    sourcePath: file.path,
                    lineNumber: lineNumber,
                    modelRequestCount: 1,
                    toolCallCount: recordType == "function_call" ? 1 : 0
                ))
            }
        }

        let status: String
        if discoveredRoots.isEmpty {
            status = "missing"
        } else if files.isEmpty {
            status = "discovered_no_usage"
        } else if records.isEmpty {
            status = "missing_valid_rows"
        } else {
            status = "ok"
        }
        return CollectorResult(
            records: records,
            source: SourceInfo(
                status: status,
                files: files.count,
                records: records.count
            )
        )
    }

    static func workBuddyUsage(from object: [String: Any]) -> TokenUsageCounts? {
        let message = object["message"] as? [String: Any]
        let providerData = object["providerData"] as? [String: Any]
        let usage = message?["usage"] as? [String: Any]
            ?? providerData?["rawUsage"] as? [String: Any]
            ?? providerData?["usage"] as? [String: Any]
        guard let usage else { return nil }

        let rawInput = firstIntegerValue(
            in: usage,
            keys: ["input_tokens", "inputTokens", "prompt_tokens"]
        )
        let output = firstIntegerValue(
            in: usage,
            keys: ["output_tokens", "outputTokens", "completion_tokens"]
        )
        let cacheRead = firstIntegerValue(
            in: usage,
            keys: ["cache_read_input_tokens", "cached_tokens", "prompt_cache_hit_tokens"]
        )
        let reasoning = firstIntegerValue(
            in: usage,
            keys: ["reasoning_tokens", "completion_thinking_tokens"]
        )
        let explicitTotal = firstIntegerValue(
            in: usage,
            keys: ["total_tokens", "totalTokens"]
        )
        return canonicalUsageCounts(
            rawInputTokens: rawInput,
            outputTokens: output,
            cacheReadInputTokens: cacheRead,
            reasoningOutputTokens: reasoning,
            inputIncludesCachedTokens: true,
            explicitTotalTokens: explicitTotal,
            explicitTotalIsAuthoritative: true
        )
    }

    static func firstIntegerValue(in object: [String: Any], keys: [String]) -> Int {
        for key in keys where object.keys.contains(key) {
            return max(0, integerValue(object[key] as Any))
        }
        return 0
    }

    static func ccSwitchToolName(appType: String?) -> String {
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

    static func ccSwitchFreshInputTokens(
        rawInputTokens: Int,
        cacheReadTokens: Int,
        cacheCreationTokens: Int,
        appType: String?,
        inputTokenSemantics: Int
    ) -> Int {
        let rawInput = max(0, rawInputTokens)
        let cacheRead = max(0, cacheReadTokens)
        let cacheCreation = max(0, cacheCreationTokens)
        let normalizedAppType = (appType ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let cacheInclusiveAppTypes: Set<String> = ["codex", "gemini", "grokbuild"]
        guard cacheInclusiveAppTypes.contains(normalizedAppType) else {
            return rawInput
        }

        switch inputTokenSemantics {
        case 2:
            // FRESH: input excludes both cache-read and cache-write buckets.
            return rawInput
        case 1 where rawInput >= cacheRead + cacheCreation:
            // TOTAL: input already includes both cache buckets.
            return rawInput - cacheRead - cacheCreation
        case 0 where rawInput >= cacheRead:
            // LEGACY: cache reads were included, cache writes were separate.
            return rawInput - cacheRead
        default:
            // Malformed or future semantics stay conservative instead of going negative.
            return rawInput
        }
    }
}
