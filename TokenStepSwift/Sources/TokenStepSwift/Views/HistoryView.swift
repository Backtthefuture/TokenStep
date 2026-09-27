import AppKit
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    /// Screenshots pass a row limit and show every row up to it; the window
    /// shows a few rows with an expand button.
    var historyLimit: Int? = nil

    var body: some View {
        VStack(spacing: 16) {
            HistorySummaryTiles()
            HistoryHeatmapCard()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    HistoryTrendCard()
                        .frame(minWidth: 520)
                    HistoryDistributionCard()
                        .frame(width: 340)
                }
                .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 16) {
                    HistoryTrendCard()
                    HistoryDistributionCard()
                }
            }
            HistoryDetailCard(historyLimit: historyLimit)
        }
    }
}

// MARK: - Summary

private struct HistorySummaryTiles: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let snapshot = appState.snapshot
        let goal = appState.settings.dailyGoalTokens
        let calendar = TokenStepClock.calendar
        let goalDays = snapshot.daily.filter { $0.totalTokens >= goal }.count
        let longest = TodayOverviewModel.longestGoalStreak(daily: snapshot.daily, goal: goal, calendar: calendar)
        let current = TodayOverviewModel.goalStreak(daily: snapshot.daily, goal: goal, today: Date(), calendar: calendar)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            TodayMetricTile(
                label: L("累计 Token"),
                value: TokenStepFormat.tokens(snapshot.totals.tokens, compact: true),
                note: firstDay.map { LFormat("自 %@ 起", $0) }
            )
            TodayMetricTile(
                label: L("估算金额"),
                value: TokenStepFormat.money(snapshot.totals.cost),
                note: L("按官方单价估算")
            )
            TodayMetricTile(
                label: L("活跃天数"),
                value: LFormat("%d 天", snapshot.totals.activeDays),
                note: LFormat("达标 %d 天", goalDays)
            )
            TodayMetricTile(
                label: L("最长连续达标"),
                value: LFormat("%d 天", longest),
                note: LFormat("当前连续 %d 天", current)
            )
        }
    }

    private var firstDay: String? {
        appState.snapshot.daily.first { $0.totalTokens > 0 }?.date
    }
}

// MARK: - Heatmap

private struct HistoryHeatmapCard: View {
    @EnvironmentObject private var appState: AppState

    private let cell: CGFloat = 12
    private let gap: CGFloat = 3
    private let hourPanelWidth: CGFloat = 250

    var body: some View {
        let recentWorks = Array(appState.snapshot.agentWork.suffix(30))
        let hourTotals = TodayOverviewModel.hourOfDayTotals(recentWorks)
        TokenCard {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    DashboardCardHeader(L("消耗热力图")) { Text(L("按天 · 描边为今天")) }
                    GeometryReader { proxy in
                        heatmap(width: proxy.size.width)
                    }
                    .frame(height: 16 + 7 * cell + 6 * gap)
                    footer
                }
                .frame(maxWidth: .infinity)

                Rectangle().fill(Color.tokenHairline).frame(width: 1)

                hourPanel(hourTotals)
                    .frame(width: hourPanelWidth)
            }
        }
    }

    private func heatmap(width: CGFloat) -> some View {
        let labelWidth: CGFloat = 18
        let weeks = max(8, Int((width - labelWidth - 8 + gap) / (cell + gap)))
        let cells = TodayOverviewModel.recentWeeks(
            daily: appState.snapshot.daily,
            goal: appState.settings.dailyGoalTokens,
            today: Date(),
            weeks: weeks,
            calendar: TokenStepClock.calendar
        )
        let columns = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        return HStack(alignment: .top, spacing: 8) {
            VStack(spacing: gap) {
                Text(" ").font(.system(size: 10)).frame(height: 13)
                ForEach(Array([L("一"), "", L("三"), "", L("五"), "", L("日")].enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: labelWidth - 8, height: cell)
                }
            }
            HStack(alignment: .top, spacing: gap) {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                    VStack(spacing: gap) {
                        Text(monthLabel(column: column, previous: index > 0 ? columns[index - 1] : nil))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .frame(width: cell, height: 13, alignment: .leading)
                        ForEach(column) { item in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(item.isFuture ? Color.clear : DashboardHeatColors.color(level: item.level))
                                .overlay {
                                    if item.isToday {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .stroke(Color.tokenInk, lineWidth: 1.2)
                                    }
                                }
                                .frame(width: cell, height: cell)
                                .help("\(item.date) · \(TokenStepFormat.tokens(item.tokens, compact: true))")
                        }
                    }
                }
            }
        }
    }

    /// The month's number above the first column that starts in it.
    private func monthLabel(column: [TodayOverviewModel.HeatCell], previous: [TodayOverviewModel.HeatCell]?) -> String {
        guard let first = column.first?.date, first.count >= 7 else { return "" }
        let month = String(first.dropFirst(5).prefix(2))
        guard let prior = previous?.first?.date, prior.count >= 7 else { return "" }
        guard String(prior.dropFirst(5).prefix(2)) != month, let number = Int(month) else { return "" }
        return LFormat("%d月", number)
    }

    private var footer: some View {
        let goal = appState.settings.dailyGoalTokens
        let daily = appState.snapshot.daily
        let peak = daily.map(\.totalTokens).max() ?? 0
        return HStack {
            Text(LFormat(
                "活跃 %d 天 · 达标 %d 天 · 单日最高 %@",
                appState.snapshot.totals.activeDays,
                daily.filter { $0.totalTokens >= goal }.count,
                TokenStepFormat.tokens(peak, compact: true)
            ))
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

    private func hourPanel(_ totals: [Int]) -> some View {
        let maxValue = max(totals.max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 10) {
            DashboardCardHeader(L("常用时段")) { Text(L("近 30 天")) }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { hour in
                    let ratio = Double(totals[hour]) / Double(maxValue)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(DashboardHeatColors.color(level: totals[hour] == 0 ? 0 : min(4, 1 + Int(ratio * 3.99))))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(4, 72 * ratio))
                        .help(String(format: "%02d:00 · %@", hour, TokenStepFormat.tokens(totals[hour], compact: true)))
                }
            }
            .frame(height: 72, alignment: .bottom)
            HStack {
                Text("00"); Spacer(); Text("12"); Spacer(); Text("23")
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            if let start = TodayOverviewModel.busiestSpan(totals) {
                Text(LFormat("最常在 %02d:00–%02d:00 用 Agent", start, start + 4))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.tokenInk.opacity(0.75))
            }
        }
    }
}

// MARK: - Trend and distribution

private struct HistoryTrendCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TokenCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(L("近 30 天"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.tokenInk)
                    Text(LFormat("日均 %@", TokenStepFormat.tokens(appState.monthAverage, compact: true)))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    TokenToolLegend(tools: uniqueToolNames(in: Array(appState.snapshot.daily.suffix(30))), showsGoalLine: true)
                }
                StackedActivityBarsView(rows: appState.snapshot.daily, goal: appState.settings.dailyGoalTokens)
                    .frame(height: 120)
            }
        }
    }
}

private struct HistoryDistributionCard: View {
    @EnvironmentObject private var appState: AppState
    @State private var byModel = false

    var body: some View {
        let rows = byModel ? modelRows : clientRows
        TokenCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L("累计分布"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.tokenInk)
                    Spacer()
                    // Drawn rather than a system Picker, which screenshots
                    // cannot render.
                    HStack(spacing: 2) {
                        segment(L("客户端"), selected: !byModel) { byModel = false }
                        segment(L("模型"), selected: byModel) { byModel = true }
                    }
                    .padding(2)
                    .background(Color.tokenTrack.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                if rows.isEmpty {
                    Text(L("等待下一次同步"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                } else {
                    GeometryReader { proxy in
                        HStack(spacing: 2) {
                            ForEach(rows) { row in
                                Rectangle()
                                    .fill(row.color)
                                    .frame(width: max(2, (proxy.size.width - CGFloat(rows.count - 1) * 2) * row.percent / 100))
                            }
                        }
                    }
                    .frame(height: 10)
                    .clipShape(Capsule())
                    ForEach(rows.prefix(5)) { row in
                        HStack(spacing: 10) {
                            Circle().fill(row.color).frame(width: 8, height: 8)
                            Text(row.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.tokenInk)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(TokenStepFormat.tokens(row.tokens, compact: true))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.tokenInk)
                                .monospacedDigit()
                            Text(TokenStepFormat.percent(row.percent))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                        .frame(height: 24)
                    }
                }
            }
        }
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.tokenInk : Color.tokenInk.opacity(0.6))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(selected ? Color.tokenSurface : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private struct Row: Identifiable {
        var id: String { name }
        var name: String
        var tokens: Int
        var percent: Double
        var color: Color
    }

    private var clientRows: [Row] {
        appState.snapshot.tools
            .filter { $0.tokens > 0 }
            .sorted { $0.tokens > $1.tokens }
            .map { Row(name: $0.tool, tokens: $0.tokens, percent: $0.percentValue, color: tokenToolColor($0.tool)) }
    }

    private var modelRows: [Row] {
        let palette = TokenStepThemeRuntime.palette
        let colors = [palette.activity4.color, palette.activity3.color, palette.activity2.color, palette.activity1.color, Color.tokenInk.opacity(0.3)]
        return appState.snapshot.models
            .filter { $0.tokens > 0 }
            .sorted { $0.tokens > $1.tokens }
            .prefix(5)
            .enumerated()
            .map { index, model in
                Row(name: model.model, tokens: model.tokens, percent: model.percentValue, color: colors[min(index, colors.count - 1)])
            }
    }
}

// MARK: - Daily detail

private struct HistoryDetailCard: View {
    @EnvironmentObject private var appState: AppState
    var historyLimit: Int?
    @State private var showsAll = false

    private let collapsedCount = 7

    var body: some View {
        let all = appState.visibleHistoryRows
        let rows: [DailyUsage] = {
            if let historyLimit { return Array(all.prefix(historyLimit)) }
            return showsAll ? all : Array(all.prefix(collapsedCount))
        }()
        TokenCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(L("每日明细"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.tokenInk)
                    Text(LFormat("%d 天", all.count))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if historyLimit == nil, !all.isEmpty {
                        Button(L("导出 CSV")) { exportCSV(all) }
                            .controlSize(.small)
                    }
                }
                .padding(.bottom, 10)

                columnHeader
                ForEach(rows) { row in
                    HistoryDetailRow(row: row, goal: appState.settings.dailyGoalTokens, isToday: row.date == appState.today.date)
                }

                if historyLimit == nil, all.count > collapsedCount {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { showsAll.toggle() }
                    } label: {
                        Text(showsAll ? L("收起") : LFormat("展开全部 %d 天", all.count))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.tokenGreenDark)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Text(L("日期")).frame(width: 120, alignment: .leading)
            Text("Token").frame(width: 120, alignment: .trailing)
            Text(L("估算金额")).frame(width: 110, alignment: .trailing)
            Text(L("主力客户端")).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 24)
            Text(L("达标")).frame(width: 90, alignment: .trailing)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.tokenHairline).frame(height: 1) }
    }

    private func exportCSV(_ rows: [DailyUsage]) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "TokenStep-history.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var lines = ["date,total_tokens,estimated_cost_usd,top_client"]
        for row in rows.reversed() {
            let top = row.tools.max { $0.value < $1.value }?.key ?? ""
            let client = top.contains(",") ? "\"\(top)\"" : top
            lines.append("\(row.date),\(row.totalTokens),\(String(format: "%.2f", row.cost)),\(client)")
        }
        do {
            try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            appState.lastError = error.localizedDescription
        }
    }
}

private struct HistoryDetailRow: View {
    var row: DailyUsage
    var goal: Int
    var isToday: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(isToday ? LFormat("%@ 今天", row.date) : row.date)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.tokenInk.opacity(0.72))
                .frame(width: 120, alignment: .leading)
            Text(TokenStepFormat.tokens(row.totalTokens, compact: true))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.tokenInk)
                .monospacedDigit()
                .frame(width: 120, alignment: .trailing)
            Text(TokenStepFormat.money(row.cost))
                .font(.system(size: 13))
                .foregroundStyle(Color.tokenInk.opacity(0.72))
                .monospacedDigit()
                .frame(width: 110, alignment: .trailing)
            HStack(spacing: 8) {
                Circle().fill(tokenToolColor(dominantTool)).frame(width: 8, height: 8)
                Text(dominantTool).lineLimit(1)
            }
            .font(.system(size: 13))
            .foregroundStyle(Color.tokenInk.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 24)
            Text(goalText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(row.totalTokens >= goal && goal > 0 ? Color.tokenGreenDark : Color.secondary)
                .monospacedDigit()
                .frame(width: 90, alignment: .trailing)
        }
        .frame(height: 38)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.tokenDivider).frame(height: 1) }
    }

    private var dominantTool: String {
        row.tools.max(by: { $0.value < $1.value })?.key ?? L("无")
    }

    private var goalText: String {
        guard goal > 0, row.totalTokens >= goal else { return L("未达标") }
        return LFormat("%d 圈", row.totalTokens / goal)
    }
}
