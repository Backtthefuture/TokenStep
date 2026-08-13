import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState

    private var hasNoData: Bool {
        appState.collectionFreshness.kind == .neverSucceeded
    }

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Spacer()
                // G-V1：主窗口与浮层共用同一套新鲜度术语。
                FreshnessBadge(
                    freshness: appState.collectionFreshness,
                    showsLastSucceeded: appState.collectionFreshness.needsAttention
                )
            }
            hero
            todayBreakdownStrip
            todayProjectsCard
            TodayAgentWorkCard()
            metricStrip
        }
    }

    /// G-B1：今日项目卡——"今天你的 token 走了这些路"。
    @ViewBuilder
    private var todayProjectsCard: some View {
        let projects = appState.today.projects ?? []
        if !projects.isEmpty {
            TokenCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(L("今日项目"))
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(Color.tokenInk)
                        Spacer()
                        Text(L("今天你的 token 走了这些路"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    let total = max(1, projects.reduce(0) { $0 + $1.tokens })
                    ForEach(projects.prefix(4)) { project in
                        HStack(spacing: 14) {
                            Text(TokenStepProject.displayName(project.name))
                                .font(.callout.weight(.heavy))
                                .foregroundStyle(Color.tokenInk)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(width: 250, alignment: .leading)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.tokenTrack.opacity(0.5))
                                    Capsule()
                                        .fill(Color.tokenGreen.opacity(0.85))
                                        .frame(width: max(4, proxy.size.width * CGFloat(project.tokens) / CGFloat(total)))
                                }
                            }
                            .frame(height: 8)
                            Text("\(TokenStepFormat.tokens(project.tokens, compact: true)) · \(TokenStepFormat.percent(Double(project.tokens) * 100 / Double(total)))")
                                .font(.callout.weight(.bold))
                                .monospacedDigit()
                                .frame(width: 150, alignment: .trailing)
                            Text(TokenStepProject.agentSummary(project.tools))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(minWidth: 160, alignment: .leading)
                        }
                    }
                    if projects.count > 4 {
                        Text(LFormat("还有 %d 个项目", projects.count - 4))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(L("只显示项目目录名；完整路径仅保存在本机。"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var hero: some View {
        let lap = appState.todayLap
        return TokenCard {
            HStack(alignment: .center, spacing: 34) {
                ZStack {
                    ProgressRingView(progress: lap.currentLapProgress, lineWidth: 20, color: lap.color)
                    VStack(spacing: 6) {
                        if hasNoData {
                            // 从未成功：显示"暂无数据"，不显示 0（G-V1）。
                            Text(L("暂无数据"))
                                .font(.title3.weight(.heavy))
                                .foregroundStyle(.secondary)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                        } else {
                            Text(TokenStepFormat.tokens(appState.today.totalTokens))
                                .font(.system(size: 42, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.tokenInk)
                                .minimumScaleFactor(0.42)
                                .lineLimit(1)
                        }
                        Text(LFormat("/ %@ 每圈", TokenStepFormat.tokens(appState.settings.dailyGoalTokens, compact: true)))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 160)
                }
                .frame(width: 204, height: 204)

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lap.lapStatusText)
                            .font(.system(size: 35, weight: .heavy, design: .rounded))
                            .foregroundStyle(lap.color)
                            .monospacedDigit()
                        Text(lap.completedTokensText)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(lap.perLapGoalText)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("圈数进度"))
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(Color.tokenInk)
                        LapProgressChips(lap: lap)
                    }

                    HStack(spacing: 10) {
                        MetricPill(
                            label: L("消耗金额（估算）"),
                            value: hasNoData ? "—" : TokenStepFormat.money(appState.today.cost)
                        )
                        .help(L("按 API 列表价估算，不代表订阅或实际账单。"))
                        MetricPill(label: L("本月均值"), value: TokenStepFormat.tokens(appState.monthAverage, compact: true))
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var metricStrip: some View {
        HStack(spacing: 18) {
            CompactMetricCard(label: L("累计 Token 消耗"), value: TokenStepFormat.tokens(appState.snapshot.totals.tokens), detail: L("所有本机记录"))
            CompactMetricCard(label: L("活跃天数"), value: localizedDays(appState.snapshot.totals.activeDays), detail: L("有 AI 使用的日期"))
            CompactMetricCard(label: L("达标天数"), value: localizedDays(appState.goalDays), detail: L("达到每日目标"))
        }
    }

    private var todayBreakdownStrip: some View {
        HStack(alignment: .top, spacing: 22) {
            TodayBreakdownCard(title: L("今日客户端"), rows: todayToolRows, maxRows: 3)
            TodayBreakdownCard(title: L("今日模型"), rows: todayModelRows, maxRows: 4)
        }
    }

    private func localizedDays(_ count: Int) -> String {
        TokenStepLocalization.language == .en ? "\(count)d" : "\(count) 天"
    }

    private var todayToolRows: [TodayBreakdownRow] {
        let total = appState.today.totalTokens
        guard total > 0 else { return [] }
        // 主力工具仅在有数据时置顶；0 token 的行不显示，避免挤掉更大的来源。
        let primaryTools = ["Codex", "Claude Code"].filter { (appState.today.tools[$0] ?? 0) > 0 }
        let primaryRows = primaryTools.map { name in
            TodayBreakdownRow(
                name: name,
                tokens: appState.today.tools[name] ?? 0,
                percent: Double(appState.today.tools[name] ?? 0) * 100 / Double(total),
                color: tokenToolColor(name)
            )
        }
        let extraRows = appState.today.tools
            .filter { !primaryTools.contains($0.key) && $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { name, tokens in
                TodayBreakdownRow(
                    name: name,
                    tokens: tokens,
                    percent: Double(tokens) * 100 / Double(total),
                    color: tokenToolColor(name)
                )
            }
        return hideNegligibleRows(primaryRows + extraRows)
    }

    private var todayModelRows: [TodayBreakdownRow] {
        hideNegligibleRows(breakdownRows(from: appState.today.models) { _ in nil })
    }

    /// 展示占比不足 0.1%（渲染为 0%，看着像没数据）的行隐藏；保底保留前两名。
    private func hideNegligibleRows(_ rows: [TodayBreakdownRow]) -> [TodayBreakdownRow] {
        guard rows.count > 2 else { return rows }
        return rows.enumerated()
            .filter { index, row in
                index < 2 || row.percent >= 0.1
            }
            .map(\.element)
    }

    private func breakdownRows(from values: [String: Int], color: (String) -> Color?) -> [TodayBreakdownRow] {
        let total = appState.today.totalTokens
        guard total > 0 else { return [] }
        return values
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { name, tokens in
                TodayBreakdownRow(
                    name: name,
                    tokens: tokens,
                    percent: Double(tokens) * 100 / Double(total),
                    color: color(name)
                )
            }
    }
}

private struct CompactMetricCard: View {
    var label: String
    var value: String
    var detail: String

    var body: some View {
        TokenCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.tokenInk)
                    .minimumScaleFactor(0.66)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LapProgressChips: View {
    var lap: TokenStepLapProgress

    private var visibleCompletedLaps: [Int] {
        let completed = max(0, lap.completedLaps)
        guard completed > 0 else { return [] }
        if completed <= 2 { return Array(1...completed) }
        return Array(max(1, completed - 1)...completed)
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(visibleCompletedLaps, id: \.self) { item in
                LapChip(title: LFormat("%d圈完成", item), detail: TokenStepFormat.tokens(item * lap.safeGoal, compact: true), active: false, color: .tokenGreen)
            }
            LapChip(title: LFormat("%@进行中", lap.lapTitle), detail: lap.lapPercentText, active: true, color: lap.color)
        }
    }
}

private struct LapChip: View {
    var title: String
    var detail: String
    var active: Bool
    var color: Color

    var body: some View {
        VStack(spacing: 4) {
            Label(title, systemImage: active ? "arrow.clockwise.circle.fill" : "checkmark.circle.fill")
                .font(.caption.weight(.heavy))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
            Text(detail)
                .font(.caption.weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(active ? color : Color.tokenInk.opacity(0.68))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(active ? color.opacity(0.12) : Color.tokenTrack.opacity(0.46), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(active ? color.opacity(0.36) : Color.black.opacity(0.045)))
    }
}
