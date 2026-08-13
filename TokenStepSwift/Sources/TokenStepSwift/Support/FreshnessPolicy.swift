import Foundation

// G-V1 / V1-T01：统一新鲜度与失败状态模型（PRD_TOKENSTEP_OPTIMIZATION.md §5.3）。
//
// 设计约束：
// - 区分 lastAttemptedAt 与 lastSucceededAt；
// - 阈值全部集中在本 policy，UI 不得散落魔法数字；
// - 只持久化时间与安全分类，不保存敏感路径或原始错误正文；
// - Codex 与 Claude 额度的成功/失败分别记录，互不掩盖。

/// 用户可见的安全错误分类。持久化与展示只允许出现该分类，不携带原始错误正文。
enum UsageErrorKind: String, Codable, CaseIterable {
    case collectionFailed
    case networkFailed
    case unauthorized
    case timeout
    case parseFailed
    case unknown

    var localizedSummary: String {
        switch self {
        case .collectionFailed: return L("本地采集失败")
        case .networkFailed: return L("网络请求失败")
        case .unauthorized: return L("凭据未授权")
        case .timeout: return L("请求超时")
        case .parseFailed: return L("数据解析失败")
        case .unknown: return L("未知错误")
        }
    }
}

/// 单一刷新通道（本地采集 / Codex 额度 / Claude 额度）的尝试记录。
struct RefreshAttemptRecord: Codable, Equatable {
    var lastAttemptedAt: Date?
    var lastSucceededAt: Date?
    var lastFailedAt: Date?
    var lastErrorKind: UsageErrorKind?

    init(
        lastAttemptedAt: Date? = nil,
        lastSucceededAt: Date? = nil,
        lastFailedAt: Date? = nil,
        lastErrorKind: UsageErrorKind? = nil
    ) {
        self.lastAttemptedAt = lastAttemptedAt
        self.lastSucceededAt = lastSucceededAt
        self.lastFailedAt = lastFailedAt
        self.lastErrorKind = lastErrorKind
    }

    /// 最近一次尝试是否明确失败。
    var lastAttemptFailed: Bool { lastFailedAt != nil && lastFailedAt == latestAttempt }

    private var latestAttempt: Date? {
        [lastAttemptedAt, lastFailedAt].compactMap { $0 }.max()
    }

    /// 记录一次尝试的开始。
    func attempting(at date: Date) -> RefreshAttemptRecord {
        var record = self
        record.lastAttemptedAt = date
        return record
    }

    /// 记录一次成功。
    func succeeding(at date: Date) -> RefreshAttemptRecord {
        var record = self
        record.lastSucceededAt = date
        record.lastFailedAt = nil
        record.lastErrorKind = nil
        return record
    }

    /// 记录一次失败（保留旧成功时间，UI 依此展示"失败 + 最后成功时间"）。
    func failing(kind: UsageErrorKind, at date: Date) -> RefreshAttemptRecord {
        var record = self
        record.lastAttemptedAt = date
        record.lastFailedAt = date
        record.lastErrorKind = kind
        return record
    }
}

/// 统一新鲜度状态（六态）。
enum UsageFreshnessKind: String, Codable, CaseIterable {
    case neverSucceeded
    case fresh
    case aging
    case stale
    case partial
    case disabled
}

/// 面向 UI 的完整新鲜度描述。
struct UsageFreshness: Equatable {
    var kind: UsageFreshnessKind
    var lastSucceededAt: Date?
    var lastAttemptedAt: Date?
    var errorKind: UsageErrorKind?
    /// partial 状态下的来源清单（仅显示名，不含路径）。
    var successfulSources: [String]?
    var failedSources: [String]?

    init(
        kind: UsageFreshnessKind,
        lastSucceededAt: Date? = nil,
        lastAttemptedAt: Date? = nil,
        errorKind: UsageErrorKind? = nil,
        successfulSources: [String]? = nil,
        failedSources: [String]? = nil
    ) {
        self.kind = kind
        self.lastSucceededAt = lastSucceededAt
        self.lastAttemptedAt = lastAttemptedAt
        self.errorKind = errorKind
        self.successfulSources = successfulSources
        self.failedSources = failedSources
    }
}

/// 持久化的三通道尝试记录（cache/freshness-state.json）。
struct FreshnessState: Codable, Equatable {
    var collection: RefreshAttemptRecord = RefreshAttemptRecord()
    var codexQuota: RefreshAttemptRecord = RefreshAttemptRecord()
    var claudeQuota: RefreshAttemptRecord = RefreshAttemptRecord()
    var stateVersion: Int = 1

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        collection = try container.decodeIfPresent(RefreshAttemptRecord.self, forKey: .collection)
            ?? RefreshAttemptRecord()
        codexQuota = try container.decodeIfPresent(RefreshAttemptRecord.self, forKey: .codexQuota)
            ?? RefreshAttemptRecord()
        claudeQuota = try container.decodeIfPresent(RefreshAttemptRecord.self, forKey: .claudeQuota)
            ?? RefreshAttemptRecord()
        stateVersion = try container.decodeIfPresent(Int.self, forKey: .stateVersion) ?? 1
    }
}

enum FreshnessPolicy {
    /// 超过正常 TTL 该倍数后视为过期，无论最近尝试是否失败。
    static let staleTTLMultiple: Double = 2

    /// 本地采集的正常 TTL：用户设置刷新间隔，受自动重试下限约束。
    static func collectionNormalTTL(refreshIntervalSeconds: Int) -> TimeInterval {
        EnergyRefreshPolicy.automaticRetryTTL(requestedSeconds: refreshIntervalSeconds)
    }

    /// 额度的正常 TTL：沿用现有 quota TTL。
    static var quotaNormalTTL: TimeInterval {
        EnergyRefreshPolicy.quotaTTL
    }

    static func staleTTL(normalTTL: TimeInterval) -> TimeInterval {
        normalTTL * staleTTLMultiple
    }

    /// 六态分类。参数为通道视角的聚合输入：
    /// - enabled：功能是否开启（额度可关；采集始终为 true）；
    /// - record：本通道尝试记录；
    /// - sourceStatuses：本通道内各已启用来源的状态（仅采集通道提供，键为显示名）。
    static func classify(
        enabled: Bool,
        record: RefreshAttemptRecord,
        normalTTL: TimeInterval,
        now: Date,
        sourceStatuses: [String: String]? = nil
    ) -> UsageFreshness {
        guard enabled else {
            return UsageFreshness(kind: .disabled)
        }
        guard record.lastSucceededAt != nil else {
            // 从未成功（无论是否已尝试过）：UI 显示"暂无数据"，不显示 0。
            return UsageFreshness(
                kind: .neverSucceeded,
                lastAttemptedAt: record.lastAttemptedAt,
                errorKind: record.lastErrorKind
            )
        }

        let succeededAt = record.lastSucceededAt
        let age = now.timeIntervalSince(succeededAt ?? now)
        let staleAfter = staleTTL(normalTTL: normalTTL)

        // 最近一次尝试明确失败且仍展示旧值 → stale（优先于 partial/aging）。
        if record.lastAttemptFailed {
            return UsageFreshness(
                kind: .stale,
                lastSucceededAt: succeededAt,
                lastAttemptedAt: record.lastAttemptedAt,
                errorKind: record.lastErrorKind
            )
        }
        // 数据年龄超过正常 TTL 的 staleTTLMultiple 倍 → stale。
        if age > staleAfter {
            return UsageFreshness(
                kind: .stale,
                lastSucceededAt: succeededAt,
                lastAttemptedAt: record.lastAttemptedAt
            )
        }
        // 同一刷新周期内部分来源失败（仅采集通道有意义）。
        if let sourceStatuses, !sourceStatuses.isEmpty {
            let successful = sourceStatuses.filter { isSuccessfulSourceStatus($0.value) }.keys.sorted()
            let failed = sourceStatuses.filter { isFailedSourceStatus($0.value) }.keys.sorted()
            if !successful.isEmpty && !failed.isEmpty {
                return UsageFreshness(
                    kind: .partial,
                    lastSucceededAt: succeededAt,
                    lastAttemptedAt: record.lastAttemptedAt,
                    successfulSources: successful,
                    failedSources: failed
                )
            }
        }
        // 超过正常 TTL 但最近尝试没有明确失败 → aging。
        if age > normalTTL {
            return UsageFreshness(
                kind: .aging,
                lastSucceededAt: succeededAt,
                lastAttemptedAt: record.lastAttemptedAt
            )
        }
        return UsageFreshness(
            kind: .fresh,
            lastSucceededAt: succeededAt,
            lastAttemptedAt: record.lastAttemptedAt
        )
    }

    /// source diagnostics 中视为成功的状态（ok / ok_sqlite）。
    static func isSuccessfulSourceStatus(_ status: String) -> Bool {
        status == "ok" || status == "ok_sqlite"
    }

    /// 视为"缺席"的状态：功能关闭或该来源当日无数据（missing 各形态）。
    /// 缺席不等于失败：CC Switch 今天没有代理行不应天天报"部分来源失败"。
    static func isAbsentSourceStatus(_ status: String) -> Bool {
        status == "disabled" || status == "missing" || status == "missing_db"
            || status == "missing_valid_rows"
    }

    /// 视为"已启用但失败"的状态（如 incremental_cache_error / 解析失败）。
    static func isFailedSourceStatus(_ status: String) -> Bool {
        !isSuccessfulSourceStatus(status) && !isAbsentSourceStatus(status)
    }

    /// 把底层错误映射为安全分类（不保留正文）。
    static func classify(error: Error) -> UsageErrorKind {
        if let urlError = error as? URLError {
            // NSError(NSURLErrorDomain, 401/403) 会桥接成 URLError 且落入 default；
            // 鉴权类错误优先于网络分类。
            if urlError.code.rawValue == 401 || urlError.code.rawValue == 403 {
                return .unauthorized
            }
            switch urlError.code {
            case .timedOut:
                return .timeout
            case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
                 .dnsLookupFailed, .networkConnectionLost, .secureConnectionFailed:
                return .networkFailed
            case .userAuthenticationRequired, .userCancelledAuthentication:
                return .unauthorized
            default:
                return .unknown
            }
        }
        let nsError = error as NSError
        if nsError.code == NSURLErrorTimedOut || nsError.domain == NSURLErrorDomain {
            return .networkFailed
        }
        if nsError.code == 401 || nsError.code == 403 {
            return .unauthorized
        }
        let description = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        let lower = description.lowercased()
        if lower.contains("unauthorized") || lower.contains("forbidden")
            || lower.contains("401") || lower.contains("403")
            || description.contains("未授权") || description.contains("登录")
            || description.contains("凭据") || description.contains("钥匙串")
            || description.contains("额度") {
            return .unauthorized
        }
        if lower.contains("timed out") || lower.contains("timeout") || description.contains("超时") {
            return .timeout
        }
        if lower.contains("parse") || lower.contains("decode") || description.contains("解析") {
            return .parseFailed
        }
        return .unknown
    }

    /// 相对时间描述（与额度卡"刚刚 / N 分钟前"同一套口径）。
    static func relativeTime(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date).rounded()))
        if seconds < 60 {
            return L("刚刚")
        }
        if seconds < 3_600 {
            return LFormat("%d 分钟前", max(1, seconds / 60))
        }
        if seconds < 86_400 {
            return LFormat("%d 小时前", max(1, seconds / 3_600))
        }
        return LFormat("%d 天前", max(1, seconds / 86_400))
    }
}

// MARK: - 展示术语（浮层 / 主窗口 / 设置 / 文档统一）

extension UsageFreshness {
    /// 状态主标签。
    var statusLabel: String {
        switch kind {
        case .neverSucceeded: return L("暂无数据")
        case .fresh: return L("已同步")
        case .aging: return L("数据待更新")
        case .stale: return L("同步失败")
        case .partial: return L("部分来源失败")
        case .disabled: return L("已关闭")
        }
    }

    /// 失败但保留旧值时的补充说明。
    var keepsLastValueLabel: String? {
        switch kind {
        case .stale: return L("显示最后成功数据")
        default: return nil
        }
    }

    /// "最后成功 …"标签；从未成功时为 nil。
    func lastSucceededLabel(now: Date = Date()) -> String? {
        guard let lastSucceededAt else { return nil }
        return LFormat("最后成功 %@", FreshnessPolicy.relativeTime(since: lastSucceededAt, now: now))
    }

    /// 是否需要用户注意（非 fresh/disabled）。
    var needsAttention: Bool {
        switch kind {
        case .fresh, .disabled: return false
        case .neverSucceeded, .aging, .stale, .partial: return true
        }
    }
}
