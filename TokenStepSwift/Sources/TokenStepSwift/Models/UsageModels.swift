import Foundation

struct UsageSnapshot: Codable {
    var generatedAt: String?
    var timezone: String?
    var totals: UsageTotals
    var daily: [DailyUsage]
    var tools: [ToolUsage]
    var models: [ModelUsage]
    var sources: [String: SourceInfo]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case timezone
        case totals
        case daily
        case tools
        case models
        case sources
    }

    static let empty = UsageSnapshot(
        generatedAt: nil,
        timezone: "Asia/Shanghai",
        totals: UsageTotals(tokens: 0, cost: 0, activeDays: 0),
        daily: [],
        tools: [],
        models: [],
        sources: [:]
    )
}

struct UsageTotals: Codable {
    var tokens: Int
    var cost: Double
    var activeDays: Int

    enum CodingKeys: String, CodingKey {
        case tokens
        case cost
        case activeDays = "active_days"
    }
}

struct DailyUsage: Codable, Identifiable {
    var id: String { date }
    var date: String
    var tools: [String: Int]
    var totalTokens: Int
    var cost: Double

    enum CodingKeys: String, CodingKey {
        case date
        case tools
        case totalTokens = "total_tokens"
        case cost
    }
}

struct ToolUsage: Codable, Identifiable {
    var id: String { tool }
    var tool: String
    var tokens: Int
    var percent: Double?

    var percentValue: Double { percent ?? 0 }
}

struct ModelUsage: Codable, Identifiable {
    var id: String { "\(model)-\(tool ?? "")" }
    var model: String
    var tool: String?
    var tokens: Int
    var percent: Double?

    var percentValue: Double { percent ?? 0 }
}

struct SourceInfo: Codable {
    var status: String?
    var files: Int?
    var records: Int?
}

struct CodexQuotaSnapshot: Equatable {
    var fetchedAt: Date?
    var fiveHour: CodexQuotaWindow?
    var sevenDay: CodexQuotaWindow?

    var isAvailable: Bool {
        fiveHour != nil || sevenDay != nil
    }

    static let unavailable = CodexQuotaSnapshot(fetchedAt: nil, fiveHour: nil, sevenDay: nil)
}

struct CodexQuotaWindow: Equatable, Identifiable {
    enum Kind: Equatable {
        case fiveHour
        case sevenDay
    }

    var kind: Kind
    var usedPercent: Double
    var resetsAt: Date?

    var id: String {
        switch kind {
        case .fiveHour: return "5h"
        case .sevenDay: return "7d"
        }
    }

    var title: String {
        switch kind {
        case .fiveHour: return L("5 小时")
        case .sevenDay: return L("7 天")
        }
    }

    var remainingPercent: Double {
        min(max(100 - usedPercent, 0), 100)
    }
}

enum TokenIslandDisplayPlacement: String, CaseIterable, Identifiable, Codable {
    case automatic = "auto"
    case notchLeft = "notch_left"
    case notchRight = "notch_right"
    case menuBar = "menu_bar"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return L("自动")
        case .notchLeft: return L("刘海左侧")
        case .notchRight: return L("刘海右侧")
        case .menuBar: return L("菜单栏")
        }
    }

    var shortTitle: String {
        switch self {
        case .automatic: return L("自动")
        case .notchLeft: return L("左侧")
        case .notchRight: return L("右侧")
        case .menuBar: return L("菜单栏")
        }
    }
}

enum TokenStepLanguage: String, CaseIterable, Identifiable, Codable {
    case system
    case zhHans = "zh-Hans"
    case en
    case zhHant = "zh-Hant"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return L("跟随系统")
        case .zhHans: return "简体中文"
        case .en: return "English"
        case .zhHant: return "繁體中文"
        }
    }

    var subtitle: String {
        switch self {
        case .system: return L("自动匹配 macOS")
        case .zhHans: return "简体"
        case .en: return "English"
        case .zhHant: return "繁體"
        }
    }

    var localeIdentifier: String {
        switch resolved {
        case .system:
            return "zh-Hans"
        case .zhHans:
            return "zh-Hans"
        case .en:
            return "en"
        case .zhHant:
            return "zh-Hant"
        }
    }

    var resolved: TokenStepLanguage {
        guard self == .system else { return self }
        for identifier in Locale.preferredLanguages {
            let lowercased = identifier.lowercased()
            if lowercased.hasPrefix("zh-hant") || lowercased.hasPrefix("zh-tw") || lowercased.hasPrefix("zh-hk") {
                return .zhHant
            }
            if lowercased.hasPrefix("en") {
                return .en
            }
            if lowercased.hasPrefix("zh") {
                return .zhHans
            }
        }
        return .zhHans
    }
}

struct TokenStepSettings: Codable {
    var dailyGoalTokens: Int
    var refreshIntervalSeconds: Int
    var historyDays: Int
    var theme: TokenStepTheme
    var autoUpdateEnabled: Bool
    var askBeforeDownloadingUpdates: Bool
    var requireVerifiedUpdates: Bool
    var tokenIslandEnabled: Bool
    var tokenIslandPlacement: TokenIslandDisplayPlacement
    var language: TokenStepLanguage
    var skippedUpdateVersion: String?

    enum CodingKeys: String, CodingKey {
        case dailyGoalTokens = "daily_goal_tokens"
        case refreshIntervalSeconds = "refresh_interval_seconds"
        case historyDays = "history_days"
        case theme
        case autoUpdateEnabled = "auto_update_enabled"
        case askBeforeDownloadingUpdates = "ask_before_downloading_updates"
        case requireVerifiedUpdates = "require_verified_updates"
        case tokenIslandEnabled = "token_island_enabled"
        case tokenIslandPlacement = "token_island_placement"
        case language
        case skippedUpdateVersion = "skipped_update_version"
    }

    static let defaults = TokenStepSettings(
        dailyGoalTokens: 100_000_000,
        refreshIntervalSeconds: 60,
        historyDays: 180,
        theme: .green,
        autoUpdateEnabled: true,
        askBeforeDownloadingUpdates: true,
        requireVerifiedUpdates: true,
        tokenIslandEnabled: true,
        tokenIslandPlacement: .automatic,
        language: .system,
        skippedUpdateVersion: nil
    )

    init(
        dailyGoalTokens: Int,
        refreshIntervalSeconds: Int,
        historyDays: Int,
        theme: TokenStepTheme,
        autoUpdateEnabled: Bool,
        askBeforeDownloadingUpdates: Bool,
        requireVerifiedUpdates: Bool,
        tokenIslandEnabled: Bool,
        tokenIslandPlacement: TokenIslandDisplayPlacement,
        language: TokenStepLanguage,
        skippedUpdateVersion: String?
    ) {
        self.dailyGoalTokens = dailyGoalTokens
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.historyDays = historyDays
        self.theme = theme
        self.autoUpdateEnabled = autoUpdateEnabled
        self.askBeforeDownloadingUpdates = askBeforeDownloadingUpdates
        self.requireVerifiedUpdates = requireVerifiedUpdates
        self.tokenIslandEnabled = tokenIslandEnabled
        self.tokenIslandPlacement = tokenIslandPlacement
        self.language = language
        self.skippedUpdateVersion = skippedUpdateVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = TokenStepSettings.defaults
        dailyGoalTokens = try container.decodeIfPresent(Int.self, forKey: .dailyGoalTokens) ?? defaults.dailyGoalTokens
        refreshIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .refreshIntervalSeconds) ?? defaults.refreshIntervalSeconds
        historyDays = try container.decodeIfPresent(Int.self, forKey: .historyDays) ?? defaults.historyDays
        let themeID = try container.decodeIfPresent(String.self, forKey: .theme)
        theme = themeID.flatMap(TokenStepTheme.init(rawValue:)) ?? defaults.theme
        autoUpdateEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoUpdateEnabled) ?? defaults.autoUpdateEnabled
        askBeforeDownloadingUpdates = try container.decodeIfPresent(Bool.self, forKey: .askBeforeDownloadingUpdates) ?? defaults.askBeforeDownloadingUpdates
        requireVerifiedUpdates = try container.decodeIfPresent(Bool.self, forKey: .requireVerifiedUpdates) ?? defaults.requireVerifiedUpdates
        let legacyTokenIslandEnabled = try container.decodeIfPresent(Bool.self, forKey: .tokenIslandEnabled)
        tokenIslandEnabled = legacyTokenIslandEnabled ?? defaults.tokenIslandEnabled
        if let placement = try container.decodeIfPresent(TokenIslandDisplayPlacement.self, forKey: .tokenIslandPlacement) {
            tokenIslandPlacement = placement
        } else if legacyTokenIslandEnabled == false {
            tokenIslandPlacement = .menuBar
        } else {
            tokenIslandPlacement = defaults.tokenIslandPlacement
        }
        language = try container.decodeIfPresent(TokenStepLanguage.self, forKey: .language) ?? defaults.language
        skippedUpdateVersion = try container.decodeIfPresent(String.self, forKey: .skippedUpdateVersion)
    }
}
