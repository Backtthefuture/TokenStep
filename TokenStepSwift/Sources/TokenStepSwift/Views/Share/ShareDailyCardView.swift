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

            VStack(alignment: .leading, spacing: 14) {
                header
                shareHero
                ShareBreakdownPanel(
                    title: L(mode == .today ? "今日来源" : "昨日来源"),
                    subtitle: L("颜色代表客户端"),
                    rows: toolRows,
                    compact: true
                )
                ShareBreakdownPanel(
                    title: L("主力模型"),
                    subtitle: L("按 Token 消耗排序"),
                    rows: modelRows,
                    compact: true
                )
                ShareTrendPanel(day: day, rows: appState.snapshot.daily, goal: appState.settings.dailyGoalTokens)

                footer
            }
            .padding(28)
        }
        .frame(width: 600, height: 840)
        .fixedSize()
        .id(appState.appearanceID)
    }

    private var header: some View {
        HStack(spacing: 12) {
            TokenStepMark(size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("TokenStep")
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.tokenInk)
                Text(L("每日 Token 消耗追踪"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(mode.title)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Color.tokenInk)
                Text(day.date)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var shareHero: some View {
        ShareCardSurface(padding: 20, cornerRadius: 26) {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    Circle()
                        .fill(lap.color.opacity(0.09))
                        .frame(width: 228, height: 228)
                        .blur(radius: 10)
                    ProgressRingView(progress: lap.currentLapProgress, lineWidth: 20, color: lap.color)
                        .frame(width: 212, height: 212)
                    VStack(spacing: 7) {
                        Text(dayNumber)
                            .font(.system(size: 64, weight: .black, design: .rounded))
                            .foregroundStyle(Color.tokenInk)
                            .minimumScaleFactor(0.42)
                            .lineLimit(1)
                        Text(LFormat("/ %@ 每圈", TokenStepFormat.tokens(appState.settings.dailyGoalTokens, compact: true)))
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 182)
                }
                .frame(width: 224, height: 224)

                VStack(alignment: .leading, spacing: 10) {
                    Text(mode.subtitle)
                        .font(.callout.weight(.heavy))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(totalCompletionText)
                            .font(.system(size: 58, weight: .black, design: .rounded))
                            .foregroundStyle(lap.color)
                            .lineLimit(1)
                        Text(L("总完成度"))
                            .font(.callout.weight(.heavy))
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(lap.completedLapsText)
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(Color.tokenInk.opacity(0.78))
                        Text(lap.perLapGoalText)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(mode == .yesterday ? comparisonText : L("今日 Token"))
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 232)
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
        .font(.caption.weight(.bold))
        .foregroundStyle(.secondary)
    }

    private var dayNumber: String {
        TokenStepFormat.tokens(day.totalTokens)
    }

    private var totalCompletionText: String {
        TokenStepFormat.percent(lap.rawProgress * 100)
    }

    private var dominantTool: String {
        orderedToolEntries(day.tools).first?.name ?? L("无")
    }

    private var dominantModel: String {
        day.models.sorted { $0.value > $1.value }.first?.key ?? L("无")
    }

    private var dominantToolTokens: Int {
        orderedToolEntries(day.tools).first?.tokens ?? 0
    }

    private var dominantModelTokens: Int {
        day.models.sorted { $0.value > $1.value }.first?.value ?? 0
    }

    private var heroRows: [ShareHeroRow] {
        [
            ShareHeroRow(
                title: L("主力工具"),
                name: dominantTool,
                value: dominantToolTokens > 0 ? TokenStepFormat.tokens(dominantToolTokens, compact: true) : "0"
            ),
            ShareHeroRow(
                title: L("主力模型"),
                name: dominantModel,
                value: dominantModelTokens > 0 ? TokenStepFormat.tokens(dominantModelTokens, compact: true) : "0"
            ),
            ShareHeroRow(
                title: L("消耗金额"),
                name: TokenStepFormat.money(day.cost),
                value: L("仅供参考")
            )
        ]
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
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.callout.weight(.heavy))
                .foregroundStyle(Color.tokenGreen)
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.heavy))
                .foregroundStyle(Color.tokenInk)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(detail)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .frame(height: 96, alignment: .topLeading)
        .background(Color.tokenSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.black.opacity(0.055)))
    }
}

private struct ShareBreakdownRow: Identifiable {
    var id: String { name }
    var name: String
    var value: String
    var percent: Double
    var color: Color
}

private struct ShareHeroRow {
    var title: String
    var name: String
    var value: String
}

private struct ShareHeroRankRow: View {
    var index: Int
    var row: ShareHeroRow

    var body: some View {
        HStack(spacing: 9) {
            Text("\(index)")
                .font(.caption2.weight(.black))
                .foregroundStyle(Color.tokenGreenDark)
                .frame(width: 22, height: 22)
                .background(Color.tokenMint.opacity(0.35), in: Circle())
            HStack(spacing: 3) {
                Text(row.title)
                    .foregroundStyle(.secondary)
                Text(row.name)
                    .foregroundStyle(Color.tokenInk)
            }
            .font(.caption.weight(.heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            Text(row.value)
                .font(.caption.weight(.heavy))
                .foregroundStyle(row.value == L("仅供参考") ? .secondary : Color.tokenInk)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Color.tokenSurface.opacity(0.72), in: Capsule())
        .overlay(Capsule().stroke(Color.black.opacity(0.045)))
    }
}

private struct ShareBreakdownPanel: View {
    var title: String
    var subtitle: String
    var rows: [ShareBreakdownRow]
    var compact = false

    var body: some View {
        ShareCardSurface(padding: compact ? 16 : 18, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline.weight(.heavy))
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
                                .frame(width: 7, height: 7)
                            Text(row.name)
                                .font((compact ? Font.subheadline : Font.caption).weight(.bold))
                                .foregroundStyle(Color.tokenInk.opacity(0.76))
                                .lineLimit(1)
                                .frame(width: compact ? 104 : 102, alignment: .leading)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.tokenTrack)
                                    Capsule()
                                        .fill(row.color)
                                        .frame(width: max(5, proxy.size.width * min(max(row.percent, 0), 100) / 100))
                                }
                            }
                            .frame(height: 7)
                            Text(row.value)
                                .font((compact ? Font.subheadline : Font.caption).weight(.heavy))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .monospacedDigit()
                                .frame(width: compact ? 72 : 70, alignment: .trailing)
                        }
                        .frame(height: compact ? 25 : 23)
                    }
                }
                .frame(
                    minHeight: max(compact ? 25 : 52, CGFloat(rows.count) * (compact ? 25 : 23)),
                    alignment: .top
                )
            }
        }
    }
}

private struct ShareTrendPanel: View {
    var day: DailyUsage
    var rows: [DailyUsage]
    var goal: Int

    var body: some View {
        ShareCardSurface(padding: 16, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("最近 30 天"))
                            .font(.headline.weight(.heavy))
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
                    .frame(height: 84)
            }
        }
    }
}

private struct ShareCardSurface<Content: View>: View {
    var padding: CGFloat = 18
    var cornerRadius: CGFloat = 22
    var content: Content

    init(padding: CGFloat = 18, cornerRadius: CGFloat = 22, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(Color.tokenSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(Color.black.opacity(0.055)))
            .shadow(color: Color.black.opacity(0.045), radius: 18, x: 0, y: 10)
    }
}
