import Foundation

struct UsageSnapshot: Codable {
    var generatedAt: String?
    var timezone: String?
    var totals: UsageTotals
    var daily: [DailyUsage]
    var rhythms: [DailyRhythm]
    var agentWork: [DailyAgentWork]
    var tools: [ToolUsage]
    var models: [ModelUsage]
    var sources: [String: SourceInfo]
    /// 生成该快照的采集尝试信息（G-V1）。旧快照缺失时按 nil 解码。
    var sourceAttempt: RefreshAttemptRecord?
    /// 项目维度聚合（G-B1，按末级目录名脱敏）。旧快照缺失时按空数组解码。
    var projects: [ProjectUsage]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case timezone
        case totals
        case daily
        case rhythms
        case agentWork = "agent_work"
        case tools
        case models
        case sources
        case sourceAttempt = "source_attempt"
        case projects
    }

    init(
        generatedAt: String?,
        timezone: String?,
        totals: UsageTotals,
        daily: [DailyUsage],
        rhythms: [DailyRhythm] = [],
        agentWork: [DailyAgentWork] = [],
        tools: [ToolUsage],
        models: [ModelUsage],
        sources: [String: SourceInfo],
        sourceAttempt: RefreshAttemptRecord? = nil,
        projects: [ProjectUsage] = []
    ) {
        self.generatedAt = generatedAt
        self.timezone = timezone
        self.totals = totals
        self.daily = daily
        self.rhythms = rhythms
        self.agentWork = agentWork
        self.tools = tools
        self.models = models
        self.sources = sources
        self.sourceAttempt = sourceAttempt
        self.projects = projects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        totals = try container.decode(UsageTotals.self, forKey: .totals)
        daily = try container.decodeIfPresent([DailyUsage].self, forKey: .daily) ?? []
        rhythms = try container.decodeIfPresent([DailyRhythm].self, forKey: .rhythms) ?? []
        agentWork = try container.decodeIfPresent([DailyAgentWork].self, forKey: .agentWork) ?? []
        tools = try container.decodeIfPresent([ToolUsage].self, forKey: .tools) ?? []
        models = try container.decodeIfPresent([ModelUsage].self, forKey: .models) ?? []
        sources = try container.decodeIfPresent([String: SourceInfo].self, forKey: .sources) ?? [:]
        sourceAttempt = try container.decodeIfPresent(RefreshAttemptRecord.self, forKey: .sourceAttempt)
        projects = try container.decodeIfPresent([ProjectUsage].self, forKey: .projects) ?? []
    }

    func rhythm(for date: String) -> DailyRhythm? {
        rhythms.first { $0.date == date && $0.totalTokens > 0 }
    }

    func agentWork(for date: String) -> DailyAgentWork? {
        agentWork.first { $0.date == date && $0.totalTokens > 0 }
    }

    static let empty = UsageSnapshot(
        generatedAt: nil,
        timezone: "Asia/Shanghai",
        totals: UsageTotals(tokens: 0, cost: 0, activeDays: 0),
        daily: [],
        rhythms: [],
        agentWork: [],
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
    var totalTokens: Int
    var cost: Double
    /// 项目维度（G-B1）。name 为末级目录名；空串表示未命名（UI 层本地化）。旧快照按 nil 解码。
    var projects: [ProjectUsage]?

    enum CodingKeys: String, CodingKey {
        case date
        case tools
        case models
        case totalTokens = "total_tokens"
        case cost
        case projects
    }

    init(date: String, tools: [String: Int], models: [String: Int] = [:], totalTokens: Int, cost: Double, projects: [ProjectUsage]? = nil) {
        self.date = date
        self.tools = tools
        self.models = models
        self.totalTokens = totalTokens
        self.cost = cost
        self.projects = projects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        tools = try container.decodeIfPresent([String: Int].self, forKey: .tools) ?? [:]
        models = try container.decodeIfPresent([String: Int].self, forKey: .models) ?? [:]
        totalTokens = try container.decode(Int.self, forKey: .totalTokens)
        cost = try container.decode(Double.self, forKey: .cost)
        projects = try container.decodeIfPresent([ProjectUsage].self, forKey: .projects)
    }
}

/// 项目维度聚合（G-B1）。name 是末级目录名（脱敏）；空串 = 未命名项目。
struct ProjectUsage: Codable, Equatable, Identifiable {
    var id: String { name }
    var name: String
    var tokens: Int
    var cost: Double
    /// Agent（客户端显示名）→ tokens。
    var tools: [String: Int]
    /// 模型 → tokens。
    var models: [String: Int]
}

struct DailyRhythm: Codable, Identifiable {
    var id: String { date }
    var date: String
    var buckets: [HourlyTokenBucket]
    var totalTokens: Int
    var peakHour: Int?
    var peakTokens: Int
    var activeHours: Int
    var firstActiveHour: Int?
    var lastActiveHour: Int?
    var primaryTag: RhythmTag
    var companionTag: RhythmTag

    enum CodingKeys: String, CodingKey {
        case date
        case buckets
        case totalTokens = "total_tokens"
        case peakHour = "peak_hour"
        case peakTokens = "peak_tokens"
        case activeHours = "active_hours"
        case firstActiveHour = "first_active_hour"
        case lastActiveHour = "last_active_hour"
        case primaryTag = "primary_tag"
        case companionTag = "companion_tag"
    }

    init(
        date: String,
        buckets: [HourlyTokenBucket],
        totalTokens: Int,
        peakHour: Int?,
        peakTokens: Int,
        activeHours: Int,
        firstActiveHour: Int?,
        lastActiveHour: Int?,
        primaryTag: RhythmTag,
        companionTag: RhythmTag
    ) {
        self.date = date
        self.buckets = buckets
        self.totalTokens = totalTokens
        self.peakHour = peakHour
        self.peakTokens = peakTokens
        self.activeHours = activeHours
        self.firstActiveHour = firstActiveHour
        self.lastActiveHour = lastActiveHour
        self.primaryTag = primaryTag
        self.companionTag = companionTag
    }

    var peakHourText: String {
        guard let peakHour else { return "--" }
        return String(format: "%02d:00", peakHour)
    }

    var activeRangeText: String {
        guard let firstActiveHour, let lastActiveHour else { return "--" }
        return String(format: "%02d:00-%02d:00", firstActiveHour, min(lastActiveHour + 1, 24))
    }

    var maxBucketTokens: Int {
        max(1, buckets.map(\.tokens).max() ?? 0)
    }

    var significantTokenThreshold: Int {
        guard totalTokens > 0 else { return 1 }
        let totalBased = Double(totalTokens) * 0.03
        let peakBased = Double(peakTokens) * 0.30
        return max(1, Int(max(totalBased, peakBased).rounded()))
    }

    func isSignificant(_ bucket: HourlyTokenBucket) -> Bool {
        bucket.tokens >= significantTokenThreshold
    }

    func tokens(in hours: ClosedRange<Int>) -> Int {
        buckets
            .filter { hours.contains($0.hour) }
            .map(\.tokens)
            .reduce(0, +)
    }

    func bucket(hour: Int) -> HourlyTokenBucket {
        buckets.first { $0.hour == hour } ?? HourlyTokenBucket(hour: hour, tokens: 0)
    }
}

struct HourlyTokenBucket: Codable, Identifiable {
    var id: Int { hour }
    var hour: Int
    var tokens: Int
}

struct DailyAgentWork: Codable, Identifiable {
    var id: String { date }
    var date: String
    var totalTokens: Int
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var cacheCoverageComplete: Bool
    var activeHours: Int
    var modelRequestCount: Int
    var toolCallCount: Int
    var sources: [AgentWorkSource]
    var hourlyBuckets: [AgentWorkHourBucket]
    var unbucketedTokens: Int

    enum CodingKeys: String, CodingKey {
        case date
        case totalTokens = "total_tokens"
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case cacheCoverageComplete = "cache_coverage_complete"
        case activeHours = "active_hours"
        case modelRequestCount = "model_request_count"
        case toolCallCount = "tool_call_count"
        case sources
        case hourlyBuckets = "hourly_buckets"
        case unbucketedTokens = "unbucketed_tokens"
    }

    init(
        date: String,
        totalTokens: Int,
        activeHours: Int,
        modelRequestCount: Int,
        toolCallCount: Int,
        sources: [AgentWorkSource],
        inputTokens: Int = 0,
        cachedInputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheCoverageComplete: Bool = false,
        hourlyBuckets: [AgentWorkHourBucket] = [],
        unbucketedTokens: Int? = nil
    ) {
        self.date = date
        self.totalTokens = totalTokens
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.cacheCoverageComplete = cacheCoverageComplete
        self.activeHours = activeHours
        self.modelRequestCount = modelRequestCount
        self.toolCallCount = toolCallCount
        self.sources = sources
        self.hourlyBuckets = Self.normalizedHourlyBuckets(hourlyBuckets)
        self.unbucketedTokens = max(
            0,
            unbucketedTokens ?? (totalTokens - self.hourlyBuckets.map(\.totalTokens).reduce(0, +))
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        totalTokens = try container.decode(Int.self, forKey: .totalTokens)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        cachedInputTokens = try container.decodeIfPresent(Int.self, forKey: .cachedInputTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        cacheCoverageComplete = try container.decodeIfPresent(Bool.self, forKey: .cacheCoverageComplete) ?? false
        activeHours = try container.decodeIfPresent(Int.self, forKey: .activeHours) ?? 0
        modelRequestCount = try container.decodeIfPresent(Int.self, forKey: .modelRequestCount) ?? 0
        toolCallCount = try container.decodeIfPresent(Int.self, forKey: .toolCallCount) ?? 0
        sources = try container.decodeIfPresent([AgentWorkSource].self, forKey: .sources) ?? []
        let decodedBuckets = try container.decodeIfPresent([AgentWorkHourBucket].self, forKey: .hourlyBuckets)
        hourlyBuckets = Self.normalizedHourlyBuckets(decodedBuckets ?? [])
        unbucketedTokens = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .unbucketedTokens)
                ?? (totalTokens - hourlyBuckets.map(\.totalTokens).reduce(0, +))
        )
    }

    var cacheHitRate: Double? {
        guard cacheCoverageComplete,
              inputTokens > 0,
              cachedInputTokens >= 0,
              cachedInputTokens <= inputTokens
        else {
            return nil
        }
        return Double(cachedInputTokens) / Double(inputTokens)
    }

    func bucket(hour: Int) -> AgentWorkHourBucket {
        hourlyBuckets.first { $0.hour == hour } ?? AgentWorkHourBucket(hour: hour, sources: [])
    }

    private static var emptyHourlyBuckets: [AgentWorkHourBucket] {
        (0..<24).map { AgentWorkHourBucket(hour: $0, sources: []) }
    }

    private static func normalizedHourlyBuckets(_ buckets: [AgentWorkHourBucket]) -> [AgentWorkHourBucket] {
        let byHour = Dictionary(
            buckets.filter { (0..<24).contains($0.hour) }.map { ($0.hour, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        return (0..<24).map { byHour[$0] ?? AgentWorkHourBucket(hour: $0, sources: []) }
    }
}

struct AgentWorkSource: Codable, Identifiable {
    var id: String { source }
    var source: String
    var tokens: Int
    var modelRequestCount: Int
    var toolCallCount: Int

    enum CodingKeys: String, CodingKey {
        case source
        case tokens
        case modelRequestCount = "model_request_count"
        case toolCallCount = "tool_call_count"
    }
}

struct AgentWorkHourBucket: Codable, Identifiable {
    var id: Int { hour }
    var hour: Int
    var sources: [AgentWorkHourlySource]

    var totalTokens: Int {
        sources.map(\.tokens).reduce(0, +)
    }
}

struct AgentWorkHourlySource: Codable, Identifiable {
    var id: String { source }
    var source: String
    var tokens: Int
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var cacheCoverageComplete: Bool

    enum CodingKeys: String, CodingKey {
        case source
        case tokens
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case cacheCoverageComplete = "cache_coverage_complete"
    }

    var cacheHitRate: Double? {
        guard cacheCoverageComplete,
              inputTokens > 0,
              cachedInputTokens >= 0,
              cachedInputTokens <= inputTokens
        else {
            return nil
        }
        return Double(cachedInputTokens) / Double(inputTokens)
    }
}

enum RhythmTag: String, Codable {
    case earlyStarter = "early_starter"
    case morningPlanner = "morning_planner"
    case afternoonBurst = "afternoon_burst"
    case eveningSprint = "evening_sprint"
    case nightAgent = "night_agent"
    case doublePeak = "double_peak"
    case fragmented = "fragmented"
    case oneShot = "one_shot"
    case steadyCruise = "steady_cruise"
    case quietDay = "quiet_day"

    var title: String {
        switch self {
        case .earlyStarter: return L("清晨启动型")
        case .morningPlanner: return L("上午规划型")
        case .afternoonBurst: return L("下午爆发型")
        case .eveningSprint: return L("晚间冲刺型")
        case .nightAgent: return L("夜间 Agent 型")
        case .doublePeak: return L("双峰推进型")
        case .fragmented: return L("碎片推进型")
        case .oneShot: return L("一波流型")
        case .steadyCruise: return L("稳定巡航型")
        case .quietDay: return L("低频轻触型")
        }
    }

    var shareLine: String {
        switch self {
        case .earlyStarter:
            return L("一早就把 AI 拉进工作台")
        case .morningPlanner:
            return L("上午定方向，后面稳稳推进")
        case .afternoonBurst:
            return L("午后能量拉满，一段时间集中爆发")
        case .eveningSprint:
            return L("晚间突然加速，把任务向前顶了一截")
        case .nightAgent:
            return L("夜里交给 Agent，把任务往前推")
        case .doublePeak:
            return L("一天两次拉满，节奏很有层次")
        case .fragmented:
            return L("多时段穿插推进，随手就把活干了")
        case .oneShot:
            return L("集中一波解决主要战斗")
        case .steadyCruise:
            return L("稳定巡航，没有明显掉线")
        case .quietDay:
            return L("轻量使用，保留一点 AI 手感")
        }
    }

    var companionLine: String {
        switch self {
        case .earlyStarter:
            return L("投缘搭子：夜间 Agent 型")
        case .morningPlanner:
            return L("投缘搭子：下午爆发型")
        case .afternoonBurst:
            return L("投缘搭子：上午规划型")
        case .eveningSprint:
            return L("投缘搭子：稳定巡航型")
        case .nightAgent:
            return L("投缘搭子：清晨启动型")
        case .doublePeak:
            return L("投缘搭子：稳定巡航型")
        case .fragmented:
            return L("投缘搭子：一波流型")
        case .oneShot:
            return L("投缘搭子：碎片推进型")
        case .steadyCruise:
            return L("投缘搭子：双峰推进型")
        case .quietDay:
            return L("投缘搭子：上午规划型")
        }
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
    var exactRecords: Int?
    var legacyRecords: Int?
    var duplicateRecords: Int?
    var counterResets: Int?
    var inheritedRecords: Int?
    var inheritedTokens: Int?
    var unknownBreakdownRecords: Int?
    var accountingRevision: Int?
    var recalibratedFromRevision: Int?
    var tokenBreakdown: SourceTokenBreakdown?

    enum CodingKeys: String, CodingKey {
        case status
        case files
        case records
        case rawRecords = "raw_records"
        case dedupedRecords = "deduped_records"
        case skippedRecords = "skipped_records"
        case strategy
        case exactRecords = "exact_records"
        case legacyRecords = "legacy_records"
        case duplicateRecords = "duplicate_records"
        case counterResets = "counter_resets"
        case inheritedRecords = "inherited_records"
        case inheritedTokens = "inherited_tokens"
        case unknownBreakdownRecords = "unknown_breakdown_records"
        case accountingRevision = "accounting_revision"
        case recalibratedFromRevision = "recalibrated_from_revision"
        case tokenBreakdown = "token_breakdown"
    }
}

struct SourceTokenBreakdown: Codable, Equatable {
    var processedTokens: Int
    var inputTokens: Int
    var cachedInputTokens: Int
    var uncachedInputTokens: Int
    var outputTokens: Int
    var reasoningTokens: Int

    enum CodingKeys: String, CodingKey {
        case processedTokens = "processed_tokens"
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case uncachedInputTokens = "uncached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningTokens = "reasoning_tokens"
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
    var range: String
    var client: String
    var usageMode: String
    var totalTokens: Int
    var totalRankedUsers: Int
    var topLimit: Int
    var entries: [TokenRankEntry]

    var topEntry: TokenRankEntry? {
        entries.first
    }

    func entry(matching userID: Int) -> TokenRankEntry? {
        entries.first { $0.userID == userID }
    }
}

struct TokenRankEntry: Decodable, Equatable, Identifiable {
    var id: Int { userID }
    var rank: Int
    var userID: Int
    var name: String
    var avatarURL: String?
    var totalTokens: Int
    var callCount: Int
    var sessionCount: Int
    var clients: [String: Int]
    var models: [String: Int]

    enum CodingKeys: String, CodingKey {
        case rank
        case user
        case totalTokens = "total_tokens"
        case callCount = "call_count"
        case sessionCount = "session_count"
        case clients
        case models
    }

    init(
        rank: Int,
        userID: Int,
        name: String,
        avatarURL: String?,
        totalTokens: Int,
        callCount: Int,
        sessionCount: Int,
        clients: [String: Int],
        models: [String: Int]
    ) {
        self.rank = rank
        self.userID = userID
        self.name = name
        self.avatarURL = avatarURL
        self.totalTokens = totalTokens
        self.callCount = callCount
        self.sessionCount = sessionCount
        self.clients = clients
        self.models = models
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let user = try container.decode(TokenRankPublicUser.self, forKey: .user)
        rank = try container.decode(Int.self, forKey: .rank)
        userID = user.id
        name = user.name
        avatarURL = user.avatarURL
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        callCount = try container.decodeIfPresent(Int.self, forKey: .callCount) ?? 0
        sessionCount = try container.decodeIfPresent(Int.self, forKey: .sessionCount) ?? 0
        clients = try container.decodeIfPresent([String: Int].self, forKey: .clients) ?? [:]
        models = try container.decodeIfPresent([String: Int].self, forKey: .models) ?? [:]
    }
}

private struct TokenRankPublicUser: Decodable {
    var id: Int
    var name: String
    var avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case avatarURL = "avatar_url"
    }
}

struct TokenRankLeaderboardResponse: Decodable {
    var success: Bool
    var data: TokenRankLeaderboardPayload
}

struct TokenRankLeaderboardPayload: Decodable {
    var range: String
    var client: String
    var usageMode: String
    var totalTokens: Int
    var totalRankedUsers: Int
    var topLimit: Int
    var rows: [TokenRankEntry]

    enum CodingKeys: String, CodingKey {
        case range
        case client
        case usageMode = "usage_mode"
        case totalTokens = "total_tokens"
        case totalRankedUsers = "total_ranked_users"
        case topLimit = "top_limit"
        case rows
    }
}

struct AgentWorkRankIdentity: Equatable, Identifiable {
    var id: Int
    var name: String
    var avatarURL: String?
    var lastSyncedAt: Date?
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

enum AgentWorkRankVisibility: String, Codable, CaseIterable, Identifiable {
    case automatic
    case visible
    case hidden

    var id: String { rawValue }

    var readsLocalIdentity: Bool {
        self != .hidden
    }

    func shouldShow(hasLocalIdentity: Bool) -> Bool {
        switch self {
        case .automatic:
            return hasLocalIdentity
        case .visible:
            return true
        case .hidden:
            return false
        }
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
    var agentWorkRankVisibility: AgentWorkRankVisibility
    var showExperimentalAgentSources: Bool
    /// G-A1：逐源启用的实验 Agent 源（显示名）。nil = 主开关即旧三源语义；
    /// 显式列表决定 T1 新源是否参与采集，新源永不因 legacy 布尔迁移被开启。
    var experimentalAgentSources: [String]?
    /// G-S1：多设备同步（默认关闭；服务端契约冻结前不提供启用入口）。
    var deviceSyncEnabled: Bool = false
    var mergeTodayAllDevices: Bool = false
    var mergeHistoryAllDevices: Bool = false
    var hiddenDeviceIDs: [String] = []
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
        case agentWorkRankVisibility = "agent_work_rank_visibility"
        case legacyShowAgentWorkRank = "show_agent_work_rank"
        case showExperimentalAgentSources = "show_experimental_agent_sources"
        case experimentalAgentSources = "experimental_agent_sources"
        case deviceSyncEnabled = "device_sync_enabled"
        case mergeTodayAllDevices = "merge_today_all_devices"
        case mergeHistoryAllDevices = "merge_history_all_devices"
        case hiddenDeviceIDs = "hidden_device_ids"
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
        agentWorkRankVisibility: .hidden,
        showExperimentalAgentSources: false,
        experimentalAgentSources: nil,
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
        agentWorkRankVisibility: AgentWorkRankVisibility,
        showExperimentalAgentSources: Bool,
        experimentalAgentSources: [String]? = nil,
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
        self.agentWorkRankVisibility = agentWorkRankVisibility
        self.showExperimentalAgentSources = showExperimentalAgentSources
        self.experimentalAgentSources = experimentalAgentSources
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
        showCodexQuota = try container.decodeIfPresent(Bool.self, forKey: .showCodexQuota) ?? defaults.showCodexQuota
        if let visibility = try container.decodeIfPresent(AgentWorkRankVisibility.self, forKey: .agentWorkRankVisibility) {
            agentWorkRankVisibility = visibility
        } else if let legacyVisible = try container.decodeIfPresent(Bool.self, forKey: .legacyShowAgentWorkRank) {
            // Opt-in contract (docs/PRIVACY.md): legacy absence/false must never
            // silently enable local identity reads or leaderboard requests.
            agentWorkRankVisibility = legacyVisible ? .visible : .hidden
        } else {
            agentWorkRankVisibility = defaults.agentWorkRankVisibility
        }
        showExperimentalAgentSources = try container.decodeIfPresent(Bool.self, forKey: .showExperimentalAgentSources) ?? defaults.showExperimentalAgentSources
        experimentalAgentSources = try container.decodeIfPresent([String].self, forKey: .experimentalAgentSources) ?? defaults.experimentalAgentSources
        deviceSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .deviceSyncEnabled) ?? false
        mergeTodayAllDevices = try container.decodeIfPresent(Bool.self, forKey: .mergeTodayAllDevices) ?? false
        mergeHistoryAllDevices = try container.decodeIfPresent(Bool.self, forKey: .mergeHistoryAllDevices) ?? false
        hiddenDeviceIDs = try container.decodeIfPresent([String].self, forKey: .hiddenDeviceIDs) ?? []
        language = try container.decodeIfPresent(TokenStepLanguage.self, forKey: .language) ?? defaults.language
        skippedUpdateVersion = try container.decodeIfPresent(String.self, forKey: .skippedUpdateVersion)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dailyGoalTokens, forKey: .dailyGoalTokens)
        try container.encode(refreshIntervalSeconds, forKey: .refreshIntervalSeconds)
        try container.encode(historyDays, forKey: .historyDays)
        try container.encode(theme, forKey: .theme)
        try container.encode(autoUpdateEnabled, forKey: .autoUpdateEnabled)
        try container.encode(askBeforeDownloadingUpdates, forKey: .askBeforeDownloadingUpdates)
        try container.encode(requireVerifiedUpdates, forKey: .requireVerifiedUpdates)
        try container.encode(tokenIslandEnabled, forKey: .tokenIslandEnabled)
        try container.encode(tokenIslandPlacement, forKey: .tokenIslandPlacement)
        try container.encode(showCodexQuota, forKey: .showCodexQuota)
        try container.encode(agentWorkRankVisibility, forKey: .agentWorkRankVisibility)
        try container.encode(showExperimentalAgentSources, forKey: .showExperimentalAgentSources)
        try container.encodeIfPresent(experimentalAgentSources, forKey: .experimentalAgentSources)
        try container.encode(deviceSyncEnabled, forKey: .deviceSyncEnabled)
        try container.encode(mergeTodayAllDevices, forKey: .mergeTodayAllDevices)
        try container.encode(mergeHistoryAllDevices, forKey: .mergeHistoryAllDevices)
        try container.encode(hiddenDeviceIDs, forKey: .hiddenDeviceIDs)
        try container.encode(language, forKey: .language)
        try container.encodeIfPresent(skippedUpdateVersion, forKey: .skippedUpdateVersion)
    }
}
