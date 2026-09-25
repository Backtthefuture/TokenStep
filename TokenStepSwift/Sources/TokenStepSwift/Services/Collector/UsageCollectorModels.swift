import Foundation

struct CollectorResult {
    var records: [UsageRecord]
    var source: SourceInfo
}

struct CodexCollectionOutcome {
    var result: CollectorResult
    var usedIncrementalStore: Bool
}

struct PendingCodexSession {
    var path: URL
    var metadata: (size: UInt64, modificationTime: TimeInterval)
    var fingerprint: String
    var validationFingerprint: String? = nil
    var scan: CodexSessionScan
}

struct StoredCodexSessionMetadata {
    var size: UInt64
    var modificationTime: TimeInterval
    var fingerprint: String
    var validationFingerprint: String?
    var sessionID: String
}

struct CodexCachedSession {
    var path: String
    var size: UInt64
    var modificationTime: TimeInterval
    var fingerprint: String
    var validationFingerprint: String? = nil
    var sessionID: String
    var createdAtEpoch: TimeInterval?
    var parentSessionID: String?
    var anchors: [CodexAnchor]
    var records: [UsageRecord]
    var summaryRecords: [UsageRecord]
    var cursor: CodexSessionCursor
    var diagnostics: CodexCollectionDiagnostics

    func hasSameStoredAccounting(as other: CodexCachedSession) -> Bool {
        path == other.path
            && size == other.size
            && abs(modificationTime - other.modificationTime) < 0.001
            && fingerprint == other.fingerprint
            && sessionID == other.sessionID
            && createdAtEpoch == other.createdAtEpoch
            && parentSessionID == other.parentSessionID
            && anchors == other.anchors
            && records == other.records
            && summaryRecords == other.summaryRecords
            && cursor == other.cursor
            && diagnostics == other.diagnostics
    }
}

struct CodexCachedContribution {
    var records: [UsageRecord]
    var recordCount: Int
    var diagnostics: CodexCollectionDiagnostics
}

struct CodexSummaryKey: Hashable {
    var date: String
    var model: String
    var hour: Int?
}

struct CodexSummaryAccumulator {
    var timestamp: String?
    var timestampEpoch: TimeInterval?
    var usage = TokenUsageCounts()
    var modelRequestCount = 0
    var toolCallCount = 0

    mutating func add(_ record: UsageRecord) {
        timestamp = timestamp ?? record.timestamp
        timestampEpoch = timestampEpoch ?? record.timestampEpoch
        usage.add(record.usage)
        modelRequestCount += max(0, record.modelRequestCount)
        toolCallCount += max(0, record.toolCallCount)
    }
}

struct CollectorCache: Codable {
    static let currentVersion = UsageCollector.codexAccountingRevision

    var version = currentVersion
    // Cached records carry day keys, so they are only reusable in the zone that
    // produced them. Nil means the cache predates this field (legacy zone).
    var timeZone: String? = UsageCollector.timezone.identifier
    var files: [String: CachedUsageFile] = [:]
}

struct CollectorCacheLoad {
    var cache: CollectorCache
    var recalibratedFromRevision: Int?
}

struct CachedUsageFile: Codable {
    var tool: String
    var size: UInt64
    var modificationTime: TimeInterval
    var records: [UsageRecord]
    var codexScan: CodexSessionScan? = nil
    var contentFingerprint: String? = nil
    var claudeState: ClaudeFileState? = nil
}

/// Resume point for appending Claude Code transcripts.
struct ClaudeFileState: Codable {
    /// Byte offset just past the last complete line that was read.
    var processedBytes: UInt64 = 0
    /// Number of lines containing "usage" read so far; line-number identities depend on it.
    var usageLineCount = 0
    var candidates: [String: ClaudeUsageCandidate] = [:]
    /// `contentFingerprint` of the first `processedBytes` bytes, to detect rewrites.
    var prefixFingerprint: String?
}

struct CodexSessionScan: Codable {
    var canonicalSessionID: String
    var createdAt: String?
    var parentSessionID: String?
    var sourcePath: String
    var events: [CodexTokenEvent]
    var finalModel: String? = nil
    var relevantLineCount: Int? = nil
}

struct CodexTokenEvent: Codable {
    var timestamp: String?
    var timestampEpoch: TimeInterval? = nil
    var model: String
    var cumulativePresent: Bool
    var cumulative: TokenUsageCounts?
    var last: TokenUsageCounts?
    var modelContextWindow: Int
    var lineNumber: Int
}

struct CodexAnchor: Codable, Equatable {
    var timestamp: TimeInterval
    var usage: TokenUsageCounts
}

struct CodexDeltaCursor {
    var hasCumulativeSchema: Bool
    var previousCumulative: TokenUsageCounts?
    var epoch: Int
}

struct CodexSessionCursor: Codable, Equatable {
    var currentModel: String
    var relevantLineNumber: Int
    var hasCumulativeSchema: Bool
    var previousCumulative: TokenUsageCounts?
    var epoch: Int
}

struct CodexSessionTail {
    var events: [CodexTokenEvent]
    var currentModel: String
    var relevantLineNumber: Int
    var processedSize: UInt64
    var modificationTime: TimeInterval
    var fingerprint: String
}

struct CodexCollectionDiagnostics: Codable, Equatable {
    var rawRecords = 0
    var exactRecords = 0
    var legacyRecords = 0
    var duplicateRecords = 0
    var counterResets = 0
    var inheritedRecords = 0
    var inheritedTokens = 0
    var skippedRecords = 0
    var unknownBreakdownRecords = 0

    mutating func add(_ other: CodexCollectionDiagnostics) {
        rawRecords += other.rawRecords
        exactRecords += other.exactRecords
        legacyRecords += other.legacyRecords
        duplicateRecords += other.duplicateRecords
        counterResets += other.counterResets
        inheritedRecords += other.inheritedRecords
        inheritedTokens += other.inheritedTokens
        skippedRecords += other.skippedRecords
        unknownBreakdownRecords += other.unknownBreakdownRecords
    }
}

struct UsageRecord: Codable, Equatable {
    var date: String
    var timestamp: String?
    var timestampEpoch: TimeInterval? = nil
    var tool: String
    var model: String
    var usage: TokenUsageCounts
    var costUSD: Double? = nil
    var source: UsageRecordSource = .unknown
    var requestID: String? = nil
    var sessionID: String? = nil
    var responseID: String? = nil
    var sourcePath: String? = nil
    var lineNumber: Int? = nil
    var dataSource: String? = nil
    var modelRequestCount = 1
    var toolCallCount = 0

    enum CodingKeys: String, CodingKey {
        case date
        case timestamp
        case timestampEpoch
        case tool
        case model
        case usage
        case costUSD
        case source
        case requestID
        case sessionID
        case responseID
        case sourcePath
        case lineNumber
        case dataSource
        case modelRequestCount
        case toolCallCount
    }

    init(
        date: String,
        timestamp: String?,
        timestampEpoch: TimeInterval? = nil,
        tool: String,
        model: String,
        usage: TokenUsageCounts,
        costUSD: Double? = nil,
        source: UsageRecordSource = .unknown,
        requestID: String? = nil,
        sessionID: String? = nil,
        responseID: String? = nil,
        sourcePath: String? = nil,
        lineNumber: Int? = nil,
        dataSource: String? = nil,
        modelRequestCount: Int = 1,
        toolCallCount: Int = 0
    ) {
        self.date = date
        self.timestamp = timestamp
        self.timestampEpoch = timestampEpoch
        self.tool = tool
        self.model = model
        self.usage = usage
        self.costUSD = costUSD
        self.source = source
        self.requestID = requestID
        self.sessionID = sessionID
        self.responseID = responseID
        self.sourcePath = sourcePath
        self.lineNumber = lineNumber
        self.dataSource = dataSource
        self.modelRequestCount = modelRequestCount
        self.toolCallCount = toolCallCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        timestampEpoch = try container.decodeIfPresent(TimeInterval.self, forKey: .timestampEpoch)
        tool = try container.decode(String.self, forKey: .tool)
        model = try container.decode(String.self, forKey: .model)
        usage = try container.decode(TokenUsageCounts.self, forKey: .usage)
        costUSD = try container.decodeIfPresent(Double.self, forKey: .costUSD)
        source = try container.decodeIfPresent(UsageRecordSource.self, forKey: .source) ?? .unknown
        requestID = try container.decodeIfPresent(String.self, forKey: .requestID)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        responseID = try container.decodeIfPresent(String.self, forKey: .responseID)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
        lineNumber = try container.decodeIfPresent(Int.self, forKey: .lineNumber)
        dataSource = try container.decodeIfPresent(String.self, forKey: .dataSource)
        modelRequestCount = try container.decodeIfPresent(Int.self, forKey: .modelRequestCount) ?? 1
        toolCallCount = try container.decodeIfPresent(Int.self, forKey: .toolCallCount) ?? 0
    }
}

enum UsageRecordSource: String, Codable, Equatable {
    case nativeCodex
    case nativeCodexSQLite
    case nativeClaudeCode
    case ccSwitchProxy
    case zcode
    case hermes
    case workbuddy
    case unknown
}

struct CrossSourceDedupeResult {
    var records: [UsageRecord]
    var rawProxyRecords: Int
    var keptProxyRecords: Int
    var dedupedProxyRecords: Int
    var skippedProxyRecords: Int
}

struct ClaudeIdentity {
    var deduplicationKey: String
    var requestID: String?
    var responseID: String?
    var sessionID: String?
}

struct ClaudeUsageCandidate: Codable {
    var date: String
    var timestamp: String
    var model: String
    var usage: TokenUsageCounts
    var hasStopReason: Bool
    var lineNumber: Int
    var requestID: String?
    var responseID: String?
    var sessionID: String?
    var sourcePath: String

    var record: UsageRecord {
        UsageRecord(
            date: date,
            timestamp: timestamp,
            tool: "Claude Code",
            model: model,
            usage: usage,
            source: .nativeClaudeCode,
            requestID: requestID,
            sessionID: sessionID,
            responseID: responseID,
            sourcePath: sourcePath,
            lineNumber: lineNumber
        )
    }

    func isPreferred(over other: ClaudeUsageCandidate) -> Bool {
        if hasStopReason != other.hasStopReason {
            return hasStopReason
        }
        if timestamp != other.timestamp {
            return timestamp > other.timestamp
        }
        return lineNumber > other.lineNumber
    }
}

struct TokenUsageCounts: Codable, Equatable {
    var inputTokens = 0
    var outputTokens = 0
    var cacheCreationInputTokens = 0
    var cacheReadInputTokens = 0
    var reasoningOutputTokens = 0
    var totalTokens = 0

    mutating func add(_ other: TokenUsageCounts) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheCreationInputTokens += other.cacheCreationInputTokens
        cacheReadInputTokens += other.cacheReadInputTokens
        reasoningOutputTokens += other.reasoningOutputTokens
        totalTokens += other.totalTokens
    }

    var fingerprint: String {
        [
            totalTokens,
            inputTokens,
            cacheReadInputTokens,
            outputTokens,
            reasoningOutputTokens,
            cacheCreationInputTokens
        ].map(String.init).joined(separator: ":")
    }

    var cacheCoverageComplete: Bool {
        inputTokens >= 0
            && outputTokens >= 0
            && cacheCreationInputTokens >= 0
            && cacheReadInputTokens >= 0
            && reasoningOutputTokens >= 0
            && totalTokens == inputTokens + outputTokens
            && cacheCreationInputTokens + cacheReadInputTokens <= inputTokens
            && reasoningOutputTokens <= outputTokens
    }
}

struct UsageAccumulator {
    var usage = TokenUsageCounts()
    var cost = 0.0

    mutating func add(_ counts: TokenUsageCounts, cost: Double) {
        usage.inputTokens += counts.inputTokens
        usage.outputTokens += counts.outputTokens
        usage.cacheCreationInputTokens += counts.cacheCreationInputTokens
        usage.cacheReadInputTokens += counts.cacheReadInputTokens
        usage.reasoningOutputTokens += counts.reasoningOutputTokens
        usage.totalTokens += counts.totalTokens
        self.cost += cost
    }
}

struct DailyAccumulator {
    var date: String
    var tools: [String: Int] = [:]
    var models: [String: Int] = [:]
    var modelCosts: [String: Double] = [:]
    var totalTokens = 0
    var cost = 0.0

    mutating func add(record: UsageRecord, cost: Double) {
        tools[record.tool, default: 0] += record.usage.totalTokens
        models[record.model, default: 0] += record.usage.totalTokens
        modelCosts[record.model, default: 0] += cost
        totalTokens += record.usage.totalTokens
        self.cost += cost
    }
}

struct AgentWorkAccumulator {
    var date: String
    var totalTokens = 0
    var inputTokens = 0
    var cachedInputTokens = 0
    var outputTokens = 0
    var cacheCoverageComplete = true
    var unbucketedTokens = 0
    var activeHours = Set<Int>()
    var modelRequestCount = 0
    var toolCallCount = 0
    var sources: [String: AgentWorkSourceAccumulator] = [:]
    var hourlySources: [Int: [String: AgentWorkHourlySourceAccumulator]] = [:]

    mutating func add(record: UsageRecord, hour: Int?) {
        totalTokens += record.usage.totalTokens
        inputTokens += record.usage.inputTokens
        cachedInputTokens += record.usage.cacheReadInputTokens
        outputTokens += record.usage.outputTokens
        cacheCoverageComplete = cacheCoverageComplete && record.usage.cacheCoverageComplete
        if let hour {
            activeHours.insert(hour)
            var sourceRows = hourlySources[hour] ?? [:]
            sourceRows[record.tool, default: AgentWorkHourlySourceAccumulator(source: record.tool)]
                .add(record: record)
            hourlySources[hour] = sourceRows
        } else {
            unbucketedTokens += record.usage.totalTokens
        }
        modelRequestCount += max(0, record.modelRequestCount)
        toolCallCount += max(0, record.toolCallCount)
        sources[record.tool, default: AgentWorkSourceAccumulator(source: record.tool)]
            .add(record: record)
    }

    var dailyAgentWork: DailyAgentWork {
        DailyAgentWork(
            date: date,
            totalTokens: totalTokens,
            activeHours: activeHours.count,
            modelRequestCount: modelRequestCount,
            toolCallCount: toolCallCount,
            sources: sources.values
                .filter { $0.tokens > 0 }
                .sorted { $0.tokens > $1.tokens }
                .map(\.agentWorkSource),
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            cacheCoverageComplete: cacheCoverageComplete,
            hourlyBuckets: (0..<24).map { hour in
                AgentWorkHourBucket(
                    hour: hour,
                    sources: (hourlySources[hour] ?? [:]).values
                        .filter { $0.tokens > 0 }
                        .sorted {
                            if $0.tokens == $1.tokens {
                                return $0.source < $1.source
                            }
                            return $0.tokens > $1.tokens
                        }
                        .map(\.hourlySource)
                )
            },
            unbucketedTokens: unbucketedTokens
        )
    }
}

struct AgentWorkSourceAccumulator {
    var source: String
    var tokens = 0
    var modelRequestCount = 0
    var toolCallCount = 0

    mutating func add(record: UsageRecord) {
        tokens += record.usage.totalTokens
        modelRequestCount += max(0, record.modelRequestCount)
        toolCallCount += max(0, record.toolCallCount)
    }

    var agentWorkSource: AgentWorkSource {
        AgentWorkSource(
            source: source,
            tokens: tokens,
            modelRequestCount: modelRequestCount,
            toolCallCount: toolCallCount
        )
    }
}

struct AgentWorkHourlySourceAccumulator {
    var source: String
    var tokens = 0
    var inputTokens = 0
    var cachedInputTokens = 0
    var outputTokens = 0
    var cacheCoverageComplete = true

    mutating func add(record: UsageRecord) {
        tokens += record.usage.totalTokens
        inputTokens += record.usage.inputTokens
        cachedInputTokens += record.usage.cacheReadInputTokens
        outputTokens += record.usage.outputTokens
        cacheCoverageComplete = cacheCoverageComplete && record.usage.cacheCoverageComplete
    }

    var hourlySource: AgentWorkHourlySource {
        AgentWorkHourlySource(
            source: source,
            tokens: tokens,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            cacheCoverageComplete: cacheCoverageComplete
        )
    }
}

struct RhythmAccumulator {
    var date: String
    var hourlyTokens = Array(repeating: 0, count: 24)

    mutating func add(tokens: Int, hour: Int) {
        guard tokens > 0, (0..<hourlyTokens.count).contains(hour) else { return }
        hourlyTokens[hour] += tokens
    }

    var dailyRhythm: DailyRhythm {
        let buckets = hourlyTokens.enumerated().map { hour, tokens in
            HourlyTokenBucket(hour: hour, tokens: tokens)
        }
        let totalTokens = hourlyTokens.reduce(0, +)
        let peak = hourlyTokens.enumerated().max { left, right in
            if left.element == right.element {
                return left.offset > right.offset
            }
            return left.element < right.element
        }
        let peakHour = (peak?.element ?? 0) > 0 ? peak?.offset : nil
        let peakTokens = peak?.element ?? 0
        let activeThreshold = Self.significantTokenThreshold(totalTokens: totalTokens, peakTokens: peakTokens)
        let significantHourlyTokens = hourlyTokens.map { $0 >= activeThreshold ? $0 : 0 }
        let activeHours = significantHourlyTokens.filter { $0 > 0 }.count
        let firstActiveHour = significantHourlyTokens.firstIndex { $0 > 0 }
        let lastActiveHour = significantHourlyTokens.lastIndex { $0 > 0 }
        let primaryTag = Self.classify(
            hourlyTokens: hourlyTokens,
            significantHourlyTokens: significantHourlyTokens,
            totalTokens: totalTokens,
            peakHour: peakHour,
            peakTokens: peakTokens,
            activeHours: activeHours,
            firstActiveHour: firstActiveHour
        )

        return DailyRhythm(
            date: date,
            buckets: buckets,
            totalTokens: totalTokens,
            peakHour: peakHour,
            peakTokens: peakTokens,
            activeHours: activeHours,
            firstActiveHour: firstActiveHour,
            lastActiveHour: lastActiveHour,
            primaryTag: primaryTag,
            companionTag: Self.companionTag(for: primaryTag)
        )
    }

    static func classify(
        hourlyTokens: [Int],
        significantHourlyTokens: [Int],
        totalTokens: Int,
        peakHour: Int?,
        peakTokens: Int,
        activeHours: Int,
        firstActiveHour: Int?
    ) -> RhythmTag {
        guard totalTokens > 0 else { return .quietDay }
        let peakShare = share(peakTokens, of: totalTokens)
        if isDoublePeak(hourlyTokens: significantHourlyTokens, peakTokens: peakTokens) {
            return .doublePeak
        }
        if peakShare >= 0.50 {
            return .oneShot
        }

        let nightShare = share(tokens(in: [21, 22, 23, 0, 1, 2], hourlyTokens: significantHourlyTokens), of: totalTokens)
        if nightShare >= 0.35 || (peakHour.map { $0 >= 21 || $0 <= 2 } == true && nightShare >= 0.25) {
            return .nightAgent
        }

        let eveningShare = share(tokens(in: [19, 20], hourlyTokens: significantHourlyTokens), of: totalTokens)
        if peakHour.map({ (19...20).contains($0) }) == true || eveningShare >= 0.30 {
            return .eveningSprint
        }

        let afternoonShare = share(tokens(in: Array(14...18), hourlyTokens: significantHourlyTokens), of: totalTokens)
        if afternoonShare >= 0.35 || peakHour.map({ (14...18).contains($0) }) == true && afternoonShare >= 0.25 {
            return .afternoonBurst
        }

        let earlyShare = share(tokens(in: Array(5...9), hourlyTokens: significantHourlyTokens), of: totalTokens)
        if firstActiveHour.map({ $0 <= 8 }) == true && earlyShare >= 0.25 {
            return .earlyStarter
        }

        let morningShare = share(tokens(in: Array(8...12), hourlyTokens: significantHourlyTokens), of: totalTokens)
        if morningShare >= 0.35 || peakHour.map({ (8...12).contains($0) }) == true && morningShare >= 0.25 {
            return .morningPlanner
        }

        if activeHours >= 6 && peakShare < 0.35 {
            return .fragmented
        }
        if activeHours >= 4 {
            return .steadyCruise
        }
        return .quietDay
    }

    static func companionTag(for tag: RhythmTag) -> RhythmTag {
        switch tag {
        case .earlyStarter:
            return .nightAgent
        case .morningPlanner:
            return .afternoonBurst
        case .afternoonBurst:
            return .morningPlanner
        case .eveningSprint:
            return .steadyCruise
        case .nightAgent:
            return .earlyStarter
        case .doublePeak:
            return .steadyCruise
        case .fragmented:
            return .oneShot
        case .oneShot:
            return .fragmented
        case .steadyCruise:
            return .doublePeak
        case .quietDay:
            return .morningPlanner
        }
    }

    static func isDoublePeak(hourlyTokens: [Int], peakTokens: Int) -> Bool {
        guard peakTokens > 0 else { return false }
        let peaks = localPeakCandidates(hourlyTokens: hourlyTokens)
            .filter { Double($0.tokens) >= Double(peakTokens) * 0.45 }
            .sorted { $0.tokens > $1.tokens }
            .prefix(5)
        for left in peaks {
            for right in peaks where abs(left.hour - right.hour) >= 4 {
                return true
            }
        }
        return false
    }

    static func localPeakCandidates(hourlyTokens: [Int]) -> [(hour: Int, tokens: Int)] {
        hourlyTokens.enumerated().compactMap { hour, tokens in
            guard tokens > 0 else { return nil }
            let previous = hour > 0 ? hourlyTokens[hour - 1] : 0
            let next = hour < hourlyTokens.count - 1 ? hourlyTokens[hour + 1] : 0
            guard tokens >= previous && tokens >= next else { return nil }
            return (hour, tokens)
        }
    }

    static func tokens(in hours: [Int], hourlyTokens: [Int]) -> Int {
        hours.reduce(0) { total, hour in
            guard hourlyTokens.indices.contains(hour) else { return total }
            return total + hourlyTokens[hour]
        }
    }

    static func share(_ value: Int, of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(value) / Double(total)
    }

    static func significantTokenThreshold(totalTokens: Int, peakTokens: Int) -> Int {
        guard totalTokens > 0 else { return 1 }
        let totalBased = Double(totalTokens) * 0.03
        let peakBased = Double(peakTokens) * 0.30
        return max(1, Int(max(totalBased, peakBased).rounded()))
    }
}

struct ModelKey: Hashable {
    var tool: String
    var model: String
}
