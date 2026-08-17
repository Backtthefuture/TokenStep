import Foundation

enum AppPaths {
    static let appSupportRoot: URL = {
#if TOKENSTEP_TESTING
        if let override = ProcessInfo.processInfo.environment["TOKENSTEP_TEST_APP_SUPPORT_ROOT"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
#endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("TokenStep", isDirectory: true)
    }()

    static let usageJSON = appSupportRoot.appendingPathComponent("data/usage.json")
    static let collectorCacheJSON = appSupportRoot.appendingPathComponent("cache/collector-cache.json")
    static let collectionCheckpointJSON = appSupportRoot.appendingPathComponent("cache/collection-checkpoint.json")
    static let codexIncrementalCacheSQLite = appSupportRoot.appendingPathComponent("cache/codex-incremental.sqlite3")
    static let claudeQuotaCacheJSON = appSupportRoot.appendingPathComponent("cache/claude-quota-cache.json")
    static let cursorQuotaCacheJSON = appSupportRoot.appendingPathComponent("cache/cursor-quota-cache.json")
    static let cursorUsageCacheJSON = appSupportRoot.appendingPathComponent("cache/cursor-usage-cache.json")
    static let glmQuotaCacheJSON = appSupportRoot.appendingPathComponent("cache/glm-quota-cache.json")
    static let kimiQuotaCacheJSON = appSupportRoot.appendingPathComponent("cache/kimi-quota-cache.json")
    static let grokQuotaCacheJSON = appSupportRoot.appendingPathComponent("cache/grok-quota-cache.json")
    static let settingsJSON = appSupportRoot.appendingPathComponent("config/settings.json")
    static let autostartDefaultMarker = appSupportRoot.appendingPathComponent("config/autostart-default-applied")
    static let usageRecalibrationNoticeMarker = appSupportRoot.appendingPathComponent("config/usage-recalibration-v6-pending")
    static let updates = appSupportRoot.appendingPathComponent("updates", isDirectory: true)
    static let logs = appSupportRoot.appendingPathComponent("logs", isDirectory: true)
}
