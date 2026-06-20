import Foundation

enum AppPaths {
    static let appSupportRoot: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("TokenStep", isDirectory: true)
    }()

    static let usageJSON = appSupportRoot.appendingPathComponent("data/usage.json")
    static let collectorCacheJSON = appSupportRoot.appendingPathComponent("cache/collector-cache.json")
    static let claudeQuotaCacheJSON = appSupportRoot.appendingPathComponent("cache/claude-quota-cache.json")
    static let settingsJSON = appSupportRoot.appendingPathComponent("config/settings.json")
    static let autostartDefaultMarker = appSupportRoot.appendingPathComponent("config/autostart-default-applied")
    static let updates = appSupportRoot.appendingPathComponent("updates", isDirectory: true)
    static let logs = appSupportRoot.appendingPathComponent("logs", isDirectory: true)
}
