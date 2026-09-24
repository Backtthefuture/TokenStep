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
    // Optional so checkpoints written before the zone was recorded still decode;
    // they compare unequal and trigger one fresh collection.
    var timeZone: String?
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

    // Fixed for the life of the process: the helper is relaunched for every collection.
    static let timezone = TokenStepClock.timeZone
    static let maxRelevantLineBytes = 1_048_576
    static let ccSwitchSourceName = "CC Switch Proxy"

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
        let claude = collectClaudeCode(
            cache: &cache,
            livePaths: &livePaths,
            modifiedSince: sourceCutoff,
            forceFullValidation: forceFullValidation
        )
        let zCode = includeExperimentalAgentSources
            ? collectZCodeUsage(databaseURL: zCodeDatabaseURL)
            : CollectorResult(records: [], source: SourceInfo(status: "disabled", files: nil, records: 0))
        let hermes = includeExperimentalAgentSources
            ? collectHermesUsage(databaseURL: hermesDatabaseURL)
            : CollectorResult(records: [], source: SourceInfo(status: "disabled", files: nil, records: 0))
        let workBuddy = includeExperimentalAgentSources
            ? collectWorkBuddyUsage(rootURLs: workBuddyRootURLs, modifiedSince: sourceCutoff)
            : CollectorResult(records: [], source: SourceInfo(status: "disabled", files: nil, records: 0))
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
            deduped.records + zCode.records + hermes.records + workBuddy.records,
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
                "WorkBuddy": workBuddy.source
            ]
        )
    }

    static func collectionState(
        historyDays: Int,
        includeExperimentalAgentSources: Bool,
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
        }

        let files = Dictionary(grouping: urls, by: \.path)
            .compactMap { _, duplicates in duplicates.first.flatMap(collectionFileState) }
            .sorted { $0.path < $1.path }
        return UsageCollectionState(
            historyDays: historyDays,
            includesExperimentalAgentSources: includeExperimentalAgentSources,
            windowDay: dayFormatter.string(from: now),
            timeZone: timezone.identifier,
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

    static func accountingComparisonDiagnostics(
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

    static func anonymousPathHash(_ path: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    static func existingDatabaseFiles(_ databases: [URL]) -> [URL] {
        databases.flatMap { database in
            [
                database,
                URL(fileURLWithPath: database.path + "-wal")
            ].filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    static func collectionFileState(_ url: URL) -> UsageCollectionFileState? {
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

    /// Collects Claude Code usage through a persistent collector cache, the way
    /// repeated background collections do.
    static func collectClaudeCodeWithCacheForTests(
        rootURL: URL,
        cacheURL: URL,
        forceFullValidation: Bool = false
    ) -> UsageSnapshot {
        var cache = loadCurrentCache(at: cacheURL)
        var livePaths = Set<String>()
        let result = collectClaudeCode(
            cache: &cache,
            livePaths: &livePaths,
            rootURL: rootURL,
            modifiedSince: nil,
            forceFullValidation: forceFullValidation
        )
        cache.files = cache.files.filter { livePaths.contains($0.key) }
        saveCache(cache, to: cacheURL)
        return aggregate(records: result.records, sources: ["Claude Code": result.source])
    }

    static func collectorCacheIsReusableForTests(cacheURL: URL) -> Bool {
        !loadCache(at: cacheURL).cache.files.isEmpty
    }

    static func collectUsageSnapshotForTests(
        codexRoots: [URL] = [],
        claudeRootURL: URL? = nil,
        ccSwitchDatabaseURL: URL? = nil,
        zCodeDatabaseURL: URL? = nil,
        hermesDatabaseURL: URL? = nil,
        workBuddyRootURLs: [URL]? = nil,
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
        let deduped = deduplicateCrossSource(
            nativeRecords: codex.records + claude.records,
            proxyRecords: ccSwitch.records
        )
        ccSwitch.source = sourceInfo(ccSwitch.source, annotatedWith: deduped)
        let allRecords = deduped.records + zCode.records + hermes.records + workBuddy.records
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
                "WorkBuddy": workBuddy.source
            ]
        )
    }
}
