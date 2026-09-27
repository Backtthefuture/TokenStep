import SwiftUI

// MARK: - Shared pieces

/// Card title with an optional muted note on the right, as on the Token Rank
/// profile page.
struct DashboardCardHeader<Trailing: View>: View {
    var title: String
    var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.tokenInk)
            Spacer(minLength: 8)
            trailing
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

extension DashboardCardHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

enum DashboardHeatColors {
    static func color(level: Int) -> Color {
        let palette = TokenStepThemeRuntime.palette
        switch level {
        case 4: return palette.activity4.color
        case 3: return palette.activity3.color
        case 2: return palette.activity2.color
        case 1: return palette.activity1.color
        default: return Color.tokenTrack
        }
    }
}

// MARK: - Ring

struct TodayRingCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let lap = appState.todayLap
        let composition = TodayOverviewModel.composition(appState.todayAgentWork)
        TokenCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 22) {
                    ZStack {
                        ring(lap)
                        VStack(spacing: 2) {
                            CompactPopoverStyle.tokens(appState.today.totalTokens, size: 28, weight: .bold, design: .rounded)
                                .foregroundStyle(Color.tokenInk)
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                            Text(L("今日 Token"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 108)
                    }
                    .frame(width: 144, height: 144)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(lap.lapStatusText)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.tokenGreenDark)
                            .monospacedDigit()
                        Text(LFormat("每圈目标 %@", TokenStepFormat.tokens(appState.settings.dailyGoalTokens, compact: true)))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.tokenInk.opacity(0.72))
                        if lap.completedLaps > 0 {
                            Text(LFormat("今日已跑满 %d 圈", lap.completedLaps))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.tokenInk.opacity(0.72))
                        }
                        if let delta = yesterdayDelta {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("比昨天同一时间"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(delta >= 0
                                    ? LFormat("多 %@", TokenStepFormat.tokens(delta, compact: true))
                                    : LFormat("少 %@", TokenStepFormat.tokens(-delta, compact: true)))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(delta >= 0 ? Color.tokenGreenDark : Color.tokenInk.opacity(0.7))
                                    .monospacedDigit()
                            }
                            .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }

                if !composition.isEmpty {
                    compositionView(composition)
                }
            }
        }
    }

    @ViewBuilder
    private func ring(_ lap: TokenStepLapProgress) -> some View {
        if TokenStepThemeRuntime.isVoyage {
            VoyageBowProgressView(progress: lap.currentLapProgress, lineWidth: 12, color: lap.ringColor)
        } else if TokenStepThemeRuntime.isInterstellar {
            ProgressRingView(progress: lap.currentLapProgress, lineWidth: 12, color: lap.ringColor)
                .overlay {
                    InterstellarEventHorizonEmblem()
                        .padding(30)
                        .opacity(0.4)
                }
        } else {
            ProgressRingView(progress: lap.currentLapProgress, lineWidth: 12, color: lap.ringColor)
        }
    }

    private func compositionView(_ composition: TodayOverviewModel.Composition) -> some View {
        let parts: [(String, Int, Color)] = [
            (L("输入"), composition.freshInput, TokenStepThemeRuntime.palette.activity3.color),
            (L("缓存读取"), composition.cacheRead, TokenStepThemeRuntime.palette.activity1.color),
            (L("输出"), composition.output, TokenStepThemeRuntime.palette.activity4.color)
        ]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Token 构成"))
                Spacer()
                if let rate = appState.todayAgentWork.cacheHitRate {
                    Text(LFormat("缓存命中 %@", TokenStepFormat.percent(rate * 100)))
                        .monospacedDigit()
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            GeometryReader { proxy in
                let visible = parts.filter { $0.1 > 0 }
                let gaps = CGFloat(max(visible.count - 1, 0)) * 2
                HStack(spacing: 2) {
                    ForEach(visible, id: \.0) { part in
                        Rectangle()
                            .fill(part.2)
                            .frame(width: max(2, (proxy.size.width - gaps) * composition.share(part.1)))
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())

            HStack(spacing: 14) {
                ForEach(parts, id: \.0) { part in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(part.2).frame(width: 8, height: 8)
                        Text("\(part.0) \(TokenStepFormat.tokens(part.1, compact: true))")
                            .monospacedDigit()
                    }
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    private var yesterdayDelta: Int? {
        let calendar = TokenStepClock.calendar
        let now = Date()
        guard appState.today.date == DateFormatter.tokenStepDay.string(from: now),
              let yesterday = calendar.date(byAdding: .day, value: -1, to: now)
        else { return nil }
        let key = DateFormatter.tokenStepDay.string(from: yesterday)
        return TodayOverviewModel.deltaVersusYesterday(
            today: appState.todayAgentWork,
            yesterday: appState.snapshot.agentWork(for: key),
            throughHour: calendar.component(.hour, from: now)
        )
    }
}

// MARK: - Metric tiles

struct TodayMetricTile: View {
    var label: String
    var value: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.tokenInk)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 104, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.tokenSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.tokenHairline))
        .accessibilityElement(children: .combine)
    }
}

struct TodayMetricsGrid: View {
    @EnvironmentObject private var appState: AppState
    /// 2 for a 2×2 block beside the ring, 4 for one row under it.
    var columns: Int = 2

    var body: some View {
        let work = appState.todayAgentWork
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns),
            spacing: 12
        ) {
            TodayMetricTile(
                label: L("估算金额"),
                value: TokenStepFormat.money(appState.today.cost),
                note: L("按官方单价估算")
            )
            TodayMetricTile(
                label: L("活跃时长"),
                value: LFormat("%d 小时", work.recordedActiveHours),
                note: L("有用量的整点数")
            )
            TodayMetricTile(
                label: L("模型请求"),
                value: work.modelRequestCount.formatted(),
                note: LFormat("工具调用 %@ 次", work.toolCallCount.formatted())
            )
            rankOrTotalTile
        }
    }

    @ViewBuilder
    private var rankOrTotalTile: some View {
        if appState.shouldShowAgentWorkRank,
           let identity = appState.agentWorkRankIdentity,
           let board = appState.tokenRank,
           let mine = board.entry(matching: identity.id) {
            TodayMetricTile(
                label: L("今日排名"),
                value: "#\(mine.rank)",
                note: LFormat("共 %d 人", board.totalRankedUsers)
            )
        } else {
            TodayMetricTile(
                label: L("累计 Token"),
                value: TokenStepFormat.tokens(appState.snapshot.totals.tokens, compact: true),
                note: LFormat("活跃 %d 天", appState.snapshot.totals.activeDays)
            )
        }
    }
}

// MARK: - Recent weeks

struct TodayRecentWeeksCard: View {
    @EnvironmentObject private var appState: AppState
    var openHistory: (() -> Void)?

    private let cell: CGFloat = 22
    private let gap: CGFloat = 5

    var body: some View {
        let calendar = TokenStepClock.calendar
        let goal = appState.settings.dailyGoalTokens
        let cells = TodayOverviewModel.recentWeeks(
            daily: appState.snapshot.daily,
            goal: goal,
            today: Date(),
            weeks: 5,
            calendar: calendar
        )
        let streak = TodayOverviewModel.goalStreak(daily: appState.snapshot.daily, goal: goal, today: Date(), calendar: calendar)
        TokenCard {
            VStack(alignment: .leading, spacing: 12) {
                DashboardCardHeader(L("近 5 周")) {
                    if let openHistory {
                        Button(action: openHistory) {
                            Text(L("全部历史 →"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.tokenGreenDark)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Spacer(minLength: 0)
                    VStack(spacing: gap) {
                        ForEach(weekdayLabels.indices, id: \.self) { index in
                            Text(weekdayLabels[index])
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .frame(height: cell)
                        }
                    }
                    LazyHGrid(rows: Array(repeating: GridItem(.fixed(cell), spacing: gap), count: 7), spacing: gap) {
                        ForEach(cells) { item in
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(item.isFuture ? Color.clear : DashboardHeatColors.color(level: item.level))
                                .overlay {
                                    if item.isFuture {
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .stroke(Color.tokenHairline, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                    }
                                }
                                .overlay {
                                    if item.isToday {
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .stroke(Color.tokenInk, lineWidth: 1.5)
                                    }
                                }
                                .frame(width: cell, height: cell)
                                .help("\(item.date) · \(TokenStepFormat.tokens(item.tokens, compact: true))")
                        }
                    }
                    .fixedSize()
                    Spacer(minLength: 0)
                }

                HStack {
                    Text(LFormat("连续达标 %d 天", streak))
                        .monospacedDigit()
                    Spacer()
                    HStack(spacing: 3) {
                        Text(L("少"))
                        ForEach(0..<5, id: \.self) { level in
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(DashboardHeatColors.color(level: level))
                                .frame(width: 10, height: 10)
                        }
                        Text(L("多"))
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var weekdayLabels: [String] {
        [L("一"), "", L("三"), "", L("五"), "", L("日")]
    }
}

// MARK: - Hourly

struct TodayHourlyStackCard: View {
    @EnvironmentObject private var appState: AppState
    private let chartHeight: CGFloat = 120

    var body: some View {
        let chart = TodayOverviewModel.hourlyChart(work: appState.todayAgentWork, currentHour: currentHour)
        TokenCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(L("今日分时消耗"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.tokenInk)
                    if let peak = chart.peakHour {
                        Text(LFormat("峰值 %02d:00 · %@", peak, TokenStepFormat.tokens(chart.peakTokens, compact: true)))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    ForEach(Array(chart.sourceOrder.enumerated()), id: \.offset) { _, source in
                        HStack(spacing: 6) {
                            Circle().fill(color(source)).frame(width: 8, height: 8)
                            Text(source.isEmpty ? L("其他") : source)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Color.tokenInk.opacity(0.75))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .overlay(Capsule().stroke(Color.tokenHairline))
                    }
                }

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(chart.hours) { hour in
                        VStack(spacing: 1) {
                            ForEach(Array(hour.parts.enumerated().reversed()), id: \.offset) { index, tokens in
                                if tokens > 0 {
                                    Rectangle()
                                        .fill(color(chart.sourceOrder[index]))
                                        .frame(height: height(tokens, max: chart.maxTotal))
                                }
                            }
                            if hour.total == 0 {
                                Rectangle()
                                    .fill(Color.tokenTrack)
                                    .frame(height: 3)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .help(hourHelp(hour, chart: chart))
                    }
                }
                .frame(height: chartHeight, alignment: .bottom)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.tokenHairline).frame(height: 1)
                }

                HStack {
                    Text("00"); Spacer(); Text("06"); Spacer(); Text("12"); Spacer(); Text("18"); Spacer(); Text("23")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

                if appState.todayAgentWork.unbucketedTokens > 0 {
                    Text(LFormat("另有 %@ 没有时间戳，未计入分时", TokenStepFormat.tokens(appState.todayAgentWork.unbucketedTokens, compact: true)))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var currentHour: Int? {
        let now = Date()
        guard appState.today.date == DateFormatter.tokenStepDay.string(from: now) else { return nil }
        return TokenStepClock.calendar.component(.hour, from: now)
    }

    private func color(_ source: String) -> Color {
        source.isEmpty ? Color.tokenInk.opacity(0.3) : tokenToolColor(source)
    }

    private func height(_ tokens: Int, max maxTotal: Int) -> CGFloat {
        guard maxTotal > 0 else { return 0 }
        return Swift.max(2, (chartHeight - 4) * CGFloat(tokens) / CGFloat(maxTotal))
    }

    private func hourHelp(_ hour: TodayOverviewModel.HourStack, chart: TodayOverviewModel.HourlyChart) -> String {
        let parts = zip(chart.sourceOrder, hour.parts)
            .filter { $0.1 > 0 }
            .map { "\($0.0.isEmpty ? L("其他") : $0.0) \(TokenStepFormat.tokens($0.1, compact: true))" }
        let head = String(format: "%02d:00 · %@", hour.hour, TokenStepFormat.tokens(hour.total, compact: true))
        return parts.isEmpty ? head : head + "\n" + parts.joined(separator: "\n")
    }
}

// MARK: - Clients and models

struct TodayClientsCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let rows = TodaySourceRows.make(tools: appState.today.tools, maxNamed: 4)
        TokenCard {
            VStack(alignment: .leading, spacing: 12) {
                DashboardCardHeader(L("客户端")) { Text(L("今日")) }
                if rows.isEmpty {
                    Text(L("等待下一次同步"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                } else {
                    ForEach(rows) { row in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(row.color ?? Color.tokenInk.opacity(0.35))
                                .frame(width: 8, height: 8)
                            Text(row.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.tokenInk)
                                .lineLimit(1)
                                .frame(width: 120, alignment: .leading)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.tokenTrack)
                                    Capsule()
                                        .fill(row.color ?? Color.tokenInk.opacity(0.35))
                                        .frame(width: max(4, proxy.size.width * min(max(row.percent, 0), 100) / 100))
                                }
                            }
                            .frame(height: 6)
                            Text(TokenStepFormat.tokens(row.tokens, compact: true))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.tokenInk)
                                .monospacedDigit()
                                .frame(width: 72, alignment: .trailing)
                            Text(TokenStepFormat.percent(row.percent))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                        .frame(height: 28)
                    }
                }
            }
        }
    }
}

struct TodayModelRankCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let rows = TodayModelUsageRows.make(from: appState.today)
        let visible = Array(rows.prefix(TodayModelUsageRows.maximumVisibleRows))
        TokenCard {
            VStack(alignment: .leading, spacing: 12) {
                DashboardCardHeader(L("模型排行")) { Text(L("今日 · 金额为估算")) }
                if appState.today.totalTokens <= 0 {
                    Text(L("今日暂无使用记录"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                } else if visible.isEmpty {
                    Text(L("已有总量，等待模型明细同步"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                } else {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 16, alignment: .leading)
                            Text(row.model)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.tokenInk)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(TokenStepFormat.tokens(row.tokens, compact: true))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.tokenInk)
                                .monospacedDigit()
                                .frame(width: 72, alignment: .trailing)
                            Text(row.estimatedCost.map { TokenStepFormat.money($0) } ?? "—")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 72, alignment: .trailing)
                        }
                        .frame(height: 28)
                    }
                    if rows.count > visible.count {
                        Text(LFormat("还有 %d 个模型", rows.count - visible.count))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
