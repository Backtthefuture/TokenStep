import Foundation

extension UsageCollector {
    static func collectCodex(
        cache: inout CollectorCache,
        livePaths: inout Set<String>,
        modifiedSince cutoffDate: Date?,
        databaseURL: URL,
        forceFullValidation: Bool,
        requiresDetailedRecords: Bool,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> CodexCollectionOutcome {
        func runIncremental() throws -> CollectorResult {
            try collectCodexIncrementally(
                modifiedSince: cutoffDate,
                databaseURL: databaseURL,
                forceFullValidation: forceFullValidation,
                homeURL: homeURL,
                requiresDetailedRecords: requiresDetailedRecords,
                legacyCache: cache
            )
        }

        do {
            let incremental = try runIncremental()
            if incremental.source.status == "ok" {
                return CodexCollectionOutcome(result: incremental, usedIncrementalStore: true)
            }
        } catch {
            if let cacheError = error as? CodexIncrementalStoreError,
               cacheError.shouldRebuildCache {
                CodexIncrementalStore.discardDatabase(at: databaseURL)
                if let rebuilt = try? runIncremental(), rebuilt.source.status == "ok" {
                    return CodexCollectionOutcome(result: rebuilt, usedIncrementalStore: true)
                }
            }
        }

        let jsonlResult = collectCodexFromJSONL(
            cache: &cache,
            livePaths: &livePaths,
            modifiedSince: cutoffDate,
            homeURL: homeURL
        )
        if jsonlResult.source.status == "ok" {
            return CodexCollectionOutcome(result: jsonlResult, usedIncrementalStore: false)
        }
        return CodexCollectionOutcome(
            result: collectCodexFromSQLite() ?? jsonlResult,
            usedIncrementalStore: false
        )
    }

    static func collectCodexIncrementally(
        modifiedSince cutoffDate: Date?,
        databaseURL: URL,
        forceFullValidation: Bool,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        requiresDetailedRecords: Bool = false,
        legacyCache: CollectorCache? = nil,
        roots: [URL]? = nil
    ) throws -> CollectorResult {
        let paths = (roots ?? defaultCodexSessionRoots(homeURL: homeURL))
            .flatMap { jsonlFiles(under: $0, modifiedSince: cutoffDate) }
            .sorted { $0.path < $1.path }
        guard !paths.isEmpty else {
            return CollectorResult(
                records: [],
                source: SourceInfo(status: "missing", files: 0, records: 0)
            )
        }

        let store = try CodexIncrementalStore(url: databaseURL)
        let storedMetadata = try store.metadataByPath()
        let currentPaths = Set(paths.map(\.path))
        let deletedPaths = Set(storedMetadata.keys).subtracting(currentPaths)
        var fullyAffectedParentIDs = Set(
            deletedPaths.compactMap { storedMetadata[$0]?.sessionID }
        )
        var appendedParentAnchorThresholds = [String: TimeInterval]()
        var stagedPaths = Set<String>()
        try store.beginStaging()
        var committed = false
        defer {
            if !committed {
                store.abortStaging()
            }
        }

        func validatedScan(
            at path: URL,
            metadata: (size: UInt64, modificationTime: TimeInterval)
        ) throws -> PendingCodexSession {
            if !forceFullValidation,
               let legacyCache,
               let scan = cachedCodexScan(for: path, cache: legacyCache),
               let fingerprint = contentFingerprint(for: path, size: metadata.size) {
                return PendingCodexSession(
                    path: path,
                    metadata: metadata,
                    fingerprint: fingerprint,
                    scan: scan
                )
            }

            guard var stable = stableCodexScan(at: path) else {
                throw CodexIncrementalStoreError.unstableSource(path.path)
            }
            if !stable.isStable, let retry = stableCodexScan(at: path) {
                stable = retry
            }
            guard stable.isStable,
                  let fingerprint = contentFingerprint(for: path, size: stable.metadata.size)
            else {
                throw CodexIncrementalStoreError.unstableSource(path.path)
            }
            return PendingCodexSession(
                path: path,
                metadata: stable.metadata,
                fingerprint: fingerprint,
                scan: stable.scan
            )
        }

        for path in paths {
            guard let metadata = fileMetadata(for: path) else { continue }
            let stored = storedMetadata[path.path]
            var validatedFullFingerprint: String?
            let metadataMatches = stored?.size == metadata.size
                && abs((stored?.modificationTime ?? -1) - metadata.modificationTime) < 0.001
            if metadataMatches {
                if !forceFullValidation {
                    continue
                }
                let fingerprint = contentFingerprint(for: path, size: metadata.size)
                if fingerprint == stored?.fingerprint {
                    guard let fullFingerprint = fullContentFingerprint(
                        for: path,
                        size: metadata.size
                    ),
                    let afterValidation = fileMetadata(for: path),
                    UsageCollector.metadata(metadata, matches: afterValidation)
                    else {
                        throw CodexIncrementalStoreError.unstableSource(path.path)
                    }
                    if fullFingerprint == stored?.validationFingerprint {
                        continue
                    }
                    validatedFullFingerprint = fullFingerprint
                }
            }

            if !forceFullValidation,
               let stored,
               metadata.size > stored.size,
               contentFingerprint(for: path, size: stored.size) == stored.fingerprint,
               let cachedSession = try store.session(path: path.path),
               let appended = incrementalCodexAppend(at: path, cached: cachedSession) {
                try store.stage(session: appended)
                if let earliestNewAnchor = appended.anchors
                    .dropFirst(cachedSession.anchors.count)
                    .first?.timestamp {
                    appendedParentAnchorThresholds[appended.sessionID] = min(
                        appendedParentAnchorThresholds[appended.sessionID] ?? earliestNewAnchor,
                        earliestNewAnchor
                    )
                }
                continue
            }

            var pending = try validatedScan(at: path, metadata: metadata)
            if validatedFullFingerprint != nil {
                pending.validationFingerprint = validatedFullFingerprint
            } else if forceFullValidation, stored != nil, metadataMatches {
                guard let fullFingerprint = fullContentFingerprint(
                    for: path,
                    size: pending.metadata.size
                ),
                let afterValidation = fileMetadata(for: path),
                UsageCollector.metadata(pending.metadata, matches: afterValidation)
                else {
                    throw CodexIncrementalStoreError.unstableSource(path.path)
                }
                pending.validationFingerprint = fullFingerprint
            }
            try store.stage(
                scan: pending,
                anchors: codexAnchors(for: pending.scan),
                createdAtEpoch: pending.scan.createdAt.flatMap(parseISO)?.timeIntervalSince1970
            )
            stagedPaths.insert(path.path)
            fullyAffectedParentIDs.insert(pending.scan.canonicalSessionID)
            if let previousID = stored?.sessionID {
                fullyAffectedParentIDs.insert(previousID)
            }
        }

        func stageChild(at childPath: String) throws {
            guard currentPaths.contains(childPath), !stagedPaths.contains(childPath) else { return }
            let url = URL(fileURLWithPath: childPath)
            guard let metadata = fileMetadata(for: url) else {
                throw CodexIncrementalStoreError.unstableSource(childPath)
            }
            var pending = try validatedScan(at: url, metadata: metadata)
            if let stored = storedMetadata[childPath],
               stored.size == metadata.size,
               abs(stored.modificationTime - metadata.modificationTime) < 0.001,
               contentFingerprint(for: url, size: metadata.size) == stored.fingerprint {
                pending.validationFingerprint = stored.validationFingerprint
            }
            try store.stage(
                scan: pending,
                anchors: codexAnchors(for: pending.scan),
                createdAtEpoch: pending.scan.createdAt.flatMap(parseISO)?.timeIntervalSince1970
            )
            stagedPaths.insert(childPath)
        }

        for parentID in fullyAffectedParentIDs {
            for childPath in try store.childPaths(parentSessionID: parentID) {
                try stageChild(at: childPath)
            }
        }
        for (parentID, earliestNewAnchor) in appendedParentAnchorThresholds
        where !fullyAffectedParentIDs.contains(parentID) {
            for childPath in try store.childPaths(
                parentSessionID: parentID,
                createdAtOnOrAfter: earliestNewAnchor
            ) {
                try stageChild(at: childPath)
            }
        }

        for stagedPath in try store.stagedScanPaths() {
            guard let item = try store.stagedScan(path: stagedPath) else {
                throw CodexIncrementalStoreError.sqlite("missing staged scan for \(stagedPath)")
            }
            let parentAnchors: [CodexAnchor]?
            if let parentID = item.scan.parentSessionID {
                if let pendingParent = try store.stagedAnchors(sessionID: parentID) {
                    parentAnchors = pendingParent
                } else {
                    parentAnchors = try store.anchors(sessionID: parentID)
                }
            } else {
                parentAnchors = nil
            }
            let childCreatedAt = item.scan.createdAt.flatMap(parseISO)?.timeIntervalSince1970
            let parentAnchor = childCreatedAt.flatMap { timestamp in
                parentAnchors.flatMap { codexAnchor(atOrBefore: timestamp, anchors: $0) }
            }
            var seenRequestIDs = Set<String>()
            let result = codexDeltaRecords(
                from: item.scan,
                parentAnchor: parentAnchor,
                seenRequestIDs: &seenRequestIDs
            )
            let candidate = CodexCachedSession(
                    path: item.path.path,
                    size: item.metadata.size,
                    modificationTime: item.metadata.modificationTime,
                    fingerprint: item.fingerprint,
                    validationFingerprint: item.validationFingerprint,
                    sessionID: item.scan.canonicalSessionID,
                    createdAtEpoch: childCreatedAt,
                    parentSessionID: item.scan.parentSessionID,
                    anchors: try store.stagedAnchors(
                        sessionID: item.scan.canonicalSessionID
                    ) ?? [],
                    records: result.records,
                    summaryRecords: summarizeCodexRecords(result.records),
                    cursor: CodexSessionCursor(
                        currentModel: item.scan.finalModel ?? item.scan.events.last?.model ?? "unknown",
                        relevantLineNumber: item.scan.relevantLineCount ?? item.scan.events.count,
                        hasCumulativeSchema: result.cursor.hasCumulativeSchema,
                        previousCumulative: result.cursor.previousCumulative,
                        epoch: result.cursor.epoch
                    ),
                    diagnostics: result.diagnostics
                )
            if let existing = try store.session(path: item.path.path),
               candidate.hasSameStoredAccounting(as: existing) {
                if let validationFingerprint = candidate.validationFingerprint,
                   validationFingerprint != existing.validationFingerprint {
                    try store.updateValidationFingerprint(
                        validationFingerprint,
                        path: item.path.path
                    )
                }
            } else {
                try store.stage(session: candidate)
            }
        }

        try store.commitStaged(deletedPaths: deletedPaths)
        committed = true
        let cachedSessionCount = try store.sessionCount()
        guard cachedSessionCount == paths.count else {
            throw CodexIncrementalStoreError.incompleteCache(
                expected: paths.count,
                actual: cachedSessionCount
            )
        }

        var seenRequestIDs = Set<String>()
        var records = [UsageRecord]()
        var summaries = [CodexSummaryKey: CodexSummaryAccumulator]()
        var diagnostics = CodexCollectionDiagnostics()
        var sourceRecordCount = 0
        try store.forEachContribution(detailed: requiresDetailedRecords) { contribution in
            sourceRecordCount += contribution.recordCount
            diagnostics.add(contribution.diagnostics)
            for record in contribution.records {
                if let requestID = record.requestID,
                   !seenRequestIDs.insert(requestID).inserted {
                    diagnostics.duplicateRecords += 1
                    continue
                }
                if requiresDetailedRecords {
                    records.append(record)
                } else {
                    addCodexSummary(record, to: &summaries)
                }
            }
        }
        if !requiresDetailedRecords {
            records = codexSummaryRecords(summaries)
        }
        return codexCollectorResult(
            records: records,
            diagnostics: diagnostics,
            fileCount: paths.count,
            sourceRecordCount: sourceRecordCount
        )
    }

    static func collectCodexFromSQLite() -> CollectorResult? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".codex/state_5.sqlite"),
            home.appendingPathComponent(".codex/sqlite/state_5.sqlite")
        ]
        guard let database = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return nil
        }

        // Route through SQLiteReadonly: it streams sqlite3 output to a file, so large
        // result sets cannot fill a pipe buffer and deadlock the child process.
        let query = "select created_at, model, tokens_used from threads where tokens_used > 0"
        guard let rows = sqliteJSONRows(database: database, query: query) else {
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

    static func collectCodexFromJSONL(
        cache: inout CollectorCache,
        livePaths: inout Set<String>,
        modifiedSince cutoffDate: Date?,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        roots: [URL]? = nil
    ) -> CollectorResult {
        let roots = roots ?? defaultCodexSessionRoots(homeURL: homeURL)
        let paths = roots
            .flatMap { jsonlFiles(under: $0, modifiedSince: cutoffDate) }
            .sorted { $0.path < $1.path }
        var scans: [CodexSessionScan] = []

        for path in paths {
            livePaths.insert(path.path)
            if let cached = cachedCodexScan(for: path, cache: cache) {
                scans.append(cached)
                continue
            }

            guard var result = stableCodexScan(at: path) else { continue }
            if !result.isStable, let retry = stableCodexScan(at: path) {
                result = retry
            }
            scans.append(result.scan)
            if result.isStable {
                updateCodexCache(path: path, scan: result.scan, metadata: result.metadata, cache: &cache)
            }
        }

        let scansBySessionID = Dictionary(
            scans.map { ($0.canonicalSessionID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let anchorsBySessionID = scansBySessionID.mapValues(codexAnchors)
        var records: [UsageRecord] = []
        var diagnostics = CodexCollectionDiagnostics()
        var seenRequestIDs = Set<String>()
        for scan in scans.sorted(by: { $0.sourcePath < $1.sourcePath }) {
            let parentAnchor = codexForkAnchor(for: scan, anchorsBySessionID: anchorsBySessionID)
            let result = codexDeltaRecords(
                from: scan,
                parentAnchor: parentAnchor,
                seenRequestIDs: &seenRequestIDs
            )
            records.append(contentsOf: result.records)
            diagnostics.add(result.diagnostics)
        }

        return codexCollectorResult(
            records: records,
            diagnostics: diagnostics,
            fileCount: paths.count
        )
    }

    static func codexCollectorResult(
        records: [UsageRecord],
        diagnostics: CodexCollectionDiagnostics,
        fileCount: Int,
        sourceRecordCount: Int? = nil
    ) -> CollectorResult {
        let breakdown = records.reduce(into: TokenUsageCounts()) { partial, record in
            partial.add(record.usage)
        }
        return CollectorResult(
            records: records,
            source: SourceInfo(
                status: records.isEmpty ? "missing" : "ok",
                files: fileCount,
                records: sourceRecordCount ?? records.count,
                rawRecords: diagnostics.rawRecords,
                dedupedRecords: diagnostics.duplicateRecords + diagnostics.inheritedRecords,
                skippedRecords: diagnostics.skippedRecords,
                strategy: "total_token_usage_delta_v6_with_incremental_cache",
                exactRecords: diagnostics.exactRecords,
                legacyRecords: diagnostics.legacyRecords,
                duplicateRecords: diagnostics.duplicateRecords,
                counterResets: diagnostics.counterResets,
                inheritedRecords: diagnostics.inheritedRecords,
                inheritedTokens: diagnostics.inheritedTokens,
                unknownBreakdownRecords: diagnostics.unknownBreakdownRecords,
                accountingRevision: codexAccountingRevision,
                tokenBreakdown: SourceTokenBreakdown(
                    processedTokens: breakdown.totalTokens,
                    inputTokens: breakdown.inputTokens,
                    cachedInputTokens: breakdown.cacheReadInputTokens,
                    uncachedInputTokens: max(
                        0,
                        breakdown.inputTokens
                            - breakdown.cacheReadInputTokens
                            - breakdown.cacheCreationInputTokens
                    ),
                    outputTokens: breakdown.outputTokens,
                    reasoningTokens: breakdown.reasoningOutputTokens
                )
            )
        )
    }

    static func summarizeCodexRecords(_ records: [UsageRecord]) -> [UsageRecord] {
        var summaries = [CodexSummaryKey: CodexSummaryAccumulator]()
        for record in records {
            addCodexSummary(record, to: &summaries)
        }
        return codexSummaryRecords(summaries)
    }

    static func addCodexSummary(
        _ record: UsageRecord,
        to summaries: inout [CodexSummaryKey: CodexSummaryAccumulator]
    ) {
        let hour = record.timestampEpoch.map(hour(fromEpoch:))
            ?? hour(fromISO: record.timestamp)
        let key = CodexSummaryKey(date: record.date, model: record.model, hour: hour)
        summaries[key, default: CodexSummaryAccumulator()].add(record)
    }

    static func codexSummaryRecords(
        _ summaries: [CodexSummaryKey: CodexSummaryAccumulator]
    ) -> [UsageRecord] {
        summaries.map { key, value in
            UsageRecord(
                date: key.date,
                timestamp: value.timestamp,
                timestampEpoch: value.timestampEpoch,
                tool: "Codex",
                model: key.model,
                usage: value.usage,
                source: .nativeCodex,
                dataSource: "codex_incremental_summary",
                modelRequestCount: value.modelRequestCount,
                toolCallCount: value.toolCallCount
            )
        }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.model != $1.model { return $0.model < $1.model }
            return ($0.timestampEpoch ?? -1) < ($1.timestampEpoch ?? -1)
        }
    }

    static func stableCodexScan(
        at path: URL
    ) -> (scan: CodexSessionScan, isStable: Bool, metadata: (size: UInt64, modificationTime: TimeInterval))? {
        guard let before = fileMetadata(for: path),
              let scan = scanCodexSessionFile(at: path),
              let after = fileMetadata(for: path)
        else {
            return nil
        }
        return (scan, metadata(before, matches: after), after)
    }

    static func incrementalCodexAppend(
        at path: URL,
        cached: CodexCachedSession
    ) -> CodexCachedSession? {
        guard let tail = scanCodexSessionTail(
            at: path,
            fromOffset: cached.size,
            cursor: cached.cursor
        ) else {
            return nil
        }

        var records = cached.records
        var diagnostics = cached.diagnostics
        var cursor = cached.cursor
        diagnostics.rawRecords += tail.events.count
        var seenRequestIDs = Set(records.compactMap(\.requestID))
        let scan = CodexSessionScan(
            canonicalSessionID: cached.sessionID,
            createdAt: cached.createdAtEpoch.map { isoFormatter.string(from: Date(timeIntervalSince1970: $0)) },
            parentSessionID: cached.parentSessionID,
            sourcePath: cached.path,
            events: tail.events,
            finalModel: tail.currentModel,
            relevantLineCount: tail.relevantLineNumber
        )

        if cursor.hasCumulativeSchema {
            var previous = cursor.previousCumulative
            var epoch = cursor.epoch
            for index in tail.events.indices {
                let event = tail.events[index]
                guard event.cumulativePresent else {
                    diagnostics.skippedRecords += 1
                    continue
                }
                guard let current = event.cumulative,
                      current.totalTokens > 0,
                      let day = dayString(for: event)
                else {
                    diagnostics.skippedRecords += 1
                    continue
                }

                let deltaTotal: Int
                let isReset: Bool
                if let previous {
                    if current.totalTokens == previous.totalTokens {
                        diagnostics.duplicateRecords += 1
                        continue
                    }
                    if current.totalTokens > previous.totalTokens {
                        deltaTotal = current.totalTokens - previous.totalTokens
                        isReset = false
                    } else if isCodexContextWindowSentinel(event) {
                        diagnostics.skippedRecords += 1
                        continue
                    } else if isCredibleCodexReset(
                        at: index,
                        events: tail.events,
                        current: current,
                        previous: previous
                    ) {
                        epoch += 1
                        diagnostics.counterResets += 1
                        deltaTotal = current.totalTokens
                        isReset = true
                    } else {
                        // Re-read the complete session so an ambiguous reset can be
                        // reconsidered when a following cumulative event arrives.
                        return nil
                    }
                } else {
                    deltaTotal = current.totalTokens
                    isReset = false
                }

                guard deltaTotal > 0 else { continue }
                let componentResult = codexIncrementUsage(
                    current: current,
                    previous: isReset ? nil : previous,
                    last: event.last,
                    total: deltaTotal
                )
                let requestID = "codex:cumulative:\(cached.sessionID):\(epoch):\(current.totalTokens)"
                guard seenRequestIDs.insert(requestID).inserted else {
                    diagnostics.duplicateRecords += 1
                    previous = current
                    continue
                }
                records.append(
                    codexUsageRecord(
                        scan: scan,
                        event: event,
                        day: day,
                        usage: componentResult.usage,
                        requestID: requestID,
                        dataSource: componentResult.hasKnownBreakdown
                            ? "codex_total_usage_delta"
                            : "codex_total_usage_delta_unknown_breakdown"
                    )
                )
                diagnostics.exactRecords += 1
                if !componentResult.hasKnownBreakdown {
                    diagnostics.unknownBreakdownRecords += 1
                }
                previous = current
            }
            cursor.previousCumulative = previous
            cursor.epoch = epoch
        } else {
            guard !tail.events.contains(where: \.cumulativePresent) else {
                return nil
            }
            for event in tail.events {
                guard let usage = event.last,
                      usage.totalTokens > 0,
                      let timestamp = event.timestamp,
                      let day = dayString(for: event)
                else {
                    diagnostics.skippedRecords += 1
                    continue
                }
                let requestID = "codex:legacy:\(cached.sessionID):\(timestamp):\(usage.fingerprint)"
                guard seenRequestIDs.insert(requestID).inserted else {
                    diagnostics.duplicateRecords += 1
                    continue
                }
                records.append(
                    codexUsageRecord(
                        scan: scan,
                        event: event,
                        day: day,
                        usage: usage,
                        requestID: requestID,
                        dataSource: "codex_last_usage_legacy_estimate"
                    )
                )
                diagnostics.legacyRecords += 1
                if !isCodexBreakdownConsistent(usage, total: usage.totalTokens) {
                    diagnostics.unknownBreakdownRecords += 1
                }
            }
        }

        cursor.currentModel = tail.currentModel
        cursor.relevantLineNumber = tail.relevantLineNumber
        return CodexCachedSession(
            path: cached.path,
            size: tail.processedSize,
            modificationTime: tail.modificationTime,
            fingerprint: tail.fingerprint,
            validationFingerprint: nil,
            sessionID: cached.sessionID,
            createdAtEpoch: cached.createdAtEpoch,
            parentSessionID: cached.parentSessionID,
            anchors: (cached.anchors + codexAnchors(for: scan))
                .sorted { $0.timestamp < $1.timestamp },
            records: records,
            summaryRecords: summarizeCodexRecords(records),
            cursor: cursor,
            diagnostics: diagnostics
        )
    }

    static func scanCodexSessionTail(
        at path: URL,
        fromOffset offset: UInt64,
        cursor: CodexSessionCursor
    ) -> CodexSessionTail? {
        guard let metadata = fileMetadata(for: path), metadata.size > offset else { return nil }

        do {
            if offset > 0 {
                let handle = try FileHandle(forReadingFrom: path)
                defer { try? handle.close() }
                try handle.seek(toOffset: offset - 1)
                guard try handle.read(upToCount: 1)?.first == 0x0A else { return nil }
            }

            var currentModel = cursor.currentModel
            var relevantLineNumber = cursor.relevantLineNumber
            var events = [CodexTokenEvent]()
            var encounteredSessionMetadata = false
            let processedSize = try forEachCompleteLine(
                in: path,
                fromOffset: offset,
                matchingAny: ["session_meta", "turn_context", "token_count"]
            ) { line in
                autoreleasepool {
                    relevantLineNumber += 1
                    guard line.utf8.count <= maxRelevantLineBytes,
                          let obj = jsonObject(line)
                    else { return }
                    let type = obj["type"] as? String
                    let payload = obj["payload"] as? [String: Any]
                    if type == "session_meta" {
                        encounteredSessionMetadata = true
                        return
                    }
                    if type == "turn_context" {
                        currentModel = modelKey(payload?["model"] as? String ?? currentModel)
                    }
                    guard type == "event_msg",
                          payload?["type"] as? String == "token_count",
                          let info = payload?["info"] as? [String: Any]
                    else { return }
                    let timestamp = nonEmptyString(obj["timestamp"] as? String)
                    events.append(
                        CodexTokenEvent(
                            timestamp: timestamp,
                            timestampEpoch: timestamp.flatMap(parseISO)?.timeIntervalSince1970,
                            model: currentModel,
                            cumulativePresent: info.keys.contains("total_token_usage"),
                            cumulative: (info["total_token_usage"] as? [String: Any]).map(normalizeCodexUsage),
                            last: (info["last_token_usage"] as? [String: Any]).map(normalizeCodexUsage),
                            modelContextWindow: integerValue(info["model_context_window"] as Any),
                            lineNumber: relevantLineNumber
                        )
                    )
                }
            }

            guard processedSize > offset, !encounteredSessionMetadata else { return nil }
            guard let finalMetadata = fileMetadata(for: path),
                  let fingerprint = contentFingerprint(for: path, size: processedSize)
            else { return nil }
            return CodexSessionTail(
                events: events,
                currentModel: currentModel,
                relevantLineNumber: relevantLineNumber,
                processedSize: processedSize,
                modificationTime: finalMetadata.modificationTime,
                fingerprint: fingerprint
            )
        } catch {
            return nil
        }
    }

    static func scanCodexSessionFile(at path: URL) -> CodexSessionScan? {
        guard FileManager.default.isReadableFile(atPath: path.path) else { return nil }
        var canonicalSessionID: String?
        var createdAt: String?
        var parentSessionID: String?
        var currentModel = "unknown"
        var events: [CodexTokenEvent] = []
        var relevantLineNumber = 0

        do {
            try forEachLine(in: path, matchingAny: ["session_meta", "turn_context", "token_count"]) { line in
                autoreleasepool {
                    relevantLineNumber += 1
                    guard let obj = jsonObject(line) else { return }
                    let type = obj["type"] as? String
                    let payload = obj["payload"] as? [String: Any]

                    if type == "session_meta", canonicalSessionID == nil,
                       let id = nonEmptyString(payload?["id"] as? String) {
                        canonicalSessionID = id
                        createdAt = nonEmptyString(obj["timestamp"] as? String)
                            ?? nonEmptyString(payload?["timestamp"] as? String)
                        parentSessionID = codexParentSessionID(from: payload)
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

                    let timestamp = nonEmptyString(obj["timestamp"] as? String)
                    let cumulativePresent = info.keys.contains("total_token_usage")
                    let cumulative = (info["total_token_usage"] as? [String: Any]).map(normalizeCodexUsage)
                    let last = (info["last_token_usage"] as? [String: Any]).map(normalizeCodexUsage)
                    events.append(
                        CodexTokenEvent(
                            timestamp: timestamp,
                            timestampEpoch: timestamp.flatMap(parseISO)?.timeIntervalSince1970,
                            model: currentModel,
                            cumulativePresent: cumulativePresent,
                            cumulative: cumulative,
                            last: last,
                            modelContextWindow: integerValue(info["model_context_window"] as Any),
                            lineNumber: relevantLineNumber
                        )
                    )
                }
            }
        } catch {
            return nil
        }

        return CodexSessionScan(
            canonicalSessionID: canonicalSessionID ?? path.deletingPathExtension().lastPathComponent,
            createdAt: createdAt,
            parentSessionID: parentSessionID,
            sourcePath: path.path,
            events: events,
            finalModel: currentModel,
            relevantLineCount: relevantLineNumber
        )
    }

    static func codexParentSessionID(from payload: [String: Any]?) -> String? {
        if let source = payload?["source"] as? [String: Any],
           let subagent = source["subagent"] as? [String: Any],
           let threadSpawn = subagent["thread_spawn"] as? [String: Any],
           let parent = nonEmptyString(threadSpawn["parent_thread_id"] as? String) {
            return parent
        }
        return [
            payload?["parent_thread_id"] as? String,
            payload?["forked_from_id"] as? String
        ].compactMap(nonEmptyString).first
    }

    static func codexForkAnchor(
        for scan: CodexSessionScan,
        anchorsBySessionID: [String: [CodexAnchor]]
    ) -> TokenUsageCounts? {
        guard let parentID = scan.parentSessionID,
              let anchors = anchorsBySessionID[parentID],
              let childCreatedAt = scan.createdAt.flatMap(parseISO)?.timeIntervalSince1970
        else {
            return nil
        }
        return codexAnchor(atOrBefore: childCreatedAt, anchors: anchors)
    }

    static func codexAnchors(for scan: CodexSessionScan) -> [CodexAnchor] {
        scan.events.compactMap { event in
            guard event.cumulativePresent,
                  let usage = event.cumulative,
                  usage.totalTokens > 0,
                  let timestamp = event.timestampEpoch
                    ?? event.timestamp.flatMap(parseISO)?.timeIntervalSince1970
            else {
                return nil
            }
            return CodexAnchor(timestamp: timestamp, usage: usage)
        }.sorted { $0.timestamp < $1.timestamp }
    }

    static func codexAnchor(
        atOrBefore timestamp: TimeInterval,
        anchors: [CodexAnchor]
    ) -> TokenUsageCounts? {
        var lower = 0
        var upper = anchors.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if anchors[middle].timestamp <= timestamp {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower > 0 else { return nil }
        return anchors[lower - 1].usage
    }

    static func codexDeltaRecords(
        from scan: CodexSessionScan,
        parentAnchor: TokenUsageCounts?,
        seenRequestIDs: inout Set<String>
    ) -> (
        records: [UsageRecord],
        diagnostics: CodexCollectionDiagnostics,
        cursor: CodexDeltaCursor
    ) {
        var diagnostics = CodexCollectionDiagnostics(rawRecords: scan.events.count)
        var records: [UsageRecord] = []
        let hasCumulativeSchema = scan.events.contains { $0.cumulativePresent }

        if !hasCumulativeSchema {
            for event in scan.events {
                guard let usage = event.last,
                      usage.totalTokens > 0,
                      let timestamp = event.timestamp,
                      let day = dayString(for: event)
                else {
                    diagnostics.skippedRecords += 1
                    continue
                }
                let requestID = "codex:legacy:\(scan.canonicalSessionID):\(timestamp):\(usage.fingerprint)"
                guard seenRequestIDs.insert(requestID).inserted else {
                    diagnostics.duplicateRecords += 1
                    continue
                }
                records.append(
                    codexUsageRecord(
                        scan: scan,
                        event: event,
                        day: day,
                        usage: usage,
                        requestID: requestID,
                        dataSource: "codex_last_usage_legacy_estimate"
                    )
                )
                diagnostics.legacyRecords += 1
                if !isCodexBreakdownConsistent(usage, total: usage.totalTokens) {
                    diagnostics.unknownBreakdownRecords += 1
                }
            }
            return (
                records,
                diagnostics,
                CodexDeltaCursor(
                    hasCumulativeSchema: false,
                    previousCumulative: nil,
                    epoch: 0
                )
            )
        }

        var startIndex = 0
        var previous: TokenUsageCounts?
        if let parentAnchor,
           parentAnchor.totalTokens > 0,
           let anchorIndex = scan.events.firstIndex(where: {
               $0.cumulativePresent && $0.cumulative == parentAnchor
           }) {
            previous = parentAnchor
            startIndex = anchorIndex + 1
            diagnostics.inheritedRecords = scan.events[...anchorIndex].filter(\.cumulativePresent).count
            diagnostics.inheritedTokens = parentAnchor.totalTokens
        }

        var epoch = 0
        for index in startIndex..<scan.events.count {
            let event = scan.events[index]
            guard event.cumulativePresent else {
                diagnostics.skippedRecords += 1
                continue
            }
            guard let current = event.cumulative,
                  current.totalTokens > 0,
                  let day = dayString(for: event)
            else {
                diagnostics.skippedRecords += 1
                continue
            }

            let deltaTotal: Int
            let isReset: Bool
            if let previous {
                if current.totalTokens == previous.totalTokens {
                    diagnostics.duplicateRecords += 1
                    continue
                }
                if current.totalTokens > previous.totalTokens {
                    deltaTotal = current.totalTokens - previous.totalTokens
                    isReset = false
                } else if isCodexContextWindowSentinel(event) {
                    diagnostics.skippedRecords += 1
                    continue
                } else if isCredibleCodexReset(
                    at: index,
                    events: scan.events,
                    current: current,
                    previous: previous
                ) {
                    epoch += 1
                    diagnostics.counterResets += 1
                    deltaTotal = current.totalTokens
                    isReset = true
                } else {
                    diagnostics.skippedRecords += 1
                    continue
                }
            } else {
                deltaTotal = current.totalTokens
                isReset = false
            }

            guard deltaTotal > 0 else { continue }
            let componentResult = codexIncrementUsage(
                current: current,
                previous: isReset ? nil : previous,
                last: event.last,
                total: deltaTotal
            )
            let requestID = "codex:cumulative:\(scan.canonicalSessionID):\(epoch):\(current.totalTokens)"
            guard seenRequestIDs.insert(requestID).inserted else {
                diagnostics.duplicateRecords += 1
                previous = current
                continue
            }
            records.append(
                codexUsageRecord(
                    scan: scan,
                    event: event,
                    day: day,
                    usage: componentResult.usage,
                    requestID: requestID,
                    dataSource: componentResult.hasKnownBreakdown
                        ? "codex_total_usage_delta"
                        : "codex_total_usage_delta_unknown_breakdown"
                )
            )
            diagnostics.exactRecords += 1
            if !componentResult.hasKnownBreakdown {
                diagnostics.unknownBreakdownRecords += 1
            }
            previous = current
        }
        return (
            records,
            diagnostics,
            CodexDeltaCursor(
                hasCumulativeSchema: true,
                previousCumulative: previous,
                epoch: epoch
            )
        )
    }

    static func codexUsageRecord(
        scan: CodexSessionScan,
        event: CodexTokenEvent,
        day: String,
        usage: TokenUsageCounts,
        requestID: String,
        dataSource: String
    ) -> UsageRecord {
        UsageRecord(
            date: day,
            timestamp: event.timestamp,
            timestampEpoch: event.timestampEpoch,
            tool: "Codex",
            model: event.model,
            usage: usage,
            source: .nativeCodex,
            requestID: requestID,
            sessionID: scan.canonicalSessionID,
            sourcePath: scan.sourcePath,
            lineNumber: event.lineNumber,
            dataSource: dataSource
        )
    }

    static func codexIncrementUsage(
        current: TokenUsageCounts,
        previous: TokenUsageCounts?,
        last: TokenUsageCounts?,
        total: Int
    ) -> (usage: TokenUsageCounts, hasKnownBreakdown: Bool) {
        if let last,
           last.totalTokens == total,
           isCodexBreakdownConsistent(last, total: total) {
            var result = last
            result.totalTokens = total
            return (result, true)
        }

        let previous = previous ?? TokenUsageCounts()
        guard current.inputTokens >= previous.inputTokens,
              current.outputTokens >= previous.outputTokens,
              current.cacheCreationInputTokens >= previous.cacheCreationInputTokens,
              current.cacheReadInputTokens >= previous.cacheReadInputTokens,
              current.reasoningOutputTokens >= previous.reasoningOutputTokens
        else {
            return (TokenUsageCounts(totalTokens: total), false)
        }
        var result = TokenUsageCounts(
            inputTokens: current.inputTokens - previous.inputTokens,
            outputTokens: current.outputTokens - previous.outputTokens,
            cacheCreationInputTokens: current.cacheCreationInputTokens - previous.cacheCreationInputTokens,
            cacheReadInputTokens: current.cacheReadInputTokens - previous.cacheReadInputTokens,
            reasoningOutputTokens: current.reasoningOutputTokens - previous.reasoningOutputTokens,
            totalTokens: total
        )
        guard isCodexBreakdownConsistent(result, total: total) else {
            result = TokenUsageCounts(totalTokens: total)
            return (result, false)
        }
        return (result, true)
    }

    static func isCodexBreakdownConsistent(_ usage: TokenUsageCounts, total: Int) -> Bool {
        usage.inputTokens >= 0
            && usage.outputTokens >= 0
            && usage.cacheCreationInputTokens >= 0
            && usage.cacheReadInputTokens >= 0
            && usage.reasoningOutputTokens >= 0
            && usage.inputTokens + usage.outputTokens == total
            && usage.cacheCreationInputTokens + usage.cacheReadInputTokens <= usage.inputTokens
            && usage.reasoningOutputTokens <= usage.outputTokens
    }

    static func isCodexContextWindowSentinel(_ event: CodexTokenEvent) -> Bool {
        guard let current = event.cumulative else { return false }
        return current.inputTokens == 0
            && current.outputTokens == 0
            && current.cacheCreationInputTokens == 0
            && current.cacheReadInputTokens == 0
            && current.reasoningOutputTokens == 0
            && (event.last?.totalTokens ?? 0) == 0
            && event.modelContextWindow > 0
            && current.totalTokens == event.modelContextWindow
    }

    static func isCredibleCodexReset(
        at index: Int,
        events: [CodexTokenEvent],
        current: TokenUsageCounts,
        previous: TokenUsageCounts
    ) -> Bool {
        if let last = events[index].last,
           last.totalTokens == current.totalTokens,
           isCodexBreakdownConsistent(last, total: current.totalTokens) {
            return true
        }
        for candidate in events.dropFirst(index + 1) where candidate.cumulativePresent {
            guard let next = candidate.cumulative, next.totalTokens > 0 else { continue }
            if next.totalTokens == current.totalTokens { continue }
            return next.totalTokens > current.totalTokens && next.totalTokens < previous.totalTokens
        }
        return false
    }

    static func defaultCodexSessionRoots(homeURL: URL) -> [URL] {
        // archived_sessions may contain restored historical logs with rewritten timestamps.
        // Only live Codex sessions should count as current usage.
        [
            homeURL.appendingPathComponent(".codex/sessions", isDirectory: true)
        ]
    }
}
