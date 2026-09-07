import CryptoKit
import Foundation
import SQLite3

struct UsageCollectionFileState: Codable, Equatable {
    var path: String
    var size: UInt64
    var modificationTime: TimeInterval
}

struct UsageCollectionState: Codable, Equatable {
    var schemaVersion = 2
    var historyDays: Int
    var includesExperimentalAgentSources: Bool
    var windowDay: String
    var files: [UsageCollectionFileState]
}

struct CodexIncrementalCacheStats: Equatable {
    var generation: Int
    var sessions: Int
    var records: Int
    var lastLogicalWriteBytes: Int
}

struct CodexAccountingComparisonDiagnostics {
    var incrementalSnapshot: UsageSnapshot
    var referenceSnapshot: UsageSnapshot
    var mismatchedPathHashes: [String]
    var incrementalRecordCount: Int
    var referenceRecordCount: Int
}

enum UsageCollector {
    static let codexAccountingRevision = 8

    private static let timezone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    private static let maxRelevantLineBytes = 1_048_576
    private static let ccSwitchSourceName = "CC Switch Proxy"

    static func collect(
        historyDays: Int = TokenStepSettings.defaults.historyDays,
        includeCCSwitchProxyUsage: Bool = true,
        ccSwitchDatabaseURL: URL? = nil,
        includeExperimentalAgentSources: Bool = false,
        zCodeDatabaseURL: URL? = nil,
        hermesDatabaseURL: URL? = nil,
        workBuddyRootURLs: [URL]? = nil,
        forceFullValidation: Bool = false
    ) -> UsageSnapshot {
        let cacheLoad = loadCache()
        var cache = cacheLoad.cache
        var livePaths = Set<String>()
        let sourceCutoff = sourceFileCutoffDate(historyDays: historyDays)
        var ccSwitch = includeCCSwitchProxyUsage
            ? collectCCSwitchProxyUsage(databaseURL: ccSwitchDatabaseURL)
            : CollectorResult(records: [], source: SourceInfo(status: "disabled", files: nil, records: 0))
        let codexOutcome = collectCodex(
            cache: &cache,
            livePaths: &livePaths,
            modifiedSince: sourceCutoff,
            databaseURL: AppPaths.codexIncrementalCacheSQLite,
            forceFullValidation: forceFullValidation,
            requiresDetailedRecords: !ccSwitch.records.isEmpty
        )
        var codex = codexOutcome.result
        codex.source.recalibratedFromRevision = cacheLoad.recalibratedFromRevision
        let claude = collectClaudeCode(cache: &cache, livePaths: &livePaths, modifiedSince: sourceCutoff)
        let zCode = includeExperimentalAgentSources
            ? collectZCodeUsage(databaseURL: zCodeDatabaseURL)
            : CollectorResult(records: [], source: SourceInfo(status: "disabled", files: nil, records: 0))
        let hermes = includeExperimentalAgentSources
            ? collectHermesUsage(databaseURL: hermesDatabaseURL)
            : CollectorResult(records: [], source: SourceInfo(status: "disabled", files: nil, records: 0))
        let workBuddy = includeExperimentalAgentSources
            ? collectWorkBuddyUsage(rootURLs: workBuddyRootURLs, modifiedSince: sourceCutoff)
            : CollectorResult(records: [], source: SourceInfo(status: "disabled", files: nil, records: 0))
        let deepSeekHarness = includeExperimentalAgentSources
            ? collectDeepSeekHarnessUsage(
                cache: &cache,
                livePaths: &livePaths,
                rootURLs: defaultDeepSeekHarnessRoots(),
                modifiedSince: sourceCutoff
            )
            : CollectorResult(records: [], source: SourceInfo(status: "disabled", files: nil, records: 0))
        let autoClaw = collectAutoClawUsage(modifiedSince: sourceCutoff)
        if codexOutcome.usedIncrementalStore {
            cache.files = cache.files.filter { $0.value.tool != "Codex" && livePaths.contains($0.key) }
        } else {
            cache.files = cache.files.filter { livePaths.contains($0.key) }
        }
        saveCache(cache)

        let nativeRecords = codex.records + claude.records
        let deduped = deduplicateCrossSource(
            nativeRecords: nativeRecords,
            proxyRecords: ccSwitch.records
        )
        if includeCCSwitchProxyUsage {
            ccSwitch.source = sourceInfo(ccSwitch.source, annotatedWith: deduped)
        }
        let records = recordsInHistoryWindow(
            deduped.records + zCode.records + hermes.records + workBuddy.records + deepSeekHarness.records + autoClaw.records,
            historyDays: historyDays,
            now: Date()
        )
        return aggregate(
            records: records,
            sources: [
                "Codex": codex.source,
                "Claude Code": claude.source,
                ccSwitchSourceName: ccSwitch.source,
                "ZCode": zCode.source,
                "Hermes Agent": hermes.source,
                "WorkBuddy": workBuddy.source,
                "DeepSeek Harness": deepSeekHarness.source,
                "AutoClaw": autoClaw.source
            ]
        )
    }

    static func collectionState(
        historyDays: Int,
        includeExperimentalAgentSources: Bool,
        deepSeekHarnessRootURLs: [URL]? = nil,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = Date()
    ) -> UsageCollectionState {
        let cutoff = sourceFileCutoffDate(historyDays: historyDays)
        var urls = defaultCodexSessionRoots(homeURL: homeURL)
            .flatMap { jsonlFiles(under: $0, modifiedSince: cutoff) }
        urls.append(contentsOf: jsonlFiles(
            under: homeURL.appendingPathComponent(".claude/projects", isDirectory: true),
            modifiedSince: cutoff
        ))

        let databases = [
            homeURL.appendingPathComponent(".codex/state_5.sqlite"),
            homeURL.appendingPathComponent(".codex/sqlite/state_5.sqlite"),
            homeURL.appendingPathComponent(".cc-switch/cc-switch.db")
        ]
        urls.append(contentsOf: existingDatabaseFiles(databases))

        if includeExperimentalAgentSources {
            urls.append(contentsOf: existingDatabaseFiles([
                homeURL.appendingPathComponent(".zcode/cli/db/db.sqlite"),
                homeURL.appendingPathComponent(".hermes/state.db")
            ]))
            urls.append(contentsOf: [
                homeURL.appendingPathComponent(".workbuddy/projects", isDirectory: true),
                homeURL.appendingPathComponent("Library/Application Support/WorkBuddyExtension", isDirectory: true)
            ].flatMap { jsonlFiles(under: $0, modifiedSince: cutoff) })
            urls.append(contentsOf: (deepSeekHarnessRootURLs ?? defaultDeepSeekHarnessRoots(homeURL: homeURL)).flatMap {
                zstdSessionFiles(under: $0, modifiedSince: cutoff)
            })
        }
        urls.append(contentsOf: jsonlFiles(
            under: homeURL.appendingPathComponent(".openclaw-autoclaw", isDirectory: true),
            modifiedSince: cutoff
        ))

        let files = Dictionary(grouping: urls, by: \.path)
            .compactMap { _, duplicates in duplicates.first.flatMap(collectionFileState) }
            .sorted { $0.path < $1.path }
        return UsageCollectionState(
            historyDays: historyDays,
            includesExperimentalAgentSources: includeExperimentalAgentSources,
            windowDay: dayFormatter.string(from: now),
            files: files
        )
    }

    static func codexIncrementalCacheStatsForTests(databaseURL: URL) -> CodexIncrementalCacheStats? {
        try? CodexIncrementalStore(url: databaseURL).stats()
    }

    static func codexCollectionStateForTests(
        homeURL: URL
    ) -> [UsageCollectionFileState] {
        defaultCodexSessionRoots(homeURL: homeURL)
            .flatMap { jsonlFiles(under: $0, modifiedSince: nil) }
            .compactMap(collectionFileState)
            .sorted { $0.path < $1.path }
    }

    static func compareIncrementalCodexAccountingForTests(
        homeURL: URL,
        databaseURL: URL
    ) throws -> CodexAccountingComparisonDiagnostics {
        let incremental = try collectCodexIncrementally(
            modifiedSince: nil,
            databaseURL: databaseURL,
            forceFullValidation: false,
            homeURL: homeURL,
            requiresDetailedRecords: true
        )
        var cache = CollectorCache()
        var livePaths = Set<String>()
        let reference = collectCodexFromJSONL(
            cache: &cache,
            livePaths: &livePaths,
            modifiedSince: nil,
            homeURL: homeURL
        )

        return try accountingComparisonDiagnostics(
            incremental: incremental,
            reference: reference
        )
    }

    static func compareLegacyMigrationCodexAccountingForTests(
        homeURL: URL,
        databaseURL: URL
    ) throws -> CodexAccountingComparisonDiagnostics {
        var legacyCache = CollectorCache()
        var livePaths = Set<String>()
        let reference = collectCodexFromJSONL(
            cache: &legacyCache,
            livePaths: &livePaths,
            modifiedSince: nil,
            homeURL: homeURL
        )
        let incremental = try collectCodexIncrementally(
            modifiedSince: nil,
            databaseURL: databaseURL,
            forceFullValidation: false,
            homeURL: homeURL,
            requiresDetailedRecords: true,
            legacyCache: legacyCache
        )
        return try accountingComparisonDiagnostics(
            incremental: incremental,
            reference: reference
        )
    }

    private static func accountingComparisonDiagnostics(
        incremental: CollectorResult,
        reference: CollectorResult
    ) throws -> CodexAccountingComparisonDiagnostics {
        let incrementalByPath = Dictionary(grouping: incremental.records) {
            $0.sourcePath ?? "<missing>"
        }
        let referenceByPath = Dictionary(grouping: reference.records) {
            $0.sourcePath ?? "<missing>"
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let paths = Set(incrementalByPath.keys).union(referenceByPath.keys)
        let mismatches = try paths.compactMap { path -> String? in
            let incrementalData = try encoder.encode(incrementalByPath[path] ?? [])
            let referenceData = try encoder.encode(referenceByPath[path] ?? [])
            return incrementalData == referenceData ? nil : anonymousPathHash(path)
        }.sorted()

        return CodexAccountingComparisonDiagnostics(
            incrementalSnapshot: aggregate(
                records: incremental.records,
                sources: ["Codex": incremental.source]
            ),
            referenceSnapshot: aggregate(
                records: reference.records,
                sources: ["Codex": reference.source]
            ),
            mismatchedPathHashes: mismatches,
            incrementalRecordCount: incremental.records.count,
            referenceRecordCount: reference.records.count
        )
    }

    private static func anonymousPathHash(_ path: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static func existingDatabaseFiles(_ databases: [URL]) -> [URL] {
        databases.flatMap { database in
            [
                database,
                URL(fileURLWithPath: database.path + "-wal")
            ].filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    private static func collectionFileState(_ url: URL) -> UsageCollectionFileState? {
        guard let metadata = fileMetadata(for: url) else { return nil }
        return UsageCollectionFileState(
            path: url.standardizedFileURL.path,
            size: metadata.size,
            modificationTime: metadata.modificationTime
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

    static func collectCodexUsageSnapshotForTests(
        homeURL: URL,
        cacheURL: URL? = nil,
        forceFullValidation: Bool = false,
        requiresDetailedRecords: Bool = false
    ) -> UsageSnapshot {
        if let cacheURL {
            do {
                let result = try collectCodexIncrementally(
                modifiedSince: nil,
                databaseURL: cacheURL,
                forceFullValidation: forceFullValidation,
                homeURL: homeURL,
                requiresDetailedRecords: requiresDetailedRecords
                )
                return aggregate(records: result.records, sources: ["Codex": result.source])
            } catch {
                return aggregate(
                    records: [],
                    sources: ["Codex": SourceInfo(status: "incremental_cache_error", files: 0, records: 0)]
                )
            }
        }
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

    static func collectIncrementalCodexAndProxySnapshotForTests(
        codexRoots: [URL],
        cacheURL: URL,
        ccSwitchDatabaseURL: URL
    ) -> UsageSnapshot {
        let codex: CollectorResult
        do {
            codex = try collectCodexIncrementally(
                modifiedSince: nil,
                databaseURL: cacheURL,
                forceFullValidation: false,
                requiresDetailedRecords: true,
                roots: codexRoots
            )
        } catch {
            codex = CollectorResult(
                records: [],
                source: SourceInfo(status: "incremental_cache_error", files: 0, records: 0)
            )
        }
        var proxy = collectCCSwitchProxyUsage(databaseURL: ccSwitchDatabaseURL)
        let deduped = deduplicateCrossSource(
            nativeRecords: codex.records,
            proxyRecords: proxy.records
        )
        proxy.source = sourceInfo(proxy.source, annotatedWith: deduped)
        return aggregate(
            records: deduped.records,
            sources: [
                "Codex": codex.source,
                ccSwitchSourceName: proxy.source
            ]
        )
    }

    static func collectCodexWithIncrementalFallbackForTests(
        homeURL: URL,
        cacheURL: URL
    ) -> UsageSnapshot {
        var cache = CollectorCache()
        var livePaths = Set<String>()
        let outcome = collectCodex(
            cache: &cache,
            livePaths: &livePaths,
            modifiedSince: nil,
            databaseURL: cacheURL,
            forceFullValidation: false,
            requiresDetailedRecords: false,
            homeURL: homeURL
        )
        return aggregate(
            records: outcome.result.records,
            sources: ["Codex": outcome.result.source]
        )
    }

    static func collectorCacheRecalibrationRevisionForTests(cacheURL: URL) -> Int? {
        loadCache(at: cacheURL).recalibratedFromRevision
    }

    static func collectUsageSnapshotForTests(
        codexRoots: [URL] = [],
        claudeRootURL: URL? = nil,
        ccSwitchDatabaseURL: URL? = nil,
        zCodeDatabaseURL: URL? = nil,
        hermesDatabaseURL: URL? = nil,
        workBuddyRootURLs: [URL]? = nil,
        deepSeekHarnessRootURLs: [URL]? = nil,
        autoClawRootURLs: [URL]? = nil,
        includeExperimentalAgentSources: Bool = false,
        historyDays: Int? = nil,
        now: Date = Date()
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
        let zCode = includeExperimentalAgentSources
            ? zCodeDatabaseURL.map { collectZCodeUsage(databaseURL: $0) } ?? CollectorResult(records: [], source: SourceInfo(status: "missing_db", files: 0, records: 0))
            : CollectorResult(records: [], source: SourceInfo(status: "disabled", files: nil, records: 0))
        let hermes = includeExperimentalAgentSources
            ? hermesDatabaseURL.map { collectHermesUsage(databaseURL: $0) } ?? CollectorResult(records: [], source: SourceInfo(status: "missing_db", files: 0, records: 0))
            : CollectorResult(records: [], source: SourceInfo(status: "disabled", files: nil, records: 0))
        let workBuddy = includeExperimentalAgentSources
            ? collectWorkBuddyUsage(rootURLs: workBuddyRootURLs ?? [], modifiedSince: nil)
            : CollectorResult(records: [], source: SourceInfo(status: "disabled", files: nil, records: 0))
        let deepSeekHarness = includeExperimentalAgentSources
            ? collectDeepSeekHarnessUsage(
                cache: &cache,
                livePaths: &livePaths,
                rootURLs: deepSeekHarnessRootURLs ?? [],
                modifiedSince: nil
            )
            : CollectorResult(records: [], source: SourceInfo(status: "disabled", files: nil, records: 0))
        // Keep test snapshots isolated from the developer machine's live AutoClaw
        // history; callers opt in by supplying explicit roots.
        let autoClaw = autoClawRootURLs.map {
            collectAutoClawUsage(rootURLs: $0, modifiedSince: nil)
        } ?? CollectorResult(
            records: [],
            source: SourceInfo(status: "disabled", files: nil, records: 0)
        )
        let deduped = deduplicateCrossSource(
            nativeRecords: codex.records + claude.records,
            proxyRecords: ccSwitch.records
        )
        ccSwitch.source = sourceInfo(ccSwitch.source, annotatedWith: deduped)
        let allRecords = deduped.records + zCode.records + hermes.records + workBuddy.records + deepSeekHarness.records + autoClaw.records
        let records = historyDays.map {
            recordsInHistoryWindow(allRecords, historyDays: $0, now: now)
        } ?? allRecords
        return aggregate(
            records: records,
            sources: [
                "Codex": codex.source,
                "Claude Code": claude.source,
                ccSwitchSourceName: ccSwitch.source,
                "ZCode": zCode.source,
                "Hermes Agent": hermes.source,
                "WorkBuddy": workBuddy.source,
                "DeepSeek Harness": deepSeekHarness.source,
                "AutoClaw": autoClaw.source
            ]
        )
    }

    private static func collectCodex(
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

    private static func collectCodexIncrementally(
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

    private static func codexCollectorResult(
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

    private static func summarizeCodexRecords(_ records: [UsageRecord]) -> [UsageRecord] {
        var summaries = [CodexSummaryKey: CodexSummaryAccumulator]()
        for record in records {
            addCodexSummary(record, to: &summaries)
        }
        return codexSummaryRecords(summaries)
    }

    private static func addCodexSummary(
        _ record: UsageRecord,
        to summaries: inout [CodexSummaryKey: CodexSummaryAccumulator]
    ) {
        let hour = record.timestampEpoch.map(hour(fromEpoch:))
            ?? hour(fromISO: record.timestamp)
        let key = CodexSummaryKey(date: record.date, model: record.model, hour: hour)
        summaries[key, default: CodexSummaryAccumulator()].add(record)
    }

    private static func codexSummaryRecords(
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

    private static func stableCodexScan(
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

    private static func incrementalCodexAppend(
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

    private static func scanCodexSessionTail(
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

    private static func scanCodexSessionFile(at path: URL) -> CodexSessionScan? {
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

    private static func codexParentSessionID(from payload: [String: Any]?) -> String? {
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

    private static func codexForkAnchor(
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

    private static func codexAnchors(for scan: CodexSessionScan) -> [CodexAnchor] {
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

    private static func codexAnchor(
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

    private static func codexDeltaRecords(
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

    private static func codexUsageRecord(
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

    private static func codexIncrementUsage(
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

    private static func isCodexBreakdownConsistent(_ usage: TokenUsageCounts, total: Int) -> Bool {
        usage.inputTokens >= 0
            && usage.outputTokens >= 0
            && usage.cacheCreationInputTokens >= 0
            && usage.cacheReadInputTokens >= 0
            && usage.reasoningOutputTokens >= 0
            && usage.inputTokens + usage.outputTokens == total
            && usage.cacheCreationInputTokens + usage.cacheReadInputTokens <= usage.inputTokens
            && usage.reasoningOutputTokens <= usage.outputTokens
    }

    private static func isCodexContextWindowSentinel(_ event: CodexTokenEvent) -> Bool {
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

    private static func isCredibleCodexReset(
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

    private static func collectZCodeUsage(databaseURL: URL? = nil) -> CollectorResult {
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

    private static func collectHermesUsage(databaseURL: URL? = nil) -> CollectorResult {
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

    private static func collectWorkBuddyUsage(
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

    private static func zstdSessionFiles(under root: URL, modifiedSince cutoffDate: Date? = nil) -> [URL] {
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
                  url.lastPathComponent == "session.jsonl.zstd",
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

    private static func defaultDeepSeekHarnessRoots(
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        [
            homeURL.appendingPathComponent(".dsh/sessions", isDirectory: true),
            homeURL.appendingPathComponent(
                "Library/Application Support/@deepseek-ai/dsh-desktop/harness/sessions",
                isDirectory: true
            )
        ]
    }

    private static func parseDeepSeekHarnessFile(_ url: URL) throws -> DeepSeekHarnessFileResult {
        var sessionID = url.deletingLastPathComponent().lastPathComponent
        var sequence = 0
        var candidates: [String: DeepSeekHarnessCandidate] = [:]
        let decodeResult = try DeepSeekHarnessDecoder.decode(fileURL: url) { line in
            sequence += 1
            guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                return
            }
            let eventType = object["type"] as? String ?? ""
            if eventType == "session" || eventType == "session/header" {
                sessionID = nonEmptyString(object["id"] as? String) ?? sessionID
                return
            }
            guard eventType == "assistant/message" || eventType == "assistant/chunk",
                  let data = object["data"] as? [String: Any],
                  let turn = integerValueIfPresent(data["turn"]),
                  let step = integerValueIfPresent(data["step"])
            else {
                return
            }

            let chunk = data["chunk"] as? [String: Any]
            let usage = (data["usage"] as? [String: Any]) ?? (chunk?["usage"] as? [String: Any])
            let isMessage = eventType == "assistant/message"
            let chunkType = data["type"] as? String ?? chunk?["type"] as? String
            guard let usage, isMessage || chunkType == "usage" else {
                return
            }

            let source = ((data["message"] as? [String: Any])?["source"] as? [String: Any])
                ?? ((chunk?["replayState"] as? [String: Any]))
            let model = nonEmptyString(source?["model"] as? String) ?? "unknown"
            let provider = nonEmptyString(source?["provider"] as? String)
            let input = integerValueIfPresent(usage["inputTokens"]) ?? 0
            let output = integerValueIfPresent(usage["outputTokens"]) ?? 0
            let cacheRead = integerValueIfPresent(usage["cacheReadTokens"]) ?? 0
            let cacheWrite = integerValueIfPresent(usage["cacheWriteTokens"]) ?? 0
            let reasoning = integerValueIfPresent(usage["reasoningTokens"]) ?? 0
            guard input >= 0, output >= 0, cacheRead >= 0, cacheWrite >= 0, reasoning >= 0 else {
                return
            }
            let timestampEpoch = epochSeconds(object["time"])
            guard let timestampEpoch,
                  let date = dayString(fromEpoch: timestampEpoch),
                  let timestamp = isoString(fromEpoch: timestampEpoch)
            else {
                return
            }
            let usageCounts = canonicalUsageCounts(
                rawInputTokens: input,
                outputTokens: output,
                cacheCreationInputTokens: cacheWrite,
                cacheReadInputTokens: cacheRead,
                reasoningOutputTokens: reasoning,
                inputIncludesCachedTokens: false
            )
            guard usageCounts.totalTokens > 0 else { return }

            let key = "\(sessionID)|\(turn)|\(step)"
            let candidate = DeepSeekHarnessCandidate(
                key: key,
                date: date,
                timestamp: timestamp,
                timestampEpoch: timestampEpoch,
                model: model,
                usage: usageCounts,
                requestID: key,
                sessionID: sessionID,
                sourcePath: nil,
                lineNumber: sequence,
                dataSource: provider,
                priority: isMessage ? 2 : 1
            )
            if let existing = candidates[key] {
                if candidate.isPreferred(over: existing) {
                    candidates[key] = candidate
                }
            } else {
                candidates[key] = candidate
            }
        }
        return DeepSeekHarnessFileResult(
            records: candidates.values.map(\.record),
            partialTail: decodeResult.partialTail
        )
    }

    private static func mergeDeepSeekHarnessCandidate(
        _ candidate: DeepSeekHarnessCandidate,
        into candidates: inout [String: DeepSeekHarnessCandidate]
    ) {
        guard let key = candidate.key else { return }
        if let existing = candidates[key] {
            if candidate.isPreferred(over: existing) {
                candidates[key] = candidate
            }
        } else {
            candidates[key] = candidate
        }
    }

    private static func integerValueIfPresent(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func collectDeepSeekHarnessUsage(
        cache: inout CollectorCache,
        livePaths: inout Set<String>,
        rootURLs: [URL],
        modifiedSince: Date?
    ) -> CollectorResult {
        let urls = rootURLs.flatMap { zstdSessionFiles(under: $0, modifiedSince: modifiedSince) }
        guard !urls.isEmpty else {
            return CollectorResult(
                records: [],
                source: SourceInfo(status: "missing_files", files: 0, records: 0)
            )
        }

        var candidates: [String: DeepSeekHarnessCandidate] = [:]
        var acceptedFiles = 0
        var partialFiles = 0
        var unreadableFiles = 0

        for url in urls {
            livePaths.insert(url.path)
            if let cached = cachedRecords(for: url, tool: "DeepSeek Harness", cache: cache) {
                acceptedFiles += 1
                for record in cached {
                    mergeDeepSeekHarnessCandidate(
                        DeepSeekHarnessCandidate(record: record),
                        into: &candidates
                    )
                }
                continue
            }

            do {
                let beforeMetadata = fileMetadata(for: url)
                let priorRecords = cache.files[url.path]?.records
                let parsed = try parseDeepSeekHarnessFile(url)
                let afterMetadata = fileMetadata(for: url)
                let stable = beforeMetadata.flatMap { before in
                    afterMetadata.map { metadata(before, matches: $0) }
                } ?? false
                acceptedFiles += 1
                if parsed.partialTail || !stable { partialFiles += 1 }
                let recordsToMerge = stable && !parsed.partialTail ? parsed.records : (priorRecords ?? parsed.records)
                for record in recordsToMerge {
                    mergeDeepSeekHarnessCandidate(
                        DeepSeekHarnessCandidate(record: record),
                        into: &candidates
                    )
                }
                if stable && !parsed.partialTail {
                    updateCache(path: url, tool: "DeepSeek Harness", records: parsed.records, cache: &cache)
                }
            } catch {
                unreadableFiles += 1
            }
        }

        let records = candidates.values
            .map(\.record)
            .sorted { lhs, rhs in
                (lhs.timestampEpoch ?? 0) < (rhs.timestampEpoch ?? 0)
            }
        let status: String
        if unreadableFiles > 0 && records.isEmpty {
            status = "unreadable_source"
        } else if partialFiles > 0 {
            status = "partial_tail"
        } else if records.isEmpty {
            status = "missing_valid_rows"
        } else {
            status = "ok"
        }
        return CollectorResult(
            records: records,
            source: SourceInfo(
                status: status,
                files: acceptedFiles,
                records: records.count,
                skippedRecords: unreadableFiles
            )
        )
    }

    private static func collectAutoClawUsage(
        rootURLs: [URL]? = nil,
        modifiedSince cutoffDate: Date?
    ) -> CollectorResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = rootURLs ?? [
            home.appendingPathComponent(".openclaw-autoclaw/agents", isDirectory: true)
        ]
        let sessionRoots = roots.flatMap { root -> [URL] in
            guard FileManager.default.fileExists(atPath: root.path),
                  let contents = try? FileManager.default.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: [.isDirectoryKey]
                  )
            else { return [] }
            return contents.filter { agent in
                (try? agent.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }.map { $0.appendingPathComponent("sessions", isDirectory: true) }
        }
        let discoveredRoots = sessionRoots.filter { FileManager.default.fileExists(atPath: $0.path) }
        let files = discoveredRoots.flatMap { jsonlFiles(under: $0, modifiedSince: cutoffDate) }
        var records: [UsageRecord] = []

        for file in files {
            var lineNumber = 0
            try? forEachLine(in: file, matchingAny: ["\"usage\""]) { line in
                lineNumber += 1
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let message = object["message"] as? [String: Any],
                      let usageDict = message["usage"] as? [String: Any],
                      let day = dayString(fromISO: (object["timestamp"] as? String) ?? ""),
                      !day.isEmpty
                else {
                    return
                }

                let input = firstIntegerValue(
                    in: usageDict,
                    keys: ["input"]
                )
                let output = firstIntegerValue(
                    in: usageDict,
                    keys: ["output"]
                )
                let cacheRead = firstIntegerValue(
                    in: usageDict,
                    keys: ["cacheRead"]
                )
                let cacheWrite = firstIntegerValue(
                    in: usageDict,
                    keys: ["cacheWrite"]
                )
                let reasoning = firstIntegerValue(
                    in: usageDict,
                    keys: ["reasoningTokens"]
                )
                // OpenClaw records input including cached tokens; total is explicit.
                let counts = canonicalUsageCounts(
                    rawInputTokens: input,
                    outputTokens: output,
                    cacheCreationInputTokens: cacheWrite,
                    cacheReadInputTokens: cacheRead,
                    reasoningOutputTokens: reasoning,
                    inputIncludesCachedTokens: true,
                    explicitTotalTokens: firstIntegerValue(in: usageDict, keys: ["totalTokens"]),
                    explicitTotalIsAuthoritative: true
                )
                guard counts.totalTokens > 0 else { return }

                let timestamp = isoString(fromEpoch: object["timestamp"])
                    ?? (object["timestamp"] as? String)
                let epoch = epochSeconds(object["timestamp"])
                let recordType = object["type"] as? String
                records.append(UsageRecord(
                    date: day,
                    timestamp: timestamp,
                    timestampEpoch: epoch,
                    tool: "AutoClaw",
                    model: modelKey(message["model"] as? String),
                    usage: counts,
                    source: .autoclaw,
                    requestID: nonEmptyString(message["responseId"] as? String),
                    sessionID: nonEmptyString(object["id"] as? String),
                    sourcePath: file.path,
                    lineNumber: lineNumber,
                    modelRequestCount: 1,
                    toolCallCount: recordType == "function_call" ? 1 : 0
                ))
            }
        }

        let status: String
        if roots.allSatisfy({ !FileManager.default.fileExists(atPath: $0.path) }) {
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

    private static func workBuddyUsage(from object: [String: Any]) -> TokenUsageCounts? {
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

    private static func firstIntegerValue(in object: [String: Any], keys: [String]) -> Int {
        for key in keys where object.keys.contains(key) {
            return max(0, integerValue(object[key] as Any))
        }
        return 0
    }

    private static func deduplicateCrossSource(
        nativeRecords: [UsageRecord],
        proxyRecords: [UsageRecord]
    ) -> CrossSourceDedupeResult {
        var enrichedNativeRecords = nativeRecords
        let deduplicableProxyIndices = proxyRecords.indices.filter {
            isDeduplicableProxyRecord(proxyRecords[$0])
        }
        var matchedProxyIndices = Set<Int>()
        var matchedNativeIndices = Set<Int>()
        let skippedProxyRecords = 0

        let exactPairs = uniqueDedupePairs(
            proxyIndices: deduplicableProxyIndices,
            nativeIndices: Array(nativeRecords.indices)
        ) { proxyIndex, nativeIndex in
            isSameDedupeDomain(
                proxyRecord: proxyRecords[proxyIndex],
                nativeRecord: nativeRecords[nativeIndex]
            ) && hasExactIdentifierMatch(
                proxyRecord: proxyRecords[proxyIndex],
                nativeRecord: nativeRecords[nativeIndex]
            )
        }
        applyDedupePairs(
            exactPairs,
            proxyRecords: proxyRecords,
            enrichedNativeRecords: &enrichedNativeRecords,
            matchedProxyIndices: &matchedProxyIndices,
            matchedNativeIndices: &matchedNativeIndices
        )

        // Similar timing/model/token vectors alone are not proof of identity: concurrent
        // requests can legitimately look the same. A shared session is the minimum
        // fallback correlation when request/response IDs are unavailable.
        let remainingProxyIndices = deduplicableProxyIndices.filter { !matchedProxyIndices.contains($0) }
        let remainingNativeIndices = nativeRecords.indices.filter { !matchedNativeIndices.contains($0) }
        let sessionPairs = uniqueDedupePairs(
            proxyIndices: remainingProxyIndices,
            nativeIndices: Array(remainingNativeIndices)
        ) { proxyIndex, nativeIndex in
            isSameDedupeDomain(
                proxyRecord: proxyRecords[proxyIndex],
                nativeRecord: nativeRecords[nativeIndex]
            ) && hasSessionIdentityMatch(
                proxyRecord: proxyRecords[proxyIndex],
                nativeRecord: nativeRecords[nativeIndex]
            )
        }
        applyDedupePairs(
            sessionPairs,
            proxyRecords: proxyRecords,
            enrichedNativeRecords: &enrichedNativeRecords,
            matchedProxyIndices: &matchedProxyIndices,
            matchedNativeIndices: &matchedNativeIndices
        )

        let keptProxyRecords = proxyRecords.indices
            .filter { !matchedProxyIndices.contains($0) }
            .map { proxyRecords[$0] }
        return CrossSourceDedupeResult(
            records: enrichedNativeRecords + keptProxyRecords,
            rawProxyRecords: proxyRecords.count,
            keptProxyRecords: keptProxyRecords.count,
            dedupedProxyRecords: matchedProxyIndices.count,
            skippedProxyRecords: skippedProxyRecords
        )
    }

    private static func uniqueDedupePairs(
        proxyIndices: [Int],
        nativeIndices: [Int],
        matches: (Int, Int) -> Bool
    ) -> [(proxy: Int, native: Int)] {
        var nativeCandidatesByProxy: [Int: [Int]] = [:]
        var proxyCandidateCountByNative: [Int: Int] = [:]
        for proxyIndex in proxyIndices {
            let candidates = nativeIndices.filter { matches(proxyIndex, $0) }
            nativeCandidatesByProxy[proxyIndex] = candidates
            for nativeIndex in candidates {
                proxyCandidateCountByNative[nativeIndex, default: 0] += 1
            }
        }
        return proxyIndices.compactMap { proxyIndex in
            guard let candidates = nativeCandidatesByProxy[proxyIndex],
                  candidates.count == 1,
                  let nativeIndex = candidates.first,
                  proxyCandidateCountByNative[nativeIndex] == 1
            else {
                return nil
            }
            return (proxy: proxyIndex, native: nativeIndex)
        }
    }

    private static func applyDedupePairs(
        _ pairs: [(proxy: Int, native: Int)],
        proxyRecords: [UsageRecord],
        enrichedNativeRecords: inout [UsageRecord],
        matchedProxyIndices: inout Set<Int>,
        matchedNativeIndices: inout Set<Int>
    ) {
        for pair in pairs {
            enrichedNativeRecords[pair.native] = enrichedRecord(
                enrichedNativeRecords[pair.native],
                withProxyCostFrom: proxyRecords[pair.proxy]
            )
            matchedProxyIndices.insert(pair.proxy)
            matchedNativeIndices.insert(pair.native)
        }
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

    private static func isSameDedupeDomain(proxyRecord: UsageRecord, nativeRecord: UsageRecord) -> Bool {
        guard proxyRecord.date == nativeRecord.date,
              let proxyFamily = toolFamily(for: proxyRecord.tool),
              let nativeFamily = toolFamily(for: nativeRecord.tool),
              proxyFamily == nativeFamily,
              nativeRecord.source != .ccSwitchProxy
        else {
            return false
        }
        return true
    }

    private static func hasExactIdentifierMatch(proxyRecord: UsageRecord, nativeRecord: UsageRecord) -> Bool {
        let proxyIDs = Set([proxyRecord.requestID, proxyRecord.responseID].compactMap(nonEmptyString))
        let nativeIDs = Set([nativeRecord.requestID, nativeRecord.responseID].compactMap(nonEmptyString))
        return !proxyIDs.isDisjoint(with: nativeIDs)
    }

    private static func hasSessionIdentityMatch(proxyRecord: UsageRecord, nativeRecord: UsageRecord) -> Bool {
        guard let proxySessionID = nonEmptyString(proxyRecord.sessionID),
              let nativeSessionID = nonEmptyString(nativeRecord.sessionID),
              proxySessionID == nativeSessionID,
              areTimestampsClose(proxyRecord.timestamp, nativeRecord.timestamp, seconds: 10),
              modelsCompatible(proxyRecord.model, nativeRecord.model),
              usageVectorsClose(proxyRecord: proxyRecord, nativeRecord: nativeRecord)
        else {
            return false
        }
        return true
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

    private static func usageVectorsClose(proxyRecord: UsageRecord, nativeRecord: UsageRecord) -> Bool {
        guard toolFamily(for: proxyRecord.tool) == "codex",
              toolFamily(for: nativeRecord.tool) == "codex"
        else {
            return usageVectorsClose(proxyRecord.usage, nativeRecord.usage)
        }

        let proxy = proxyRecord.usage
        let native = nativeRecord.usage
        guard tokenValuesClose(proxy.outputTokens, native.outputTokens),
              tokenValuesClose(proxy.cacheReadInputTokens, native.cacheReadInputTokens),
              tokenValuesClose(proxy.cacheCreationInputTokens, native.cacheCreationInputTokens)
        else {
            return false
        }

        // Native Codex reports cached input as a subset of input. CC Switch versions
        // have emitted input both inclusive and exclusive of cached input, so compare
        // both canonical interpretations without changing either source's stored data.
        let nativeUncachedInput = max(0, native.inputTokens - native.cacheReadInputTokens)
        let inputMatches = tokenValuesClose(proxy.inputTokens, native.inputTokens)
            || tokenValuesClose(proxy.inputTokens, nativeUncachedInput)
        guard inputMatches else { return false }

        let proxyProcessedCandidates = [
            proxy.inputTokens + proxy.outputTokens,
            proxy.inputTokens + proxy.cacheReadInputTokens + proxy.cacheCreationInputTokens + proxy.outputTokens
        ]
        return proxyProcessedCandidates.contains { tokenValuesClose($0, native.totalTokens) }
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
        var agentWork = [String: AgentWorkAccumulator]()
        var tools = [String: UsageAccumulator]()
        var models = [ModelKey: UsageAccumulator]()

        for record in records {
            let cost = record.costUSD ?? estimateCost(usage: record.usage, tool: record.tool, model: record.model)
            daily[record.date, default: DailyAccumulator(date: record.date)].add(record: record, cost: cost)
            let recordHour = record.timestampEpoch.map(hour(fromEpoch:))
                ?? hour(fromISO: record.timestamp)
            if let hour = recordHour {
                rhythms[record.date, default: RhythmAccumulator(date: record.date)]
                    .add(tokens: record.usage.totalTokens, hour: hour)
            }
            if isAgentWorkRecord(record) {
                agentWork[record.date, default: AgentWorkAccumulator(date: record.date)]
                    .add(record: record, hour: recordHour)
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
                    modelCosts: item.modelCosts.mapValues { rounded($0, digits: 4) },
                    totalTokens: item.totalTokens,
                    cost: rounded(item.cost, digits: 4)
                )
            }

        let rhythmRows = rhythms.values
            .map(\.dailyRhythm)
            .filter { $0.totalTokens > 0 }
            .sorted { $0.date < $1.date }

        let agentWorkRows = agentWork.values
            .map(\.dailyAgentWork)
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
            agentWork: agentWorkRows,
            tools: toolRows,
            models: modelRows,
            sources: sources
        )
    }

    private static func isAgentWorkRecord(_ record: UsageRecord) -> Bool {
        switch record.source {
        case .nativeCodex, .nativeCodexSQLite, .nativeClaudeCode, .ccSwitchProxy, .zcode, .hermes, .workbuddy, .deepSeekHarness, .autoclaw:
            return true
        case .unknown:
            return false
        }
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
              let fingerprint = contentFingerprint(for: url, size: metadata.size),
              let cached = cache.files[url.path],
              cached.tool == tool,
              cached.size == metadata.size,
              abs(cached.modificationTime - metadata.modificationTime) < 0.001,
              cached.contentFingerprint == fingerprint
        else {
            return nil
        }
        return cached.records
    }

    private static func cachedCodexScan(for url: URL, cache: CollectorCache) -> CodexSessionScan? {
        guard let metadata = fileMetadata(for: url),
              let fingerprint = contentFingerprint(for: url, size: metadata.size),
              let cached = cache.files[url.path],
              cached.tool == "Codex",
              cached.size == metadata.size,
              abs(cached.modificationTime - metadata.modificationTime) < 0.001,
              cached.contentFingerprint == fingerprint
        else {
            return nil
        }
        return cached.codexScan
    }

    private static func updateCache(path: URL, tool: String, records: [UsageRecord], cache: inout CollectorCache) {
        guard let metadata = fileMetadata(for: path),
              let fingerprint = contentFingerprint(for: path, size: metadata.size)
        else {
            return
        }
        cache.files[path.path] = CachedUsageFile(
            tool: tool,
            size: metadata.size,
            modificationTime: metadata.modificationTime,
            records: records,
            contentFingerprint: fingerprint
        )
    }

    private static func updateCodexCache(
        path: URL,
        scan: CodexSessionScan,
        metadata: (size: UInt64, modificationTime: TimeInterval),
        cache: inout CollectorCache
    ) {
        guard let currentMetadata = fileMetadata(for: path),
              UsageCollector.metadata(metadata, matches: currentMetadata),
              let fingerprint = contentFingerprint(for: path, size: currentMetadata.size),
              let finalMetadata = fileMetadata(for: path),
              UsageCollector.metadata(currentMetadata, matches: finalMetadata)
        else {
            return
        }
        cache.files[path.path] = CachedUsageFile(
            tool: "Codex",
            size: finalMetadata.size,
            modificationTime: finalMetadata.modificationTime,
            records: [],
            codexScan: scan,
            contentFingerprint: fingerprint
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

    private static func metadata(
        _ lhs: (size: UInt64, modificationTime: TimeInterval),
        matches rhs: (size: UInt64, modificationTime: TimeInterval)
    ) -> Bool {
        lhs.size == rhs.size && abs(lhs.modificationTime - rhs.modificationTime) < 0.001
    }

    private static func contentFingerprint(for url: URL, size: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let chunkSize = 4_096
        var hash: UInt64 = 14_695_981_039_346_656_037
        func include(_ data: Data) {
            for byte in data {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
        }

        do {
            include(withUnsafeBytes(of: size.littleEndian) { Data($0) })
            let leadingCount = min(chunkSize, Int(clamping: size))
            include(try handle.read(upToCount: leadingCount) ?? Data())
            if size > UInt64(leadingCount) {
                let trailingCount = min(chunkSize, Int(clamping: size))
                try handle.seek(toOffset: size - UInt64(trailingCount))
                include(try handle.read(upToCount: trailingCount) ?? Data())
            }
            return String(format: "%016llx", hash)
        } catch {
            return nil
        }
    }

    private static func fullContentFingerprint(for url: URL, size: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        hasher.update(data: withUnsafeBytes(of: size.littleEndian) { Data($0) })
        var remaining = size
        do {
            while remaining > 0 {
                let requested = min(1_048_576, Int(clamping: remaining))
                guard let chunk = try autoreleasepool(invoking: {
                    try handle.read(upToCount: requested)
                }), !chunk.isEmpty else {
                    return nil
                }
                hasher.update(data: chunk)
                remaining -= UInt64(chunk.count)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch {
            return nil
        }
    }

    private static func loadCache() -> CollectorCacheLoad {
        loadCache(at: AppPaths.collectorCacheJSON)
    }

    private static func loadCache(at url: URL) -> CollectorCacheLoad {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CollectorCache.self, from: data)
        else {
            return CollectorCacheLoad(cache: CollectorCache(), recalibratedFromRevision: nil)
        }
        guard decoded.version == CollectorCache.currentVersion else {
            return CollectorCacheLoad(
                cache: CollectorCache(),
                recalibratedFromRevision: decoded.version < CollectorCache.currentVersion ? decoded.version : nil
            )
        }
        return CollectorCacheLoad(cache: decoded, recalibratedFromRevision: nil)
    }

    private static func saveCache(_ cache: CollectorCache) {
        saveCache(cache, to: AppPaths.collectorCacheJSON)
    }

    private static func loadCurrentCache(at url: URL) -> CollectorCache {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(CollectorCache.self, from: data),
              cache.version == CollectorCache.currentVersion
        else {
            return CollectorCache()
        }
        return cache
    }

    private static func saveCache(_ cache: CollectorCache, to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(cache)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let existingSize = (attributes[.size] as? NSNumber)?.intValue,
               existingSize == data.count,
               let existing = try? Data(contentsOf: url),
               existing == data {
                return
            }
            try data.write(to: url, options: .atomic)
        } catch {
            // Cache misses should never prevent the app from showing fresh usage.
        }
    }

    private static func sourceFileCutoffDate(historyDays: Int) -> Date? {
        calendar.date(byAdding: .day, value: -max(7, historyDays + 1), to: Date())
    }

    private static func recordsInHistoryWindow(
        _ records: [UsageRecord],
        historyDays: Int,
        now: Date
    ) -> [UsageRecord] {
        let inclusiveDays = max(1, historyDays)
        let today = calendar.startOfDay(for: now)
        guard let firstDay = calendar.date(
            byAdding: .day,
            value: -(inclusiveDays - 1),
            to: today
        ) else {
            return records
        }
        let firstDayString = dayFormatter.string(from: firstDay)
        let todayString = dayFormatter.string(from: today)
        return records.filter {
            $0.date >= firstDayString && $0.date <= todayString
        }
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

        while try autoreleasepool(invoking: { () throws -> Bool in
            guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else {
                return false
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
            return true
        }) {}

        if !discardingOversizedLine,
           !buffer.isEmpty,
           buffer.count <= maxRelevantLineBytes {
            processLine(buffer)
        }
    }

    @discardableResult
    private static func forEachCompleteLine(
        in url: URL,
        fromOffset offset: UInt64,
        matchingAny markers: [String] = [],
        _ body: (String) -> Void
    ) throws -> UInt64 {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)

        let newline = Data([0x0A])
        let markerData = markers.map { Data($0.utf8) }
        var buffer = Data()
        buffer.reserveCapacity(128 * 1024)
        var discardingOversizedLine = false
        var discardedIncompleteBytes = 0
        var processedSize = offset

        func processLine(_ lineData: Data) {
            guard lineMatches(lineData, markers: markerData),
                  let line = String(data: lineData, encoding: .utf8),
                  !line.isEmpty
            else {
                return
            }
            body(line)
        }

        while try autoreleasepool(invoking: { () throws -> Bool in
            guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else {
                return false
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
                    processLine(buffer.subdata(in: lineStart..<lineEnd))
                }
                consumedEnd = range.upperBound
                lineStart = range.upperBound
                searchRange = lineStart..<buffer.endIndex
            }

            if consumedEnd > buffer.startIndex {
                let consumedBytes = buffer.distance(from: buffer.startIndex, to: consumedEnd)
                processedSize += UInt64(discardedIncompleteBytes + consumedBytes)
                discardedIncompleteBytes = 0
                buffer.removeSubrange(buffer.startIndex..<consumedEnd)
            }

            if buffer.count > maxRelevantLineBytes {
                discardingOversizedLine = true
                discardedIncompleteBytes += buffer.count
                buffer.removeAll(keepingCapacity: true)
            }
            return true
        }) {}

        return processedSize
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
        func value(_ keys: [String]) -> Int {
            for key in keys where raw.keys.contains(key) {
                return max(0, integerValue(raw[key] as Any))
            }
            return 0
        }

        let explicitTotal = ["total_tokens", "total"].first(where: { raw.keys.contains($0) })
            .map { max(0, integerValue(raw[$0] as Any)) }
        return canonicalUsageCounts(
            rawInputTokens: value(["input_tokens", "input"]),
            outputTokens: value(["output_tokens", "output"]),
            cacheCreationInputTokens: value(["cache_creation_input_tokens"]),
            cacheReadInputTokens: value(["cache_read_input_tokens", "cached_input_tokens", "cached"]),
            reasoningOutputTokens: value(["reasoning_output_tokens", "reasoning_tokens", "thoughts"]),
            inputIncludesCachedTokens: false,
            explicitTotalTokens: explicitTotal
        )
    }

    private static func normalizeCodexUsage(_ raw: [String: Any]) -> TokenUsageCounts {
        func value(_ keys: [String]) -> Int {
            for key in keys where raw.keys.contains(key) {
                return max(0, integerValue(raw[key] as Any))
            }
            return 0
        }

        let input = value(["input_tokens", "input"])
        let output = value(["output_tokens", "output"])
        let cached = value(["cached_input_tokens", "cache_read_input_tokens", "cached"])
        let reasoning = value(["reasoning_output_tokens", "reasoning_tokens", "thoughts"])
        let explicitTotal = ["total_tokens", "total"].first(where: { raw.keys.contains($0) })
            .map { max(0, integerValue(raw[$0] as Any)) }
        return canonicalUsageCounts(
            rawInputTokens: input,
            outputTokens: output,
            cacheCreationInputTokens: value(["cache_creation_input_tokens", "cache_write_input_tokens"]),
            cacheReadInputTokens: cached,
            reasoningOutputTokens: reasoning,
            inputIncludesCachedTokens: true,
            explicitTotalTokens: explicitTotal,
            explicitTotalIsAuthoritative: true
        )
    }

    private static func canonicalUsageCounts(
        rawInputTokens: Int,
        outputTokens: Int,
        cacheCreationInputTokens: Int = 0,
        cacheReadInputTokens: Int = 0,
        reasoningOutputTokens: Int = 0,
        inputIncludesCachedTokens: Bool,
        explicitTotalTokens: Int? = nil,
        explicitTotalIsAuthoritative: Bool = false
    ) -> TokenUsageCounts {
        let rawInput = max(0, rawInputTokens)
        let output = max(0, outputTokens)
        let cacheCreation = max(0, cacheCreationInputTokens)
        let cacheRead = max(0, cacheReadInputTokens)
        let reasoning = max(0, reasoningOutputTokens)
        let input = rawInput + (inputIncludesCachedTokens ? 0 : cacheCreation + cacheRead)
        let derivedTotal = input + output
        let explicitTotal = max(0, explicitTotalTokens ?? 0)
        let total = explicitTotalIsAuthoritative && explicitTotal > 0
            ? explicitTotal
            : (derivedTotal > 0 ? derivedTotal : explicitTotal)
        return TokenUsageCounts(
            inputTokens: input,
            outputTokens: output,
            cacheCreationInputTokens: cacheCreation,
            cacheReadInputTokens: cacheRead,
            reasoningOutputTokens: reasoning,
            totalTokens: total
        )
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

    private static func dayString(for event: CodexTokenEvent) -> String? {
        if let timestamp = event.timestampEpoch {
            return dayFormatter.string(from: Date(timeIntervalSince1970: timestamp))
        }
        return event.timestamp.flatMap(dayString(fromISO:))
    }

    private static func hour(fromEpoch value: TimeInterval) -> Int {
        calendar.component(.hour, from: Date(timeIntervalSince1970: value))
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

    private static func ccSwitchFreshInputTokens(
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

    private static func sqliteJSONRows(database: URL, query: String) -> [[String: Any]]? {
        SQLiteReadonly.jsonRows(database: database, query: query)
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
            return costByParts(usage: usage, input: 5, output: 25, cacheCreation: 6.25, cacheRead: 0.5)
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
        let cacheCreation = max(0, usage.cacheCreationInputTokens)
        let uncachedInput = max(0, usage.inputTokens - cached - cacheCreation)
        if uncachedInput == 0,
           cached == 0,
           cacheCreation == 0,
           usage.outputTokens == 0,
           usage.totalTokens > 0 {
            return Double(usage.totalTokens) / 1_000_000 * input
        }
        return Double(uncachedInput + cacheCreation) / 1_000_000 * input
            + Double(cached) / 1_000_000 * cachedInput
            + Double(usage.outputTokens) / 1_000_000 * output
    }

    private static func costByParts(
        usage: TokenUsageCounts,
        input: Double,
        output: Double,
        cacheCreation: Double,
        cacheRead: Double
    ) -> Double {
        let uncachedInput = max(
            0,
            usage.inputTokens - usage.cacheCreationInputTokens - usage.cacheReadInputTokens
        )
        return Double(uncachedInput) / 1_000_000 * input
            + Double(usage.outputTokens) / 1_000_000 * output
            + Double(usage.cacheCreationInputTokens) / 1_000_000 * cacheCreation
            + Double(usage.cacheReadInputTokens) / 1_000_000 * cacheRead
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

private struct CodexCollectionOutcome {
    var result: CollectorResult
    var usedIncrementalStore: Bool
}

private struct PendingCodexSession {
    var path: URL
    var metadata: (size: UInt64, modificationTime: TimeInterval)
    var fingerprint: String
    var validationFingerprint: String? = nil
    var scan: CodexSessionScan
}

private struct StoredCodexSessionMetadata {
    var size: UInt64
    var modificationTime: TimeInterval
    var fingerprint: String
    var validationFingerprint: String?
    var sessionID: String
}

private struct CodexCachedSession {
    var path: String
    var size: UInt64
    var modificationTime: TimeInterval
    var fingerprint: String
    var validationFingerprint: String? = nil
    var sessionID: String
    var createdAtEpoch: TimeInterval?
    var parentSessionID: String?
    var anchors: [CodexAnchor]
    var records: [UsageRecord]
    var summaryRecords: [UsageRecord]
    var cursor: CodexSessionCursor
    var diagnostics: CodexCollectionDiagnostics

    func hasSameStoredAccounting(as other: CodexCachedSession) -> Bool {
        path == other.path
            && size == other.size
            && abs(modificationTime - other.modificationTime) < 0.001
            && fingerprint == other.fingerprint
            && sessionID == other.sessionID
            && createdAtEpoch == other.createdAtEpoch
            && parentSessionID == other.parentSessionID
            && anchors == other.anchors
            && records == other.records
            && summaryRecords == other.summaryRecords
            && cursor == other.cursor
            && diagnostics == other.diagnostics
    }
}

private struct CodexCachedContribution {
    var records: [UsageRecord]
    var recordCount: Int
    var diagnostics: CodexCollectionDiagnostics
}

private struct CodexSummaryKey: Hashable {
    var date: String
    var model: String
    var hour: Int?
}

private struct CodexSummaryAccumulator {
    var timestamp: String?
    var timestampEpoch: TimeInterval?
    var usage = TokenUsageCounts()
    var modelRequestCount = 0
    var toolCallCount = 0

    mutating func add(_ record: UsageRecord) {
        timestamp = timestamp ?? record.timestamp
        timestampEpoch = timestampEpoch ?? record.timestampEpoch
        usage.add(record.usage)
        modelRequestCount += max(0, record.modelRequestCount)
        toolCallCount += max(0, record.toolCallCount)
    }
}

private enum CodexIncrementalStoreError: LocalizedError {
    case sqlite(String)
    case corruptPayload(String)
    case unstableSource(String)
    case incompleteCache(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case let .sqlite(message):
            return "Incremental cache error: \(message)"
        case let .corruptPayload(context):
            return "Incremental cache payload is corrupt: \(context)"
        case .unstableSource:
            return "A Codex session changed while it was being collected."
        case let .incompleteCache(expected, actual):
            return "Incremental cache is incomplete (expected \(expected), got \(actual))."
        }
    }

    var shouldRebuildCache: Bool {
        switch self {
        case .corruptPayload:
            return true
        case let .sqlite(message):
            let normalized = message.lowercased()
            return normalized.contains("not a database")
                || normalized.contains("database disk image is malformed")
                || normalized.contains("database malformed")
        case .incompleteCache:
            return true
        case .unstableSource:
            return false
        }
    }
}

private final class CodexIncrementalStore {
    private static let schemaVersion: Int32 = 6
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private var database: OpaquePointer?
    private var stagingTransactionActive = false

    static func discardDatabase(at url: URL) {
        let fileManager = FileManager.default
        for path in [url.path, url.path + "-wal", url.path + "-shm"] {
            guard fileManager.fileExists(atPath: path) else { continue }
            try? fileManager.removeItem(atPath: path)
        }
    }

    init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let database { sqlite3_close(database) }
            database = nil
            throw CodexIncrementalStoreError.sqlite(message)
        }
        do {
            sqlite3_busy_timeout(database, 2_000)
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=NORMAL")
            try migrateIfNeeded()
        } catch {
            if let database {
                sqlite3_close(database)
            }
            database = nil
            throw error
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func metadataByPath() throws -> [String: StoredCodexSessionMetadata] {
        let statement = try prepare(
            """
            SELECT path, size, modification_time, fingerprint,
                   validation_fingerprint, session_id
            FROM codex_sessions
            """
        )
        defer { sqlite3_finalize(statement) }
        var result = [String: StoredCodexSessionMetadata]()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let path = columnText(statement, index: 0),
                  let fingerprint = columnText(statement, index: 3),
                  let sessionID = columnText(statement, index: 5)
            else { continue }
            result[path] = StoredCodexSessionMetadata(
                size: UInt64(max(0, sqlite3_column_int64(statement, 1))),
                modificationTime: sqlite3_column_double(statement, 2),
                fingerprint: fingerprint,
                validationFingerprint: columnText(statement, index: 4),
                sessionID: sessionID
            )
        }
        try checkFinalStep(statement)
        return result
    }

    func childPaths(parentSessionID: String) throws -> [String] {
        let statement = try prepare(
            "SELECT path FROM codex_sessions WHERE parent_session_id = ? ORDER BY path"
        )
        defer { sqlite3_finalize(statement) }
        bind(parentSessionID, to: statement, index: 1)
        var result = [String]()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let path = columnText(statement, index: 0) {
                result.append(path)
            }
        }
        try checkFinalStep(statement)
        return result
    }

    func childPaths(
        parentSessionID: String,
        createdAtOnOrAfter timestamp: TimeInterval
    ) throws -> [String] {
        let statement = try prepare(
            """
            SELECT path FROM codex_sessions
            WHERE parent_session_id = ?
              AND (created_at_epoch IS NULL OR created_at_epoch >= ?)
            ORDER BY path
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(parentSessionID, to: statement, index: 1)
        sqlite3_bind_double(statement, 2, timestamp)
        var result = [String]()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let path = columnText(statement, index: 0) {
                result.append(path)
            }
        }
        try checkFinalStep(statement)
        return result
    }

    func anchors(sessionID: String) throws -> [CodexAnchor]? {
        let statement = try prepare(
            "SELECT anchors FROM codex_sessions WHERE session_id = ? ORDER BY path LIMIT 1"
        )
        defer { sqlite3_finalize(statement) }
        bind(sessionID, to: statement, index: 1)
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW,
              let data = columnData(statement, index: 0)
        else {
            throw currentError()
        }
        return try decode([CodexAnchor].self, from: data, context: "anchors")
    }

    func session(path: String) throws -> CodexCachedSession? {
        let statement = try prepare(
            """
            SELECT size, modification_time, fingerprint, validation_fingerprint,
                   session_id, created_at_epoch, parent_session_id, anchors,
                   records, COALESCE(summary_records, records), cursor, diagnostics
            FROM codex_sessions WHERE path = ? LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(path, to: statement, index: 1)
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW,
              let fingerprint = columnText(statement, index: 2),
              let sessionID = columnText(statement, index: 4),
              let anchorsData = columnData(statement, index: 7),
              let recordsData = columnData(statement, index: 8),
              let summaryData = columnData(statement, index: 9),
              let cursorData = columnData(statement, index: 10),
              let diagnosticsData = columnData(statement, index: 11)
        else { return nil }
        return CodexCachedSession(
            path: path,
            size: UInt64(max(0, sqlite3_column_int64(statement, 0))),
            modificationTime: sqlite3_column_double(statement, 1),
            fingerprint: fingerprint,
            validationFingerprint: columnText(statement, index: 3),
            sessionID: sessionID,
            createdAtEpoch: sqlite3_column_type(statement, 5) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 5),
            parentSessionID: columnText(statement, index: 6),
            anchors: try decode([CodexAnchor].self, from: anchorsData, context: "session anchors"),
            records: try decode([UsageRecord].self, from: recordsData, context: "session records"),
            summaryRecords: try decode([UsageRecord].self, from: summaryData, context: "session summaries"),
            cursor: try decode(CodexSessionCursor.self, from: cursorData, context: "session cursor"),
            diagnostics: try decode(
                CodexCollectionDiagnostics.self,
                from: diagnosticsData,
                context: "session diagnostics"
            )
        )
    }

    func beginStaging() throws {
        guard !stagingTransactionActive else {
            throw CodexIncrementalStoreError.sqlite("staging transaction already active")
        }
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try execute("DELETE FROM codex_staged_scans")
            try execute("DELETE FROM codex_staged_sessions")
            stagingTransactionActive = true
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func abortStaging() {
        guard stagingTransactionActive else { return }
        try? execute("ROLLBACK")
        stagingTransactionActive = false
    }

    func updateValidationFingerprint(_ fingerprint: String, path: String) throws {
        guard stagingTransactionActive else {
            throw CodexIncrementalStoreError.sqlite("staging transaction is not active")
        }
        let statement = try prepare(
            "UPDATE codex_sessions SET validation_fingerprint = ? WHERE path = ?"
        )
        defer { sqlite3_finalize(statement) }
        bind(fingerprint, to: statement, index: 1)
        bind(path, to: statement, index: 2)
        try requireDone(statement)
    }

    func stage(
        scan item: PendingCodexSession,
        anchors: [CodexAnchor],
        createdAtEpoch: TimeInterval?
    ) throws {
        guard stagingTransactionActive else {
            throw CodexIncrementalStoreError.sqlite("staging transaction is not active")
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let anchors = try encoder.encode(anchors)
        let scan = try encoder.encode(item.scan)
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO codex_staged_scans (
                path, size, modification_time, fingerprint, validation_fingerprint,
                session_id, created_at_epoch, parent_session_id, anchors, scan
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(item.path.path, to: statement, index: 1)
        sqlite3_bind_int64(statement, 2, sqlite3_int64(item.metadata.size))
        sqlite3_bind_double(statement, 3, item.metadata.modificationTime)
        bind(item.fingerprint, to: statement, index: 4)
        bind(item.validationFingerprint, to: statement, index: 5)
        bind(item.scan.canonicalSessionID, to: statement, index: 6)
        bind(createdAtEpoch, to: statement, index: 7)
        bind(item.scan.parentSessionID, to: statement, index: 8)
        bind(anchors, to: statement, index: 9)
        bind(scan, to: statement, index: 10)
        try requireDone(statement)
    }

    func stagedScanPaths() throws -> [String] {
        let statement = try prepare("SELECT path FROM codex_staged_scans ORDER BY path")
        defer { sqlite3_finalize(statement) }
        var paths = [String]()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let path = columnText(statement, index: 0) {
                paths.append(path)
            }
        }
        try checkFinalStep(statement)
        return paths
    }

    func stagedScan(path: String) throws -> PendingCodexSession? {
        let statement = try prepare(
            """
            SELECT size, modification_time, fingerprint, validation_fingerprint, scan
            FROM codex_staged_scans WHERE path = ? LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(path, to: statement, index: 1)
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW,
              let fingerprint = columnText(statement, index: 2),
              let scanData = columnData(statement, index: 4)
        else { throw currentError() }
        return PendingCodexSession(
            path: URL(fileURLWithPath: path),
            metadata: (
                size: UInt64(max(0, sqlite3_column_int64(statement, 0))),
                modificationTime: sqlite3_column_double(statement, 1)
            ),
            fingerprint: fingerprint,
            validationFingerprint: columnText(statement, index: 3),
            scan: try decode(CodexSessionScan.self, from: scanData, context: "staged scan")
        )
    }

    func stagedAnchors(sessionID: String) throws -> [CodexAnchor]? {
        for table in ["codex_staged_scans", "codex_staged_sessions"] {
            let statement = try prepare(
                "SELECT anchors FROM \(table) WHERE session_id = ? ORDER BY path LIMIT 1"
            )
            defer { sqlite3_finalize(statement) }
            bind(sessionID, to: statement, index: 1)
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { continue }
            guard status == SQLITE_ROW,
                  let data = columnData(statement, index: 0)
            else { throw currentError() }
            return try decode([CodexAnchor].self, from: data, context: "staged anchors")
        }
        return nil
    }

    func stage(session: CodexCachedSession) throws {
        guard stagingTransactionActive else {
            throw CodexIncrementalStoreError.sqlite("staging transaction is not active")
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let anchors = try encoder.encode(session.anchors)
        let records = try encoder.encode(session.records)
        let summaryRecords = try encoder.encode(session.summaryRecords)
        let cursor = try encoder.encode(session.cursor)
        let diagnostics = try encoder.encode(session.diagnostics)
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO codex_staged_sessions (
                path, size, modification_time, fingerprint, validation_fingerprint,
                session_id, created_at_epoch, parent_session_id, anchors, records,
                summary_records, record_count, cursor, diagnostics
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(session.path, to: statement, index: 1)
        sqlite3_bind_int64(statement, 2, sqlite3_int64(session.size))
        sqlite3_bind_double(statement, 3, session.modificationTime)
        bind(session.fingerprint, to: statement, index: 4)
        bind(session.validationFingerprint, to: statement, index: 5)
        bind(session.sessionID, to: statement, index: 6)
        bind(session.createdAtEpoch, to: statement, index: 7)
        bind(session.parentSessionID, to: statement, index: 8)
        bind(anchors, to: statement, index: 9)
        bind(records, to: statement, index: 10)
        bind(summaryRecords, to: statement, index: 11)
        sqlite3_bind_int64(statement, 12, sqlite3_int64(session.records.count))
        bind(cursor, to: statement, index: 13)
        bind(diagnostics, to: statement, index: 14)
        try requireDone(statement)
    }

    func commitStaged(deletedPaths: Set<String>) throws {
        guard stagingTransactionActive else {
            throw CodexIncrementalStoreError.sqlite("staging transaction is not active")
        }
        do {
            let stagedCount = try stagedSessionCount()
            let stagedPayloadBytes = try stagedSessionPayloadBytes()
            if !deletedPaths.isEmpty {
                let statement = try prepare("DELETE FROM codex_sessions WHERE path = ?")
                defer { sqlite3_finalize(statement) }
                for path in deletedPaths {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    bind(path, to: statement, index: 1)
                    try requireDone(statement)
                }
            }
            if stagedCount > 0 {
                try execute(
                    """
                    INSERT OR REPLACE INTO codex_sessions (
                        path, size, modification_time, fingerprint, validation_fingerprint,
                        session_id, created_at_epoch, parent_session_id, anchors, records,
                        summary_records, record_count, cursor, diagnostics
                    )
                    SELECT path, size, modification_time, fingerprint,
                           validation_fingerprint, session_id, created_at_epoch,
                           parent_session_id, anchors, records, summary_records,
                           record_count, cursor, diagnostics
                    FROM codex_staged_sessions
                    """
                )
            }
            if stagedCount > 0 || !deletedPaths.isEmpty {
                try execute(
                    """
                    INSERT INTO cache_meta(key, value) VALUES ('generation', '1')
                    ON CONFLICT(key) DO UPDATE SET value = CAST(value AS INTEGER) + 1
                    """
                )
                let logicalWriteBytes = stagedPayloadBytes * 2
                try execute(
                    """
                    INSERT INTO cache_meta(key, value)
                    VALUES ('last_logical_write_bytes', '\(logicalWriteBytes)')
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """
                )
            }
            try execute("DELETE FROM codex_staged_scans")
            try execute("DELETE FROM codex_staged_sessions")
            try execute("COMMIT")
            stagingTransactionActive = false
        } catch {
            try? execute("ROLLBACK")
            stagingTransactionActive = false
            throw error
        }
    }

    private func stagedSessionCount() throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM codex_staged_sessions")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw currentError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func stagedSessionPayloadBytes() throws -> Int {
        let statement = try prepare(
            """
            SELECT COALESCE(SUM(
                LENGTH(anchors) + LENGTH(records) + LENGTH(summary_records)
                + LENGTH(cursor) + LENGTH(diagnostics)
            ), 0)
            FROM codex_staged_sessions
            """
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw currentError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func sessionCount() throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM codex_sessions")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw currentError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func forEachContribution(
        detailed: Bool,
        _ body: (CodexCachedContribution) throws -> Void
    ) throws {
        let statement = try prepare(
            detailed
                ? "SELECT records, diagnostics, record_count FROM codex_sessions ORDER BY path"
                : """
                  SELECT CASE
                      WHEN session_id IN (
                          SELECT session_id FROM codex_sessions
                          GROUP BY session_id HAVING COUNT(*) > 1
                      ) THEN records
                      ELSE COALESCE(summary_records, records)
                    END,
                    diagnostics,
                    record_count
                  FROM codex_sessions
                  ORDER BY path
                  """
        )
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let recordsData = columnData(statement, index: 0),
                  let diagnosticsData = columnData(statement, index: 1)
            else { throw currentError() }
            try body(
                CodexCachedContribution(
                    records: try decode(
                        [UsageRecord].self,
                        from: recordsData,
                        context: "contribution records"
                    ),
                    recordCount: Int(sqlite3_column_int64(statement, 2)),
                    diagnostics: try decode(
                        CodexCollectionDiagnostics.self,
                        from: diagnosticsData,
                        context: "contribution diagnostics"
                    )
                )
            )
        }
        try checkFinalStep(statement)
    }

    func stats() throws -> CodexIncrementalCacheStats {
        let statement = try prepare(
            """
            SELECT
                COALESCE((SELECT CAST(value AS INTEGER) FROM cache_meta WHERE key = 'generation'), 0),
                COUNT(*),
                COALESCE(SUM(record_count), 0),
                COALESCE((
                    SELECT CAST(value AS INTEGER) FROM cache_meta
                    WHERE key = 'last_logical_write_bytes'
                ), 0)
            FROM codex_sessions
            """
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw currentError() }
        return CodexIncrementalCacheStats(
            generation: Int(sqlite3_column_int64(statement, 0)),
            sessions: Int(sqlite3_column_int64(statement, 1)),
            records: Int(sqlite3_column_int64(statement, 2)),
            lastLogicalWriteBytes: Int(sqlite3_column_int64(statement, 3))
        )
    }

    private func migrateIfNeeded() throws {
        guard database != nil else { throw CodexIncrementalStoreError.sqlite("database closed") }
        let current = userVersion()
        guard current >= 0, current <= Self.schemaVersion else {
            throw CodexIncrementalStoreError.sqlite("unsupported schema version \(current)")
        }
        try execute(
            """
            CREATE TABLE IF NOT EXISTS cache_meta (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            )
            """
        )
        if current > 0, current < Self.schemaVersion {
            // v0.1.48 is the first public incremental-cache release. Recreate
            // older development schemas so interim payloads cannot survive.
            try execute("DROP TABLE IF EXISTS codex_sessions")
            try execute("DROP TABLE IF EXISTS codex_staged_scans")
            try execute("DROP TABLE IF EXISTS codex_staged_sessions")
            try execute("DELETE FROM cache_meta")
        }
        try execute(
            """
            CREATE TABLE IF NOT EXISTS codex_sessions (
                path TEXT PRIMARY KEY NOT NULL,
                size INTEGER NOT NULL,
                modification_time REAL NOT NULL,
                fingerprint TEXT NOT NULL,
                validation_fingerprint TEXT,
                session_id TEXT NOT NULL,
                created_at_epoch REAL,
                parent_session_id TEXT,
                anchors BLOB NOT NULL,
                records BLOB NOT NULL,
                summary_records BLOB,
                record_count INTEGER NOT NULL,
                cursor BLOB,
                diagnostics BLOB NOT NULL
            )
            """
        )
        try execute(
            "CREATE INDEX IF NOT EXISTS codex_sessions_session_id ON codex_sessions(session_id)"
        )
        try execute(
            "CREATE INDEX IF NOT EXISTS codex_sessions_parent_id ON codex_sessions(parent_session_id)"
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS codex_staged_scans (
                path TEXT PRIMARY KEY NOT NULL,
                size INTEGER NOT NULL,
                modification_time REAL NOT NULL,
                fingerprint TEXT NOT NULL,
                validation_fingerprint TEXT,
                session_id TEXT NOT NULL,
                created_at_epoch REAL,
                parent_session_id TEXT,
                anchors BLOB NOT NULL,
                scan BLOB NOT NULL
            )
            """
        )
        try execute(
            "CREATE INDEX IF NOT EXISTS codex_staged_scans_session_id ON codex_staged_scans(session_id)"
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS codex_staged_sessions (
                path TEXT PRIMARY KEY NOT NULL,
                size INTEGER NOT NULL,
                modification_time REAL NOT NULL,
                fingerprint TEXT NOT NULL,
                validation_fingerprint TEXT,
                session_id TEXT NOT NULL,
                created_at_epoch REAL,
                parent_session_id TEXT,
                anchors BLOB NOT NULL,
                records BLOB NOT NULL,
                summary_records BLOB NOT NULL,
                record_count INTEGER NOT NULL,
                cursor BLOB NOT NULL,
                diagnostics BLOB NOT NULL
            )
            """
        )
        try execute("PRAGMA user_version = \(Self.schemaVersion)")
    }

    private func userVersion() -> Int32 {
        guard let statement = try? prepare("PRAGMA user_version") else { return -1 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return -1 }
        return sqlite3_column_int(statement, 0)
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw CodexIncrementalStoreError.sqlite("database closed") }
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(error)
            throw CodexIncrementalStoreError.sqlite(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else { throw CodexIncrementalStoreError.sqlite("database closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw currentError() }
        return statement
    }

    private func bind(_ value: String?, to statement: OpaquePointer, index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, Self.transient)
    }

    private func bind(_ value: TimeInterval?, to statement: OpaquePointer, index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_double(statement, index, value)
    }

    private func bind(_ data: Data, to statement: OpaquePointer, index: Int32) {
        _ = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), Self.transient)
        }
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        context: String
    ) throws -> T {
        do {
            return try PropertyListDecoder().decode(type, from: data)
        } catch {
            throw CodexIncrementalStoreError.corruptPayload(context)
        }
    }

    private func columnText(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func columnData(_ statement: OpaquePointer, index: Int32) -> Data? {
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count >= 0 else { return nil }
        if count == 0 { return Data() }
        guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
        return Data(bytes: bytes, count: count)
    }

    private func requireDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw currentError() }
    }

    private func checkFinalStep(_ statement: OpaquePointer) throws {
        let status = sqlite3_errcode(database)
        guard status == SQLITE_OK || status == SQLITE_DONE else { throw currentError() }
    }

    private func currentError() -> CodexIncrementalStoreError {
        guard let database else { return .sqlite("database closed") }
        return .sqlite(String(cString: sqlite3_errmsg(database)))
    }
}

private struct CollectorCache: Codable {
    static let currentVersion = UsageCollector.codexAccountingRevision

    var version = currentVersion
    var files: [String: CachedUsageFile] = [:]
}

private struct CollectorCacheLoad {
    var cache: CollectorCache
    var recalibratedFromRevision: Int?
}

private struct CachedUsageFile: Codable {
    var tool: String
    var size: UInt64
    var modificationTime: TimeInterval
    var records: [UsageRecord]
    var codexScan: CodexSessionScan? = nil
    var contentFingerprint: String? = nil
}

private struct CodexSessionScan: Codable {
    var canonicalSessionID: String
    var createdAt: String?
    var parentSessionID: String?
    var sourcePath: String
    var events: [CodexTokenEvent]
    var finalModel: String? = nil
    var relevantLineCount: Int? = nil
}

private struct CodexTokenEvent: Codable {
    var timestamp: String?
    var timestampEpoch: TimeInterval? = nil
    var model: String
    var cumulativePresent: Bool
    var cumulative: TokenUsageCounts?
    var last: TokenUsageCounts?
    var modelContextWindow: Int
    var lineNumber: Int
}

private struct CodexAnchor: Codable, Equatable {
    var timestamp: TimeInterval
    var usage: TokenUsageCounts
}

private struct CodexDeltaCursor {
    var hasCumulativeSchema: Bool
    var previousCumulative: TokenUsageCounts?
    var epoch: Int
}

private struct CodexSessionCursor: Codable, Equatable {
    var currentModel: String
    var relevantLineNumber: Int
    var hasCumulativeSchema: Bool
    var previousCumulative: TokenUsageCounts?
    var epoch: Int
}

private struct CodexSessionTail {
    var events: [CodexTokenEvent]
    var currentModel: String
    var relevantLineNumber: Int
    var processedSize: UInt64
    var modificationTime: TimeInterval
    var fingerprint: String
}

private struct CodexCollectionDiagnostics: Codable, Equatable {
    var rawRecords = 0
    var exactRecords = 0
    var legacyRecords = 0
    var duplicateRecords = 0
    var counterResets = 0
    var inheritedRecords = 0
    var inheritedTokens = 0
    var skippedRecords = 0
    var unknownBreakdownRecords = 0

    mutating func add(_ other: CodexCollectionDiagnostics) {
        rawRecords += other.rawRecords
        exactRecords += other.exactRecords
        legacyRecords += other.legacyRecords
        duplicateRecords += other.duplicateRecords
        counterResets += other.counterResets
        inheritedRecords += other.inheritedRecords
        inheritedTokens += other.inheritedTokens
        skippedRecords += other.skippedRecords
        unknownBreakdownRecords += other.unknownBreakdownRecords
    }
}

private struct UsageRecord: Codable, Equatable {
    var date: String
    var timestamp: String?
    var timestampEpoch: TimeInterval? = nil
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
    var modelRequestCount = 1
    var toolCallCount = 0

    enum CodingKeys: String, CodingKey {
        case date
        case timestamp
        case timestampEpoch
        case tool
        case model
        case usage
        case costUSD
        case source
        case requestID
        case sessionID
        case responseID
        case sourcePath
        case lineNumber
        case dataSource
        case modelRequestCount
        case toolCallCount
    }

    init(
        date: String,
        timestamp: String?,
        timestampEpoch: TimeInterval? = nil,
        tool: String,
        model: String,
        usage: TokenUsageCounts,
        costUSD: Double? = nil,
        source: UsageRecordSource = .unknown,
        requestID: String? = nil,
        sessionID: String? = nil,
        responseID: String? = nil,
        sourcePath: String? = nil,
        lineNumber: Int? = nil,
        dataSource: String? = nil,
        modelRequestCount: Int = 1,
        toolCallCount: Int = 0
    ) {
        self.date = date
        self.timestamp = timestamp
        self.timestampEpoch = timestampEpoch
        self.tool = tool
        self.model = model
        self.usage = usage
        self.costUSD = costUSD
        self.source = source
        self.requestID = requestID
        self.sessionID = sessionID
        self.responseID = responseID
        self.sourcePath = sourcePath
        self.lineNumber = lineNumber
        self.dataSource = dataSource
        self.modelRequestCount = modelRequestCount
        self.toolCallCount = toolCallCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        timestampEpoch = try container.decodeIfPresent(TimeInterval.self, forKey: .timestampEpoch)
        tool = try container.decode(String.self, forKey: .tool)
        model = try container.decode(String.self, forKey: .model)
        usage = try container.decode(TokenUsageCounts.self, forKey: .usage)
        costUSD = try container.decodeIfPresent(Double.self, forKey: .costUSD)
        source = try container.decodeIfPresent(UsageRecordSource.self, forKey: .source) ?? .unknown
        requestID = try container.decodeIfPresent(String.self, forKey: .requestID)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        responseID = try container.decodeIfPresent(String.self, forKey: .responseID)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
        lineNumber = try container.decodeIfPresent(Int.self, forKey: .lineNumber)
        dataSource = try container.decodeIfPresent(String.self, forKey: .dataSource)
        modelRequestCount = try container.decodeIfPresent(Int.self, forKey: .modelRequestCount) ?? 1
        toolCallCount = try container.decodeIfPresent(Int.self, forKey: .toolCallCount) ?? 0
    }
}

private enum UsageRecordSource: String, Codable, Equatable {
    case nativeCodex
    case nativeCodexSQLite
    case nativeClaudeCode
    case ccSwitchProxy
    case zcode
    case hermes
    case workbuddy
    case deepSeekHarness
    case autoclaw
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

private struct DeepSeekHarnessFileResult {
    var records: [UsageRecord]
    var partialTail: Bool
}

private struct DeepSeekHarnessCandidate {
    var key: String?
    var date: String
    var timestamp: String?
    var timestampEpoch: TimeInterval?
    var model: String
    var usage: TokenUsageCounts
    var requestID: String?
    var sessionID: String?
    var sourcePath: String?
    var lineNumber: Int?
    var dataSource: String?
    var priority: Int

    init(
        key: String,
        date: String,
        timestamp: String?,
        timestampEpoch: TimeInterval?,
        model: String,
        usage: TokenUsageCounts,
        requestID: String?,
        sessionID: String?,
        sourcePath: String?,
        lineNumber: Int?,
        dataSource: String?,
        priority: Int
    ) {
        self.key = key
        self.date = date
        self.timestamp = timestamp
        self.timestampEpoch = timestampEpoch
        self.model = model
        self.usage = usage
        self.requestID = requestID
        self.sessionID = sessionID
        self.sourcePath = sourcePath
        self.lineNumber = lineNumber
        self.dataSource = dataSource
        self.priority = priority
    }

    init(record: UsageRecord) {
        self.key = record.requestID
        self.date = record.date
        self.timestamp = record.timestamp
        self.timestampEpoch = record.timestampEpoch
        self.model = record.model
        self.usage = record.usage
        self.requestID = record.requestID
        self.sessionID = record.sessionID
        self.sourcePath = record.sourcePath
        self.lineNumber = record.lineNumber
        self.dataSource = record.dataSource
        self.priority = 2
    }

    var record: UsageRecord {
        UsageRecord(
            date: date,
            timestamp: timestamp,
            timestampEpoch: timestampEpoch,
            tool: "DeepSeek Harness",
            model: model,
            usage: usage,
            source: .deepSeekHarness,
            requestID: requestID,
            sessionID: sessionID,
            sourcePath: sourcePath,
            lineNumber: lineNumber,
            dataSource: dataSource
        )
    }

    func isPreferred(over other: DeepSeekHarnessCandidate) -> Bool {
        if priority != other.priority { return priority > other.priority }
        if (timestampEpoch ?? 0) != (other.timestampEpoch ?? 0) {
            return (timestampEpoch ?? 0) > (other.timestampEpoch ?? 0)
        }
        return (lineNumber ?? 0) > (other.lineNumber ?? 0)
    }
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

private struct TokenUsageCounts: Codable, Equatable {
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

    var fingerprint: String {
        [
            totalTokens,
            inputTokens,
            cacheReadInputTokens,
            outputTokens,
            reasoningOutputTokens,
            cacheCreationInputTokens
        ].map(String.init).joined(separator: ":")
    }

    var cacheCoverageComplete: Bool {
        inputTokens >= 0
            && outputTokens >= 0
            && cacheCreationInputTokens >= 0
            && cacheReadInputTokens >= 0
            && reasoningOutputTokens >= 0
            && totalTokens == inputTokens + outputTokens
            && cacheCreationInputTokens + cacheReadInputTokens <= inputTokens
            && reasoningOutputTokens <= outputTokens
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
    var modelCosts: [String: Double] = [:]
    var totalTokens = 0
    var cost = 0.0

    mutating func add(record: UsageRecord, cost: Double) {
        tools[record.tool, default: 0] += record.usage.totalTokens
        models[record.model, default: 0] += record.usage.totalTokens
        modelCosts[record.model, default: 0] += cost
        totalTokens += record.usage.totalTokens
        self.cost += cost
    }
}

private struct AgentWorkAccumulator {
    var date: String
    var totalTokens = 0
    var inputTokens = 0
    var cachedInputTokens = 0
    var outputTokens = 0
    var cacheCoverageComplete = true
    var unbucketedTokens = 0
    var activeHours = Set<Int>()
    var modelRequestCount = 0
    var toolCallCount = 0
    var sources: [String: AgentWorkSourceAccumulator] = [:]
    var hourlySources: [Int: [String: AgentWorkHourlySourceAccumulator]] = [:]

    mutating func add(record: UsageRecord, hour: Int?) {
        totalTokens += record.usage.totalTokens
        inputTokens += record.usage.inputTokens
        cachedInputTokens += record.usage.cacheReadInputTokens
        outputTokens += record.usage.outputTokens
        cacheCoverageComplete = cacheCoverageComplete && record.usage.cacheCoverageComplete
        if let hour {
            activeHours.insert(hour)
            var sourceRows = hourlySources[hour] ?? [:]
            sourceRows[record.tool, default: AgentWorkHourlySourceAccumulator(source: record.tool)]
                .add(record: record)
            hourlySources[hour] = sourceRows
        } else {
            unbucketedTokens += record.usage.totalTokens
        }
        modelRequestCount += max(0, record.modelRequestCount)
        toolCallCount += max(0, record.toolCallCount)
        sources[record.tool, default: AgentWorkSourceAccumulator(source: record.tool)]
            .add(record: record)
    }

    var dailyAgentWork: DailyAgentWork {
        DailyAgentWork(
            date: date,
            totalTokens: totalTokens,
            activeHours: activeHours.count,
            modelRequestCount: modelRequestCount,
            toolCallCount: toolCallCount,
            sources: sources.values
                .filter { $0.tokens > 0 }
                .sorted { $0.tokens > $1.tokens }
                .map(\.agentWorkSource),
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            cacheCoverageComplete: cacheCoverageComplete,
            hourlyBuckets: (0..<24).map { hour in
                AgentWorkHourBucket(
                    hour: hour,
                    sources: (hourlySources[hour] ?? [:]).values
                        .filter { $0.tokens > 0 }
                        .sorted {
                            if $0.tokens == $1.tokens {
                                return $0.source < $1.source
                            }
                            return $0.tokens > $1.tokens
                        }
                        .map(\.hourlySource)
                )
            },
            unbucketedTokens: unbucketedTokens
        )
    }
}

private struct AgentWorkSourceAccumulator {
    var source: String
    var tokens = 0
    var modelRequestCount = 0
    var toolCallCount = 0

    mutating func add(record: UsageRecord) {
        tokens += record.usage.totalTokens
        modelRequestCount += max(0, record.modelRequestCount)
        toolCallCount += max(0, record.toolCallCount)
    }

    var agentWorkSource: AgentWorkSource {
        AgentWorkSource(
            source: source,
            tokens: tokens,
            modelRequestCount: modelRequestCount,
            toolCallCount: toolCallCount
        )
    }
}

private struct AgentWorkHourlySourceAccumulator {
    var source: String
    var tokens = 0
    var inputTokens = 0
    var cachedInputTokens = 0
    var outputTokens = 0
    var cacheCoverageComplete = true

    mutating func add(record: UsageRecord) {
        tokens += record.usage.totalTokens
        inputTokens += record.usage.inputTokens
        cachedInputTokens += record.usage.cacheReadInputTokens
        outputTokens += record.usage.outputTokens
        cacheCoverageComplete = cacheCoverageComplete && record.usage.cacheCoverageComplete
    }

    var hourlySource: AgentWorkHourlySource {
        AgentWorkHourlySource(
            source: source,
            tokens: tokens,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            cacheCoverageComplete: cacheCoverageComplete
        )
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
