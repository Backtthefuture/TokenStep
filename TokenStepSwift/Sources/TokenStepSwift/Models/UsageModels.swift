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
    var models: [String: Int]
    var toolModels: [String: [String: Int]]?
    var totalTokens: Int
    var cost: Double

    enum CodingKeys: String, CodingKey {
        case date
        case tools
        case models
        case toolModels = "tool_models"
        case totalTokens = "total_tokens"
        case cost
    }

    init(date: String, tools: [String: Int], models: [String: Int] = [:], toolModels: [String: [String: Int]]? = nil, totalTokens: Int, cost: Double) {
        self.date = date
        self.tools = tools
        self.models = models
        self.toolModels = toolModels
        self.totalTokens = totalTokens
        self.cost = cost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        tools = try container.decodeIfPresent([String: Int].self, forKey: .tools) ?? [:]
        models = try container.decodeIfPresent([String: Int].self, forKey: .models) ?? [:]
        toolModels = try container.decodeIfPresent([String: [String: Int]].self, forKey: .toolModels)
        totalTokens = try container.decode(Int.self, forKey: .totalTokens)
        cost = try container.decode(Double.self, forKey: .cost)
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
    var rawRecords: Int?
    var dedupedRecords: Int?
    var skippedRecords: Int?
    var strategy: String?

    enum CodingKeys: String, CodingKey {
        case status
        case files
        case records
        case rawRecords = "raw_records"
        case dedupedRecords = "deduped_records"
        case skippedRecords = "skipped_records"
        case strategy
    }
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

struct CodexQuotaWindow: Equatable, Identifiable, Codable {
    enum Kind: String, Equatable, Codable {
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

struct TokenRankLeaderboard: Equatable {
    var fetchedAt: Date
    var board: String
    var range: String
    var entries: [TokenRankEntry]

    var topEntry: TokenRankEntry? {
        entries.first
    }

    func entry(matching userID: String) -> TokenRankEntry? {
        let normalizedID = TokenStepSettings.cleanedTokenRankUserID(userID)
        guard !normalizedID.isEmpty else { return nil }
        return entries.first { $0.userID == normalizedID }
    }
}

struct TokenRankEntry: Decodable, Equatable, Identifiable {
    var id: String { userID }
    var rank: Int
    var userID: String
    var name: String
    var avatar: String?
    var score: Int
    var cost: Double
    var byTool: [String: Int]

    enum CodingKeys: String, CodingKey {
        case rank
        case userID = "userId"
        case name
        case avatar
        case score
        case cost
        case byTool
    }

    init(
        rank: Int,
        userID: String,
        name: String,
        avatar: String?,
        score: Int,
        cost: Double,
        byTool: [String: Int]
    ) {
        self.rank = rank
        self.userID = userID
        self.name = name
        self.avatar = avatar
        self.score = score
        self.cost = cost
        self.byTool = byTool
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rank = try container.decode(Int.self, forKey: .rank)
        userID = try Self.decodeFlexibleString(from: container, forKey: .userID)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? L("匿名用户")
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        score = try container.decode(Int.self, forKey: .score)
        cost = try container.decodeIfPresent(Double.self, forKey: .cost) ?? 0
        byTool = try container.decodeIfPresent([String: Int].self, forKey: .byTool) ?? [:]
    }

    private static func decodeFlexibleString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> String {
        if let value = try? container.decode(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? container.decode(Int64.self, forKey: key) {
            return String(value)
        }
        return ""
    }
}

struct TokenRankLeaderboardResponse: Decodable {
    var status: Int?
    var board: String
    var range: String
    var entries: [TokenRankEntry]
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
    var showCodexQuota: Bool
    var showTokenRank: Bool
    var tokenRankUserID: String
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
        case showCodexQuota = "show_codex_quota"
        case showTokenRank = "show_token_rank"
        case tokenRankUserID = "token_rank_user_id"
        case language
        case skippedUpdateVersion = "skipped_update_version"
    }

    static let defaults = TokenStepSettings(
        dailyGoalTokens: 100_000_000,
        refreshIntervalSeconds: 300,
        historyDays: 180,
        theme: .green,
        autoUpdateEnabled: true,
        askBeforeDownloadingUpdates: true,
        requireVerifiedUpdates: true,
        tokenIslandEnabled: false,
        tokenIslandPlacement: .menuBar,
        showCodexQuota: false,
        showTokenRank: false,
        tokenRankUserID: "",
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
        showCodexQuota: Bool,
        showTokenRank: Bool,
        tokenRankUserID: String,
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
        self.showCodexQuota = showCodexQuota
        self.showTokenRank = showTokenRank
        self.tokenRankUserID = Self.cleanedTokenRankUserID(tokenRankUserID)
        self.language = language
        self.skippedUpdateVersion = skippedUpdateVersion
    }

    static func cleanedTokenRankUserID(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter(\.isNumber)
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
        showCodexQuota = try container.decodeIfPresent(Bool.self, forKey: .showCodexQuota) ?? defaults.showCodexQuota
        showTokenRank = try container.decodeIfPresent(Bool.self, forKey: .showTokenRank) ?? defaults.showTokenRank
        let decodedTokenRankUserID = try container.decodeIfPresent(String.self, forKey: .tokenRankUserID) ?? defaults.tokenRankUserID
        tokenRankUserID = Self.cleanedTokenRankUserID(decodedTokenRankUserID)
        language = try container.decodeIfPresent(TokenStepLanguage.self, forKey: .language) ?? defaults.language
        skippedUpdateVersion = try container.decodeIfPresent(String.self, forKey: .skippedUpdateVersion)
    }
}
