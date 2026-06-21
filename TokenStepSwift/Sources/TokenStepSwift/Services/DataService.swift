import Darwin
import Foundation

enum DataService {
    private static let helperName = "TokenStepHelper"
    private static let helperTimeoutSeconds: TimeInterval = 120

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
        let snapshot = UsageCollector.collect(historyDays: historyDays)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(
            at: AppPaths.usageJSON.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: AppPaths.usageJSON, options: .atomic)
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
            tokenRankUserID: TokenStepSettings.cleanedTokenRankUserID(settings.tokenRankUserID),
            language: settings.language,
            skippedUpdateVersion: settings.skippedUpdateVersion
        )
    }
}
