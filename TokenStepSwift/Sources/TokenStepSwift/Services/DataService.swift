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

    static func runCollector(historyDays: Int = TokenStepSettings.defaults.historyDays) throws {
        defer { MemoryPressure.relieveAllocatorPressure() }
        let settings = loadSettings()
        let previousSnapshot = try? loadSnapshot()
        let collectedSnapshot = UsageCollector.collect(
            historyDays: historyDays,
            includeExperimentalAgentSources: settings.showExperimentalAgentSources
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

    static func acknowledgeUsageRecalibrationNotice() {
        try? FileManager.default.removeItem(at: AppPaths.usageRecalibrationNoticeMarker)
    }

    static func runCollectorInHelper(historyDays: Int = TokenStepSettings.defaults.historyDays) throws {
        guard let helperURL = bundledHelperURL() else {
            try runCollector(historyDays: historyDays)
            return
        }

        let process = Process()
        process.executableURL = helperURL
        process.arguments = ["collect", "\(historyDays)"]
        process.standardOutput = Pipe()
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
            showCodexQuota: settings.showCodexQuota,
            showTokenRank: settings.showTokenRank,
            showExperimentalAgentSources: settings.showExperimentalAgentSources,
            tokenRankUserID: TokenStepSettings.cleanedTokenRankUserID(settings.tokenRankUserID),
            language: settings.language,
            skippedUpdateVersion: settings.skippedUpdateVersion
        )
    }
}
