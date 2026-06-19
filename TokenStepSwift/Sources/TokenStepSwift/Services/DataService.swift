import Foundation

enum DataService {
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

    static func runCollector() throws {
        let snapshot = UsageCollector.collect()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(
            at: AppPaths.usageJSON.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: AppPaths.usageJSON, options: .atomic)
    }

    static func normalize(_ settings: TokenStepSettings) -> TokenStepSettings {
        let intervals = Set([0, 60, 300, 900])
        return TokenStepSettings(
            dailyGoalTokens: max(1_000_000, settings.dailyGoalTokens),
            refreshIntervalSeconds: intervals.contains(settings.refreshIntervalSeconds) ? settings.refreshIntervalSeconds : 60,
            historyDays: min(365, max(7, settings.historyDays))
        )
    }
}
