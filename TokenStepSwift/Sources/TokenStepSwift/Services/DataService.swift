import Darwin
import Foundation

enum DataService {
    private static let helperName = "TokenStepHelper"
    private static let helperTimeoutSeconds: TimeInterval = 120
    private static let legacyCodexAccountingRevision = 5

    static func loadSnapshot() throws -> UsageSnapshot {
        let data = try Data(contentsOf: AppPaths.usageJSON)
        return try JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    static func loadSettings() -> TokenStepSettings {
        guard let data = try? Data(contentsOf: AppPaths.settingsJSON),
              let settings = try? JSONDecoder().decode(TokenStepSettings.self, from: data)
        else {
            return .defaults
        }
        return normalize(settings)
    }

    static func loadSettingsForAppLaunch() -> TokenStepSettings {
        let loaded = loadSettings()
        let voyageMarkerExists = FileManager.default.fileExists(
            atPath: AppPaths.voyageThemeMigrationMarker.path
        )
        let migrated = applyingVoyageThemeMigration(
            loaded,
            markerExists: voyageMarkerExists
        )
        let odysseyMarkerExists = FileManager.default.fileExists(
            atPath: AppPaths.odysseyThemePackMigrationMarker.path
        )
        guard !voyageMarkerExists || !odysseyMarkerExists else { return migrated }

        do {
            // 0.2.4 persists the decoded theme-pack defaults even when the 0.2.3
            // JSON did not yet contain classic_theme or odyssey_chapter.
            try saveSettings(migrated)
            try FileManager.default.createDirectory(
                at: AppPaths.voyageThemeMigrationMarker.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !voyageMarkerExists {
                try Data("0.2.3\n".utf8).write(
                    to: AppPaths.voyageThemeMigrationMarker,
                    options: .atomic
                )
            }
            if !odysseyMarkerExists {
                try Data("0.2.4\n".utf8).write(
                    to: AppPaths.odysseyThemePackMigrationMarker,
                    options: .atomic
                )
            }
        } catch {
            // Keep the in-memory skin selection active even if persistence is temporarily unavailable.
        }
        return migrated
    }

    static func applyingVoyageThemeMigration(
        _ settings: TokenStepSettings,
        markerExists: Bool
    ) -> TokenStepSettings {
        guard !markerExists else { return settings }
        var migrated = settings
        migrated.theme = .voyage
        return migrated
    }

    static func requiresImmediateCodexRecalibration(_ snapshot: UsageSnapshot) -> Bool {
        guard let codex = snapshot.sources["Codex"],
              (codex.records ?? 0) > 0
        else {
            return false
        }

        let storedRevision = codex.accountingRevision ?? legacyCodexAccountingRevision
        return storedRevision < UsageCollector.codexAccountingRevision
    }

    static func saveSettings(_ settings: TokenStepSettings) throws {
        let normalized = normalize(settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(normalized)
        try FileManager.default.createDirectory(
            at: AppPaths.settingsJSON.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: AppPaths.settingsJSON, options: .atomic)
    }

    @discardableResult
    static func runCollector(
        historyDays: Int = TokenStepSettings.defaults.historyDays,
        force: Bool = false
    ) throws -> CollectionRunOutcome {
        defer { MemoryPressure.relieveAllocatorPressure() }
        let settings = loadSettings()
        let previousSnapshot = try? loadSnapshot()
        let beforeState = UsageCollector.collectionState(
            historyDays: historyDays,
            includeExperimentalAgentSources: settings.showExperimentalAgentSources
        )
        let existingCheckpoint = loadCollectionCheckpoint()
        if CollectionCheckpointPolicy.shouldSkipCollection(
            force: force,
            hasSnapshot: previousSnapshot != nil,
            checkpoint: existingCheckpoint,
            state: beforeState,
            now: Date()
        ) {
            return .unchanged
        }
        let collectedSnapshot = UsageCollector.collect(
            historyDays: historyDays,
            includeExperimentalAgentSources: settings.showExperimentalAgentSources,
            forceFullValidation: force || existingCheckpoint?.isFresh(at: Date()) != true
        )
        try validateRecalibrationCandidate(
            collectedSnapshot,
            previousSnapshot: previousSnapshot
        )
        let snapshot = snapshotWithMigrationMetadata(
            collectedSnapshot,
            previousSnapshot: previousSnapshot
        )
        try persist(snapshot: snapshot)
        let afterState = UsageCollector.collectionState(
            historyDays: historyDays,
            includeExperimentalAgentSources: settings.showExperimentalAgentSources
        )
        let sourceStateWasStable = CollectionCheckpointPolicy.shouldPersist(
            beforeCollection: beforeState,
            afterCollection: afterState
        )
        if sourceStateWasStable {
            saveCollectionCheckpoint(
                CollectionCheckpoint(
                    verifiedAt: Date(),
                    state: afterState
                )
            )
        }
        return sourceStateWasStable ? .updated : .updatedWhileSourcesChanged
    }

    private static func snapshotWithMigrationMetadata(
        _ collectedSnapshot: UsageSnapshot,
        previousSnapshot: UsageSnapshot?
    ) -> UsageSnapshot {
        var snapshot = collectedSnapshot
        if snapshot.sources["Codex"]?.recalibratedFromRevision == nil,
           let previousCodex = previousSnapshot?.sources["Codex"],
           (previousCodex.records ?? 0) > 0,
           let currentRevision = snapshot.sources["Codex"]?.accountingRevision {
            let previousRevision = previousCodex.accountingRevision ?? legacyCodexAccountingRevision
            if previousRevision < currentRevision {
                snapshot.sources["Codex"]?.recalibratedFromRevision = previousRevision
            }
        }
        return snapshot
    }

    private static func validateRecalibrationCandidate(
        _ collectedSnapshot: UsageSnapshot,
        previousSnapshot: UsageSnapshot?
    ) throws {
        guard let previousCodex = previousSnapshot?.sources["Codex"],
              (previousCodex.records ?? 0) > 0
        else {
            return
        }

        let previousRevision = previousCodex.accountingRevision ?? legacyCodexAccountingRevision
        let requiredRevision = UsageCollector.codexAccountingRevision
        guard previousRevision < requiredRevision else { return }
        let currentCodex = collectedSnapshot.sources["Codex"]
        guard currentCodex?.accountingRevision == requiredRevision,
              (currentCodex?.records ?? 0) > 0,
              currentCodex?.status == "ok"
        else {
            throw NSError(
                domain: "TokenStepCollector",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: L("Token 重新校准未完成，已保留原统计。")
                ]
            )
        }
    }

    private static func persist(snapshot: UsageSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(
            at: AppPaths.usageJSON.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: AppPaths.usageJSON, options: .atomic)
        if let previousRevision = snapshot.sources["Codex"]?.recalibratedFromRevision,
           let currentRevision = snapshot.sources["Codex"]?.accountingRevision,
           previousRevision < currentRevision,
           (snapshot.sources["Codex"]?.records ?? 0) > 0 {
            try FileManager.default.createDirectory(
                at: AppPaths.usageRecalibrationNoticeMarker.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try String(currentRevision).write(
                to: AppPaths.usageRecalibrationNoticeMarker,
                atomically: true,
                encoding: .utf8
            )
        }
    }

#if TOKENSTEP_TESTING
    static func persistSnapshotForMigrationTests(
        _ snapshot: UsageSnapshot,
        previousSnapshot: UsageSnapshot?
    ) throws -> UsageSnapshot {
        try validateRecalibrationCandidate(snapshot, previousSnapshot: previousSnapshot)
        let prepared = snapshotWithMigrationMetadata(snapshot, previousSnapshot: previousSnapshot)
        try persist(snapshot: prepared)
        return prepared
    }
#endif

    static var hasPendingUsageRecalibrationNotice: Bool {
        FileManager.default.fileExists(atPath: AppPaths.usageRecalibrationNoticeMarker.path)
    }

    private static func loadCollectionCheckpoint() -> CollectionCheckpoint? {
        guard let data = try? Data(contentsOf: AppPaths.collectionCheckpointJSON) else {
            return nil
        }
        return try? JSONDecoder().decode(CollectionCheckpoint.self, from: data)
    }

    private static func saveCollectionCheckpoint(_ checkpoint: CollectionCheckpoint) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(checkpoint)
            try FileManager.default.createDirectory(
                at: AppPaths.collectionCheckpointJSON.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: AppPaths.collectionCheckpointJSON, options: .atomic)
        } catch {
            // A missing checkpoint only costs another safe collection.
        }
    }

    /// Foundation's atomic writes stage data in `.dat.nosync*` files beside the
    /// target. A crash or forced quit mid-write leaves them behind. Only files a day
    /// old are removed so an in-flight write is never touched.
    static func removeStaleAtomicWriteLeftovers(
        root: URL = AppPaths.appSupportRoot,
        now: Date = Date()
    ) {
        let fileManager = FileManager.default
        for folder in ["data", "config", "cache"] {
            let directory = root.appendingPathComponent(folder, isDirectory: true)
            guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { continue }
            for name in names where name.hasPrefix(".dat.nosync") {
                let url = directory.appendingPathComponent(name)
                guard let modified = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
                      now.timeIntervalSince(modified) > 24 * 60 * 60
                else { continue }
                try? fileManager.removeItem(at: url)
            }
        }
    }

    static func acknowledgeUsageRecalibrationNotice() {
        try? FileManager.default.removeItem(at: AppPaths.usageRecalibrationNoticeMarker)
    }

    static func runCollectorInHelper(
        historyDays: Int = TokenStepSettings.defaults.historyDays,
        force: Bool = false
    ) throws -> CollectionRunOutcome {
        guard let helperURL = bundledHelperURL() else {
            return try runCollector(historyDays: historyDays, force: force)
        }

        let process = Process()
        process.executableURL = helperURL
        process.arguments = ["collect", "\(historyDays)"] + (force ? ["--force"] : [])
        let standardOutput = Pipe()
        process.standardOutput = standardOutput
        let standardError = Pipe()
        process.standardError = standardError

        try process.run()
        let deadline = Date().addingTimeInterval(helperTimeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            let graceDeadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < graceDeadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            throw NSError(
                domain: "TokenStepCollector",
                code: Int(ETIMEDOUT),
                userInfo: [NSLocalizedDescriptionKey: L("Token 采集超时，请稍后重试")]
            )
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = standardError.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "TokenStepCollector",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message?.isEmpty == false ? message! : "Token collector failed."]
            )
        }
        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CollectionRunOutcome(rawValue: output ?? "") ?? .updated
    }

    static func bundledHelperURL() -> URL? {
        let bundleHelper = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/\(helperName)")
        if FileManager.default.isExecutableFile(atPath: bundleHelper.path) {
            return bundleHelper
        }

        if let executableSibling = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Helpers/\(helperName)"),
           FileManager.default.isExecutableFile(atPath: executableSibling.path) {
            return executableSibling
        }

        return nil
    }

    static func normalize(_ settings: TokenStepSettings) -> TokenStepSettings {
        let intervals = Set([0, 60, 300, 900])
        let placement = settings.tokenIslandEnabled ? settings.tokenIslandPlacement : .menuBar
        return TokenStepSettings(
            dailyGoalTokens: max(1_000_000, settings.dailyGoalTokens),
            refreshIntervalSeconds: intervals.contains(settings.refreshIntervalSeconds) ? settings.refreshIntervalSeconds : TokenStepSettings.defaults.refreshIntervalSeconds,
            historyDays: min(365, max(7, settings.historyDays)),
            theme: settings.theme,
            autoUpdateEnabled: settings.autoUpdateEnabled,
            askBeforeDownloadingUpdates: settings.askBeforeDownloadingUpdates,
            requireVerifiedUpdates: settings.requireVerifiedUpdates,
            tokenIslandEnabled: placement != .menuBar,
            tokenIslandPlacement: placement,
            enabledQuotaProviders: settings.enabledQuotaProviders,
            cursorQuotaEnabled: settings.cursorQuotaEnabled,
            cursorCodeSignalEnabled: settings.cursorCodeSignalEnabled,
            agentWorkRankVisibility: settings.agentWorkRankVisibility,
            showExperimentalAgentSources: settings.showExperimentalAgentSources,
            language: settings.language,
            skippedUpdateVersion: settings.skippedUpdateVersion,
            classicTheme: settings.classicTheme,
            odysseyChapter: settings.odysseyChapter
        )
    }
}

enum CollectionRunOutcome: String {
    case updated
    case unchanged
    case updatedWhileSourcesChanged = "updated_source_changed"
}

struct CollectionCheckpoint: Codable, Equatable {
    static let validationTTL: TimeInterval = 24 * 60 * 60

    var verifiedAt: Date
    var state: UsageCollectionState

    func isFresh(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(verifiedAt) < Self.validationTTL
    }
}

enum CollectionCheckpointPolicy {
    static func shouldSkipCollection(
        force: Bool,
        hasSnapshot: Bool,
        checkpoint: CollectionCheckpoint?,
        state: UsageCollectionState,
        now: Date
    ) -> Bool {
        guard !force, hasSnapshot, let checkpoint else { return false }
        return checkpoint.isFresh(at: now) && checkpoint.state == state
    }

    static func shouldPersist(
        beforeCollection: UsageCollectionState,
        afterCollection: UsageCollectionState
    ) -> Bool {
        beforeCollection == afterCollection
    }
}
