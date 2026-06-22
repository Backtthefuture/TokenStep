import SwiftUI

struct ShareRhythmCardView: View {
    @EnvironmentObject private var appState: AppState
    var day: DailyUsage
    var rhythm: DailyRhythm
    var previousDay: DailyUsage?

    private var palette: RhythmCardPalette {
        RhythmCardPalette.palette(for: rhythm)
    }

    var body: some View {
        ZStack {
            RhythmCardBackdrop(palette: palette)

            VStack(alignment: .leading, spacing: 22) {
                header
                hero
                RhythmWaveformPanel(rhythm: rhythm, palette: palette)
                metrics
                pairingPanel
                footer
            }
            .padding(30)
        }
        .frame(width: 600, height: 840)
        .fixedSize()
        .id(appState.appearanceID)
    }

    private var header: some View {
        HStack(spacing: 13) {
            TokenStepMark(size: 42)
                .padding(5)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.white.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text("TokenStep")
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(L("本地 AI 使用节奏"))
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.white.opacity(0.58))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(L("昨日 AI 节奏"))
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                Text(day.date)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.56))
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(rhythm.primaryTag.title)
                        .font(.system(size: 54, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [palette.accent, palette.secondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .shadow(color: palette.accent.opacity(0.32), radius: 18, x: 0, y: 7)
                    Text(rhythm.primaryTag.shareLine)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(2)
                }
                Spacer(minLength: 16)
                RhythmBadge(text: L("完整 24h"), palette: palette)
            }

            Text(comparisonText)
                .font(.callout.weight(.heavy))
                .foregroundStyle(Color.white.opacity(0.54))
                .lineLimit(1)
        }
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            RhythmMetricTile(title: L("峰值"), value: rhythm.peakHourText, detail: TokenStepFormat.tokens(rhythm.peakTokens, compact: true), palette: palette)
            RhythmMetricTile(title: L("活跃时段"), value: LFormat("%d 个时段", rhythm.activeHours), detail: rhythm.activeRangeText, palette: palette)
            RhythmMetricTile(title: L("昨日 Token"), value: TokenStepFormat.tokens(day.totalTokens, compact: true), detail: L("全天总量"), palette: palette)
        }
    }

    private var pairingPanel: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(palette.accent.opacity(0.16))
                    .frame(width: 70, height: 70)
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(
                        LinearGradient(colors: [palette.secondary, palette.accent], startPoint: .top, endPoint: .bottom)
                    )
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(rhythm.primaryTag.companionLine)
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(pairingDetail)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.11)))
    }

    private var footer: some View {
        HStack {
            Label(L("本地统计"), systemImage: "shield.checkered")
            Text("·")
            Text(L("不上传代码或对话"))
            Spacer()
            Text("tokenstep.app")
        }
        .font(.caption.weight(.heavy))
        .foregroundStyle(Color.white.opacity(0.48))
    }

    private var comparisonText: String {
        guard let previousDay, previousDay.totalTokens > 0 else {
            return L("昨天的完整 AI 协作节拍")
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

    private var pairingDetail: String {
        switch rhythm.primaryTag {
        case .earlyStarter:
            return L("你负责清晨开局，TA 负责夜里收尾。")
        case .morningPlanner:
            return L("你负责上午定盘，TA 负责下午冲刺。")
        case .afternoonBurst:
            return L("你负责午后爆发，TA 负责上午定盘。")
        case .nightAgent:
            return L("你负责深夜推进，TA 负责清晨接棒。")
        case .doublePeak:
            return L("你负责两次拉满，TA 负责稳定托底。")
        case .fragmented:
            return L("你负责随手推进，TA 负责集中攻坚。")
        case .oneShot:
            return L("你负责一波攻坚，TA 负责穿插补位。")
        case .steadyCruise:
            return L("你负责稳定巡航，TA 负责制造峰值。")
        case .quietDay:
            return L("你负责保持手感，TA 负责拉开节奏。")
        }
    }
}

private struct RhythmWaveformPanel: View {
    var rhythm: DailyRhythm
    var palette: RhythmCardPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("24 小时波形"))
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                    Text(L("颜色随时段变化，最高柱是峰值"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.50))
                }
                Spacer()
                RhythmBadge(text: LFormat("峰值 %@", rhythm.peakHourText), palette: palette)
            }

            ZStack(alignment: .bottom) {
                RhythmGridShape(columns: 12, rows: 4)
                    .stroke(Color.white.opacity(0.055), lineWidth: 1)

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(rhythm.buckets) { bucket in
                        RhythmHourBar(
                            bucket: bucket,
                            maxTokens: rhythm.maxBucketTokens,
                            isPeak: bucket.hour == rhythm.peakHour,
                            palette: palette
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            }
            .frame(height: 220)

            HStack {
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    Text(String(format: "%02d", hour))
                        .font(.caption2.weight(.black))
                        .foregroundStyle(Color.white.opacity(0.38))
                    if hour != 24 {
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(20)
        .background(Color.black.opacity(0.23), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.12)))
        .shadow(color: palette.accent.opacity(0.18), radius: 30, x: 0, y: 16)
    }
}

private struct RhythmHourBar: View {
    var bucket: HourlyTokenBucket
    var maxTokens: Int
    var isPeak: Bool
    var palette: RhythmCardPalette

    private var normalized: Double {
        guard maxTokens > 0 else { return 0 }
        return min(max(Double(bucket.tokens) / Double(maxTokens), 0), 1)
    }

    private var height: CGFloat {
        if bucket.tokens <= 0 { return 8 }
        return 16 + CGFloat(pow(normalized, 0.72)) * 170
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(
                LinearGradient(
                    colors: palette.barColors(for: bucket.hour, isPeak: isPeak),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .opacity(bucket.tokens > 0 ? 1 : 0.28)
            .shadow(color: isPeak ? palette.secondary.opacity(0.72) : palette.accent.opacity(0.20), radius: isPeak ? 18 : 5, x: 0, y: isPeak ? 0 : 4)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(isPeak ? 0.36 : 0.07), lineWidth: 1)
            )
    }
}

private struct RhythmMetricTile: View {
    var title: String
    var value: String
    var detail: String
    var palette: RhythmCardPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(Color.white.opacity(0.48))
            Text(value)
                .font(.system(size: 25, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
            Text(detail)
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.secondary.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .frame(height: 112)
        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.10)))
    }
}

private struct RhythmBadge: View {
    var text: String
    var palette: RhythmCardPalette

    var body: some View {
        Text(text)
            .font(.caption.weight(.black))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                LinearGradient(colors: [palette.accent.opacity(0.38), palette.secondary.opacity(0.28)], startPoint: .leading, endPoint: .trailing),
                in: Capsule()
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.14)))
    }
}

private struct RhythmCardBackdrop: View {
    var palette: RhythmCardPalette

    var body: some View {
        ZStack {
            LinearGradient(
                colors: palette.background,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [palette.accent.opacity(0.32), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 430
            )
            RadialGradient(
                colors: [palette.secondary.opacity(0.25), .clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 460
            )
            RhythmGridShape(columns: 8, rows: 12)
                .stroke(Color.white.opacity(0.035), lineWidth: 1)
        }
        .ignoresSafeArea()
    }
}

private struct RhythmGridShape: Shape {
    var columns: Int
    var rows: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard columns > 0, rows > 0 else { return path }
        for index in 1..<columns {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(columns)
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        for index in 1..<rows {
            let y = rect.minY + rect.height * CGFloat(index) / CGFloat(rows)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

private struct RhythmCardPalette {
    var background: [Color]
    var accent: Color
    var secondary: Color
    var night: Color
    var morning: Color

    static func palette(for rhythm: DailyRhythm) -> RhythmCardPalette {
        switch rhythm.primaryTag {
        case .nightAgent:
            return RhythmCardPalette(
                background: [
                    Color(red: 4 / 255, green: 7 / 255, blue: 18 / 255),
                    Color(red: 9 / 255, green: 14 / 255, blue: 36 / 255),
                    Color(red: 16 / 255, green: 9 / 255, blue: 42 / 255)
                ],
                accent: Color(red: 41 / 255, green: 218 / 255, blue: 255 / 255),
                secondary: Color(red: 145 / 255, green: 92 / 255, blue: 255 / 255),
                night: Color(red: 93 / 255, green: 126 / 255, blue: 255 / 255),
                morning: Color(red: 96 / 255, green: 239 / 255, blue: 189 / 255)
            )
        case .morningPlanner, .earlyStarter:
            return RhythmCardPalette(
                background: [
                    Color(red: 7 / 255, green: 24 / 255, blue: 22 / 255),
                    Color(red: 9 / 255, green: 40 / 255, blue: 35 / 255),
                    Color(red: 54 / 255, green: 40 / 255, blue: 12 / 255)
                ],
                accent: Color(red: 75 / 255, green: 232 / 255, blue: 159 / 255),
                secondary: Color(red: 255 / 255, green: 207 / 255, blue: 87 / 255),
                night: Color(red: 75 / 255, green: 156 / 255, blue: 232 / 255),
                morning: Color(red: 255 / 255, green: 219 / 255, blue: 123 / 255)
            )
        case .fragmented, .doublePeak:
            return RhythmCardPalette(
                background: [
                    Color(red: 8 / 255, green: 9 / 255, blue: 17 / 255),
                    Color(red: 20 / 255, green: 16 / 255, blue: 40 / 255),
                    Color(red: 4 / 255, green: 34 / 255, blue: 35 / 255)
                ],
                accent: Color(red: 80 / 255, green: 238 / 255, blue: 167 / 255),
                secondary: Color(red: 255 / 255, green: 88 / 255, blue: 164 / 255),
                night: Color(red: 83 / 255, green: 172 / 255, blue: 255 / 255),
                morning: Color(red: 255 / 255, green: 202 / 255, blue: 94 / 255)
            )
        default:
            return RhythmCardPalette(
                background: [
                    Color(red: 2 / 255, green: 12 / 255, blue: 9 / 255),
                    Color(red: 4 / 255, green: 23 / 255, blue: 18 / 255),
                    Color(red: 2 / 255, green: 16 / 255, blue: 29 / 255)
                ],
                accent: Color(red: 63 / 255, green: 238 / 255, blue: 143 / 255),
                secondary: Color(red: 52 / 255, green: 198 / 255, blue: 255 / 255),
                night: Color(red: 87 / 255, green: 128 / 255, blue: 255 / 255),
                morning: Color(red: 255 / 255, green: 213 / 255, blue: 105 / 255)
            )
        }
    }

    func barColors(for hour: Int, isPeak: Bool) -> [Color] {
        if isPeak {
            return [Color.white, secondary, accent]
        }
        if hour <= 2 || hour >= 21 {
            return [night, secondary.opacity(0.62)]
        }
        if (5...11).contains(hour) {
            return [morning, accent.opacity(0.78)]
        }
        if (14...18).contains(hour) {
            return [accent, secondary.opacity(0.80)]
        }
        return [accent.opacity(0.78), accent.opacity(0.34)]
    }
}
