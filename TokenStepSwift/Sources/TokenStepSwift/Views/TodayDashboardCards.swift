import SwiftUI

struct TodayHeroCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let lap = appState.todayLap
        TokenCard {
            HStack(alignment: .center, spacing: 20) {
                ZStack {
                    ProgressRingView(progress: lap.currentLapProgress, lineWidth: 16, color: lap.ringColor)
                    VStack(spacing: 4) {
                        Text(TokenStepFormat.tokens(appState.today.totalTokens))
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.tokenInk)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text(LFormat("/ %@ 每圈", TokenStepFormat.tokens(appState.settings.dailyGoalTokens, compact: true)))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 100)
                }
                .frame(width: 132, height: 132)

                VStack(alignment: .leading, spacing: 10) {
                    Text(lap.lapStatusText)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.tokenInk)
                    Text(heroSubtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TodayMetricChip(label: L("消耗金额"), value: TokenStepFormat.money(appState.today.cost))
                        TodayMetricChip(label: L("活跃小时"), value: "\(appState.todayAgentWork.recordedActiveHours) h")
                        TodayMetricChip(label: L("累计"), value: TokenStepFormat.tokens(appState.snapshot.totals.tokens, compact: true))
                        TodayMetricChip(label: L("达标天"), value: LFormat("%d 天", appState.goalDays))
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var heroSubtitle: String {
        let today = DateFormatter.tokenStepDay.string(from: Date())
        return LFormat("今日 %@ · 已达标 %d 圈", today, appState.todayLap.completedLaps)
    }
}

struct TodayAgentIntensityCard: View {
    @EnvironmentObject private var appState: AppState

    private var work: DailyAgentWork {
        appState.todayAgentWork
    }

    var body: some View {
        TokenCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Agent 工作强度"))
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                    Text(L("本版补全：请求数 / 工具调用 / 输出"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    TodayBigStat(label: L("模型请求"), value: compactCount(work.modelRequestCount))
                    TodayBigStat(label: L("工具调用"), value: compactCount(work.toolCallCount))
                    TodayBigStat(label: L("缓存命中"), value: cacheRateText)
                }

                VStack(spacing: 0) {
                    TodayKVRow(label: L("输入"), value: TokenStepFormat.tokens(work.inputTokens, compact: true))
                    TodayKVRow(label: L("缓存读取"), value: TokenStepFormat.tokens(work.cachedInputTokens, compact: true))
                    TodayKVRow(label: L("输出"), value: TokenStepFormat.tokens(work.outputTokens, compact: true))
                }
            }
        }
    }

    private var cacheRateText: String {
        if let rate = work.cacheHitRate {
            return TokenStepFormat.percent(rate * 100)
        }
        return "--"
    }

    private func compactCount(_ value: Int) -> String {
        TokenStepFormat.tokens(value, compact: true)
    }
}

struct TodayHourlyCard: View {
    @EnvironmentObject private var appState: AppState

    private var work: DailyAgentWork {
        appState.todayAgentWork
    }

    var body: some View {
        TokenCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("今日分时"))
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                    Text(L("来自 hourlyBuckets · 活跃小时由此重算"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<24, id: \.self) { hour in
                        let tokens = work.bucket(hour: hour).totalTokens
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.tokenGreen, Color.tokenGreenDark],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(maxWidth: .infinity, minHeight: 3, maxHeight: barHeight(tokens))
                            .opacity(tokens > 0 ? 1 : 0.18)
                    }
                }
                .frame(height: 78, alignment: .bottom)

                HStack {
                    Text("0")
                    Spacer()
                    Text("6")
                    Spacer()
                    Text("12")
                    Spacer()
                    Text("18")
                    Spacer()
                    Text("23")
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

                if work.unbucketedTokens > 0 {
                    Text(LFormat("无时间戳 %@ 已单列，不摊进任何小时。", TokenStepFormat.tokens(work.unbucketedTokens, compact: true)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func barHeight(_ tokens: Int) -> CGFloat {
        let maxTokens = max(1, work.hourlyBuckets.map(\.totalTokens).max() ?? 0)
        guard tokens > 0 else { return 3 }
        return max(6, 78 * CGFloat(tokens) / CGFloat(maxTokens))
    }
}

struct TodaySourcesCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TokenCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("今日来源"))
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                    Text(L("本地账本 + Cursor 官方用量 · 计入圆环"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if rows.isEmpty {
                    Text(L("等待下一次同步"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                } else {
                    VStack(spacing: 8) {
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Circle()
                                        .fill(row.color ?? Color.tokenInk.opacity(0.35))
                                        .frame(width: 8, height: 8)
                                    Text(row.name)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(Color.tokenInk)
                                    Spacer()
                                    Text(TokenStepFormat.tokens(row.tokens, compact: true))
                                        .font(.callout.weight(.heavy))
                                        .foregroundStyle(Color.tokenInk)
                                        .monospacedDigit()
                                }
                                GeometryReader { proxy in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.tokenTrack)
                                        Capsule()
                                            .fill(row.color ?? Color.tokenInk.opacity(0.35))
                                            .frame(width: max(4, proxy.size.width * min(max(row.percent, 0), 100) / 100))
                                    }
                                }
                                .frame(height: 5)
                            }
                        }
                    }
                }
            }
        }
    }

    private var rows: [TodayBreakdownRow] {
        TodaySourceRows.make(tools: appState.today.tools)
    }
}

enum TodaySourceRows {
    static func make(tools: [String: Int], maxNamed: Int = 3) -> [TodayBreakdownRow] {
        let total = tools.values.reduce(0, +)
        guard total > 0 else { return [] }
        let ranked = orderedToolEntries(tools)
        let named = Array(ranked.prefix(maxNamed))
        let rest = Array(ranked.dropFirst(maxNamed))
        var rows = named.map { entry in
            TodayBreakdownRow(
                name: entry.name,
                tokens: entry.tokens,
                percent: Double(entry.tokens) * 100 / Double(total),
                color: tokenToolColor(entry.name)
            )
        }
        if !rest.isEmpty {
            let tokens = rest.map(\.tokens).reduce(0, +)
            rows.append(
                TodayBreakdownRow(
                    name: LFormat("其他 %d 个来源", rest.count),
                    tokens: tokens,
                    percent: Double(tokens) * 100 / Double(total),
                    color: Color.tokenInk.opacity(0.35)
                )
            )
        }
        return rows
    }
}

struct TodayModelUsageRow: Identifiable, Equatable {
    var id: String { model }
    var model: String
    var tokens: Int
    var percent: Double
    var estimatedCost: Double?
}

enum TodayModelUsageRows {
    static let maximumVisibleRows = 5
    static let colorSlotCount = 4

    static func make(from usage: DailyUsage) -> [TodayModelUsageRow] {
        guard usage.totalTokens > 0 else { return [] }
        let sorted = usage.models
            .filter { $0.value > 0 }
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
            }
            .map { model, tokens in
                TodayModelUsageRow(
                    model: model,
                    tokens: tokens,
                    percent: min(100, max(0, Double(tokens) * 100 / Double(usage.totalTokens))),
                    estimatedCost: usage.modelCosts[model]
                )
            }

        guard sorted.count > 2 else { return sorted }
        return sorted.enumerated()
            .filter { index, row in index < 2 || row.percent >= 0.1 }
            .map(\.element)
    }

    static func colorSlot(for model: String) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in model.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(colorSlotCount))
    }

    static func hasTokenTotalMismatch(_ usage: DailyUsage) -> Bool {
        guard usage.totalTokens > 0, !usage.models.isEmpty else { return false }
        return usage.models.values.filter { $0 > 0 }.reduce(0, +) != usage.totalTokens
    }
}

struct TodayModelUsageCard: View {
    @EnvironmentObject private var appState: AppState

    private var usage: DailyUsage { appState.today }
    private var rows: [TodayModelUsageRow] { TodayModelUsageRows.make(from: usage) }
    private var visibleRows: ArraySlice<TodayModelUsageRow> { rows.prefix(TodayModelUsageRows.maximumVisibleRows) }
    private var hiddenCount: Int { max(0, rows.count - TodayModelUsageRows.maximumVisibleRows) }

    var body: some View {
        TokenCard {
            VStack(alignment: .leading, spacing: 11) {
                header

                if usage.totalTokens <= 0 {
                    emptyState(L("今日暂无使用记录"))
                } else if rows.isEmpty {
                    emptyState(L("已有总量，等待模型明细同步"))
                } else {
                    columnHeader
                    VStack(spacing: 0) {
                        ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, row in
                            modelRow(row)
                            if index < visibleRows.count - 1 {
                                Divider().opacity(0.55)
                            }
                        }
                    }
                    if hiddenCount > 0 {
                        Text(LFormat("还有 %d 个模型", hiddenCount))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if TodayModelUsageRows.hasTokenTotalMismatch(usage) {
                        Label(
                            L("模型明细合计与今日总量不一致；占比按今日总量计算。"),
                            systemImage: "info.circle"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("今日模型消耗"))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color.tokenInk)
                Text(L("按模型查看今日 Token、占比与金额估算"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(LFormat("今日 · %d 个模型", rows.count))
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.tokenGreenDark)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.tokenMint.opacity(0.24), in: Capsule())
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Text(L("模型")).frame(width: 190, alignment: .leading)
            Spacer(minLength: 60)
            Text("Token").frame(width: 104, alignment: .trailing)
            Text(L("占比")).frame(width: 72, alignment: .trailing)
            Text(L("金额估算")).frame(width: 96, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(.secondary)
    }

    private func modelRow(_ row: TodayModelUsageRow) -> some View {
        let color = rowColor(model: row.model)
        return HStack(spacing: 12) {
            HStack(spacing: 9) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(displayName(row.model))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.tokenInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.model)
            }
            .frame(width: 190, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.tokenTrack)
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, proxy.size.width * row.percent / 100))
                }
            }
            .frame(height: 6)

            Text(TokenStepFormat.tokens(row.tokens, compact: true))
                .frame(width: 104, alignment: .trailing)
            Text(TokenStepFormat.percent(row.percent))
                .frame(width: 72, alignment: .trailing)
            Text(row.estimatedCost.map { TokenStepFormat.money($0) } ?? "—")
                .frame(width: 96, alignment: .trailing)
                .help(L("按 API 列表价估算，不代表订阅或实际账单。"))
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(Color.tokenInk.opacity(0.78))
        .monospacedDigit()
        .frame(height: 34)
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    }

    private func displayName(_ model: String) -> String {
        model.lowercased() == "unknown" ? L("未知模型") : model
    }

    private func rowColor(model: String) -> Color {
        switch TodayModelUsageRows.colorSlot(for: model) {
        case 0: return .tokenGreenDark
        case 1: return TokenStepThemeRuntime.palette.activity3.color
        case 2: return TokenStepThemeRuntime.palette.activity2.color
        default: return .tokenGreen
        }
    }
}

private struct TodayMetricChip: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.tokenInk)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.tokenTrack.opacity(0.42), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.black.opacity(0.04)))
    }
}

private struct TodayBigStat: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.tokenInk)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TodayKVRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.tokenInk)
            Spacer()
            Text(value)
                .font(.callout.weight(.heavy))
                .foregroundStyle(Color.tokenInk)
                .monospacedDigit()
        }
        .padding(.vertical, 7)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 1)
        }
    }
}
