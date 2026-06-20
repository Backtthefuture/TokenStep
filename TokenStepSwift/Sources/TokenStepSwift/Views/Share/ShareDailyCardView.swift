import SwiftUI

enum ShareCardMode: Equatable {
    case today
    case yesterday

    var filePrefix: String {
        switch self {
        case .today: return "today-card"
        case .yesterday: return "yesterday-card"
        }
    }

    var title: String {
        switch self {
        case .today: return L("今日 AI 战绩")
        case .yesterday: return L("昨日 AI 工作成绩单")
        }
    }

    var subtitle: String {
        switch self {
        case .today: return L("今天我和 AI 一起消耗了")
        case .yesterday: return L("昨天我和 AI 一起完成了")
        }
    }
}

struct ShareDailyCardView: View {
    @EnvironmentObject private var appState: AppState
    var mode: ShareCardMode
    var day: DailyUsage
    var previousDay: DailyUsage?

    private var lap: TokenStepLapProgress {
        TokenStepLapProgress(tokens: day.totalTokens, goal: appState.settings.dailyGoalTokens)
    }

    var body: some View {
        ZStack {
            TokenStepBackdrop()

            VStack(alignment: .leading, spacing: 24) {
                header

                if mode == .today {
                    todayMedalHero
                } else {
                    yesterdayReportHero
                }

                HStack(spacing: 16) {
                    ShareMetricTile(title: L("已完成"), value: lap.completedLapsText, detail: lap.perLapGoalText, symbol: "checkmark.circle.fill")
                    ShareMetricTile(title: L("消耗金额"), value: TokenStepFormat.money(day.cost), detail: L("仅供参考"), symbol: "dollarsign.circle.fill")
                    ShareMetricTile(title: L("主力工具"), value: dominantTool, detail: dominantModel, symbol: "sparkles")
                }

                ShareBreakdownPanel(
                    title: L(mode == .today ? "今日来源" : "昨日来源"),
                    subtitle: L("颜色代表客户端"),
                    rows: toolRows
                )

                HStack(alignment: .top, spacing: 16) {
                    ShareBreakdownPanel(
                        title: L("主力模型"),
                        subtitle: L("按 Token 消耗排序"),
                        rows: modelRows,
                        compact: true
                    )
                    ShareTrendPanel(day: day, rows: appState.snapshot.daily, goal: appState.settings.dailyGoalTokens)
                }

                footer
            }
            .padding(42)
        }
        .frame(width: 840, height: 1120)
        .fixedSize()
        .id(appState.appearanceID)
    }

    private var header: some View {
        HStack(spacing: 14) {
            TokenStepMark(size: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text("TokenStep")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.tokenInk)
                Text(L("每日 Token 消耗追踪"))
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(mode.title)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Color.tokenInk)
                Text(day.date)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var todayMedalHero: some View {
        TokenCard {
            HStack(alignment: .center, spacing: 30) {
                ZStack {
                    Circle()
                        .fill(lap.color.opacity(0.08))
                        .frame(width: 285, height: 285)
                        .blur(radius: 10)
                    ProgressRingView(progress: lap.currentLapProgress, lineWidth: 26, color: lap.color)
                        .frame(width: 264, height: 264)
                    VStack(spacing: 9) {
                        Text(dayNumber)
                            .font(.system(size: 72, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.tokenInk)
                            .minimumScaleFactor(0.45)
                            .lineLimit(1)
                        Text(LFormat("/ %@ 每圈", TokenStepFormat.tokens(appState.settings.dailyGoalTokens, compact: true)))
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 220)
                }
                .frame(width: 290, height: 290)

                VStack(alignment: .leading, spacing: 16) {
                    Text(mode.subtitle)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(.secondary)
                    Text(dayNumber)
                        .font(.system(size: 78, weight: .black, design: .rounded))
                        .foregroundStyle(lap.color)
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                    Text("Token")
                        .font(.title.weight(.heavy))
                        .foregroundStyle(Color.tokenInk.opacity(0.72))
                    Text(lap.lapStatusText)
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(lap.color)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(lap.color.opacity(0.12), in: Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var yesterdayReportHero: some View {
        TokenCard {
            HStack(alignment: .center, spacing: 30) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(mode.subtitle)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(.secondary)
                    Text(dayNumber)
                        .font(.system(size: 92, weight: .black, design: .rounded))
                        .foregroundStyle(Color.tokenInk)
                        .minimumScaleFactor(0.52)
                        .lineLimit(1)
                    Text(lap.lapStatusText)
                        .font(.title.weight(.heavy))
                        .foregroundStyle(lap.color)
                    Text(comparisonText)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    ProgressRingView(progress: lap.currentLapProgress, lineWidth: 22, color: lap.color)
                        .frame(width: 200, height: 200)
                    VStack(spacing: 6) {
                        Text(lap.lapPercentText)
                            .font(.system(size: 42, weight: .heavy, design: .rounded))
                            .foregroundStyle(lap.color)
                        Text(L("完成度"))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 230, height: 230)
            }
        }
    }

    private var footer: some View {
        HStack {
            Label(L("本地统计"), systemImage: "shield.checkered")
            Text("·")
            Text(L("不上传代码或对话"))
            Spacer()
            Text("tokenstep.app")
        }
        .font(.callout.weight(.bold))
        .foregroundStyle(.secondary)
    }

    private var dayNumber: String {
        TokenStepFormat.tokens(day.totalTokens)
    }

    private var dominantTool: String {
        orderedToolEntries(day.tools).first?.name ?? L("无")
    }

    private var dominantModel: String {
        day.models.sorted { $0.value > $1.value }.first?.key ?? L("无")
    }

    private var comparisonText: String {
        guard let previousDay, previousDay.totalTokens > 0 else {
            return L("这是一个新的记录日")
        }
        let delta = Double(day.totalTokens - previousDay.totalTokens) / Double(previousDay.totalTokens) * 100
        if abs(delta) < 1 {
            return L("和前一天基本持平")
        }
        if delta > 0 {
            return LFormat("比前一天多 %@", TokenStepFormat.percent(delta))
        }
        return LFormat("比前一天少 %@", TokenStepFormat.percent(abs(delta)))
    }

    private var toolRows: [ShareBreakdownRow] {
        breakdownRows(from: day.tools, color: tokenToolColor)
    }

    private var modelRows: [ShareBreakdownRow] {
        breakdownRows(from: day.models) { _ in .tokenGreen }
    }

    private func breakdownRows(from values: [String: Int], color: (String) -> Color) -> [ShareBreakdownRow] {
        let total = max(day.totalTokens, 1)
        return values
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(4)
            .map { name, tokens in
                ShareBreakdownRow(
                    name: name,
                    value: TokenStepFormat.tokens(tokens, compact: true),
                    percent: Double(tokens) * 100 / Double(total),
                    color: color(name)
                )
            }
    }
}

private struct ShareMetricTile: View {
    var title: String
    var value: String
    var detail: String
    var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title3.weight(.heavy))
                .foregroundStyle(Color.tokenGreen)
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.heavy))
                .foregroundStyle(Color.tokenInk)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(detail)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.tokenSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.black.opacity(0.055)))
    }
}

private struct ShareBreakdownRow: Identifiable {
    var id: String { name }
    var name: String
    var value: String
    var percent: Double
    var color: Color
}

private struct ShareBreakdownPanel: View {
    var title: String
    var subtitle: String
    var rows: [ShareBreakdownRow]
    var compact = false

    var body: some View {
        TokenCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(Color.tokenInk)
                        Text(subtitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                VStack(spacing: compact ? 9 : 12) {
                    ForEach(rows) { row in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(row.color)
                                .frame(width: 8, height: 8)
                            Text(row.name)
                                .font(.callout.weight(.bold))
                                .foregroundStyle(Color.tokenInk.opacity(0.76))
                                .lineLimit(1)
                                .frame(width: compact ? 118 : 152, alignment: .leading)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.tokenTrack)
                                    Capsule()
                                        .fill(row.color)
                                        .frame(width: max(5, proxy.size.width * min(max(row.percent, 0), 100) / 100))
                                }
                            }
                            .frame(height: 8)
                            Text(row.value)
                                .font(.callout.weight(.heavy))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .monospacedDigit()
                                .frame(width: compact ? 72 : 84, alignment: .trailing)
                        }
                        .frame(height: compact ? 22 : 26)
                    }
                }
                .frame(minHeight: compact ? 104 : 118, alignment: .top)
            }
        }
    }
}

private struct ShareTrendPanel: View {
    var day: DailyUsage
    var rows: [DailyUsage]
    var goal: Int

    var body: some View {
        TokenCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("最近 30 天"))
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(Color.tokenInk)
                        Text(L("柱越高，用量越多"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(TokenStepFormat.tokens(day.totalTokens, compact: true))
                        .font(.callout.weight(.heavy))
                        .foregroundStyle(Color.tokenGreenDark)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.tokenMint.opacity(0.24), in: Capsule())
                }

                StackedActivityBarsView(rows: rows, goal: goal)
                    .frame(height: 100)
            }
        }
    }
}
