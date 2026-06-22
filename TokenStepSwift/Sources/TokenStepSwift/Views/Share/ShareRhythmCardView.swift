import SwiftUI

struct ShareRhythmCardView: View {
    var day: DailyUsage
    var rhythm: DailyRhythm
    var previousDay: DailyUsage?

    private var palette: RhythmCardPalette {
        RhythmCardPalette.palette(for: rhythm)
    }

    var body: some View {
        ZStack {
            RhythmCardBackdrop(palette: palette)

            VStack(spacing: 14) {
                header
                hero
                RhythmNeonWavePanel(rhythm: rhythm, palette: palette)
                peakCapsule
                tokenConsole
                bottomMetrics
                footer
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 600, height: 840)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .fixedSize()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 13) {
            TokenStepMark(size: 50)
                .shadow(color: palette.accent.opacity(0.22), radius: 12, x: 0, y: 0)

            VStack(alignment: .leading, spacing: 3) {
                Text("TokenStep")
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(L("AI Token 使用追踪"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text(displayDate)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(palette.accent)
                Text(weekdayText)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.56))
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 8) {
            Text(L("昨日 AI 节奏"))
                .font(.system(size: 31, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(alignment: .center, spacing: 12) {
                LaurelBranch(mirrored: false)
                    .stroke(palette.accent.opacity(0.78), lineWidth: 2)
                    .frame(width: 38, height: 56)
                Text(rhythm.primaryTag.title)
                    .font(.system(size: 43, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [palette.accent, palette.secondary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .shadow(color: palette.accent.opacity(0.34), radius: 16, x: 0, y: 4)
                LaurelBranch(mirrored: true)
                    .stroke(palette.accent.opacity(0.78), lineWidth: 2)
                    .frame(width: 38, height: 56)
            }

            Text(rhythm.primaryTag.shareLine)
                .font(.callout.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity)
    }

    private var peakCapsule: some View {
        HStack(spacing: 13) {
            Image(systemName: "scope")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(palette.accent)
                .frame(width: 36, height: 36)
                .background(palette.accent.opacity(0.12), in: Circle())
            Text(LFormat("峰值 %@", peakWindowText))
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Text(LFormat("峰值 %@", TokenStepFormat.tokens(rhythm.peakTokens, compact: true)))
                .font(.callout.weight(.heavy))
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(
            LinearGradient(
                colors: [palette.panel.opacity(0.96), palette.panel.opacity(0.62)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.secondary.opacity(0.35)))
        .shadow(color: palette.secondary.opacity(0.16), radius: 18, x: 0, y: 10)
    }

    private var tokenConsole: some View {
        HStack(spacing: 14) {
            RhythmChevronCluster(mirrored: false, palette: palette)
                .frame(width: 86)
            VStack(spacing: 3) {
                Text(L("昨日 Token"))
                    .font(.headline.weight(.black))
                    .foregroundStyle(Color.white.opacity(0.70))
                Text(TokenStepFormat.tokens(day.totalTokens, compact: true))
                    .font(.system(size: 49, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [palette.accent, Color.white], startPoint: .top, endPoint: .bottom)
                    )
                    .minimumScaleFactor(0.62)
                    .lineLimit(1)
                    .shadow(color: palette.accent.opacity(0.30), radius: 16, x: 0, y: 4)
            }
            .frame(maxWidth: .infinity)
            RhythmChevronCluster(mirrored: true, palette: palette)
                .frame(width: 86)
        }
        .padding(.horizontal, 20)
        .frame(height: 90)
        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(palette.secondary.opacity(0.24)))
    }

    private var bottomMetrics: some View {
        HStack(spacing: 0) {
            RhythmBottomMetric(symbol: "clock.fill", title: L("活跃时段"), value: LFormat("%d 个时段", rhythm.activeHours), color: palette.accent)
            RhythmMetricDivider()
            RhythmBottomMetric(symbol: "moon.stars.fill", title: L("夜间占比"), value: TokenStepFormat.percent(nightShare * 100), color: palette.night)
            RhythmMetricDivider()
            RhythmBottomMetric(symbol: "timer", title: L("最长连续"), value: LFormat("%d 小时", longestActiveStreak), color: palette.accent)
        }
        .frame(height: 70)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
            Text(L("本地统计"))
            Text("·")
            Text(L("不上传对话"))
        }
        .font(.caption.weight(.heavy))
        .foregroundStyle(Color.white.opacity(0.54))
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(Color.black.opacity(0.20), in: Capsule())
    }

    private var displayDate: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd"
        guard let date = DateFormatter.tokenStepDay.date(from: day.date) else { return day.date }
        return formatter.string(from: date)
    }

    private var weekdayText: String {
        guard let date = DateFormatter.tokenStepDay.date(from: day.date) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = TokenStepLocalization.locale
        formatter.dateFormat = TokenStepLocalization.language == .en ? "EEE" : "EEEE"
        return formatter.string(from: date)
    }

    private var peakWindowText: String {
        guard let peakHour = rhythm.peakHour else { return "--" }
        return String(format: "%02d:00-%02d:00", peakHour, (peakHour + 1) % 24)
    }

    private var nightShare: Double {
        guard rhythm.totalTokens > 0 else { return 0 }
        let nightTokens = rhythm.tokens(in: 21...23) + rhythm.tokens(in: 0...2)
        return Double(nightTokens) / Double(rhythm.totalTokens)
    }

    private var longestActiveStreak: Int {
        var best = 0
        var current = 0
        for bucket in rhythm.buckets {
            if rhythm.isSignificant(bucket) {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return max(best, rhythm.activeHours > 0 ? 1 : 0)
    }
}

private struct RhythmNeonWavePanel: View {
    var rhythm: DailyRhythm
    var palette: RhythmCardPalette

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                RhythmGridShape(columns: 12, rows: 4)
                    .stroke(palette.accent.opacity(0.10), lineWidth: 1)

                RhythmAreaShape(values: values)
                    .fill(
                        LinearGradient(
                            colors: [palette.accent.opacity(0.48), palette.secondary.opacity(0.22), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blur(radius: 0.3)

                RhythmLineShape(values: values)
                    .stroke(palette.secondary.opacity(0.38), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                    .blur(radius: 10)

                RhythmLineShape(values: values)
                    .stroke(
                        LinearGradient(
                            colors: [palette.accent, palette.secondary, palette.night],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )

                RhythmPeakMarker(values: values, peakHour: rhythm.peakHour, color: palette.secondary)
            }
            .frame(height: 205)
            .padding(.horizontal, 4)

            HStack {
                RhythmAxisLabel(hour: 0, symbol: "moon.stars.fill", color: palette.night)
                Spacer()
                RhythmAxisLabel(hour: 6, symbol: nil, color: .white.opacity(0.48))
                Spacer()
                RhythmAxisLabel(hour: 12, symbol: "sun.max.fill", color: Color(red: 255 / 255, green: 184 / 255, blue: 32 / 255))
                Spacer()
                RhythmAxisLabel(hour: 18, symbol: nil, color: .white.opacity(0.48))
                Spacer()
                RhythmAxisLabel(hour: 24, symbol: "moon.fill", color: palette.night)
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 238)
    }

    private var values: [Double] {
        let rawValues = rhythm.buckets.map { Double($0.tokens) }
        let smoothed = rawValues.indices.map { index in
            smoothValue(in: rawValues, at: index)
        }
        let maxTokens = max(smoothed.max() ?? 0, 1)
        return smoothed.map { value in
            guard value > 0 else { return 0.04 }
            let normalized = pow(min(value / maxTokens, 1), 0.68)
            return max(0.08, min(normalized, 1))
        }
    }

    private func smoothValue(in values: [Double], at index: Int) -> Double {
        func value(_ offset: Int) -> Double {
            let target = index + offset
            guard values.indices.contains(target) else { return 0 }
            return values[target]
        }
        return value(0) * 0.78
            + (value(-1) + value(1)) * 0.09
            + (value(-2) + value(2)) * 0.02
    }
}

private struct RhythmAxisLabel: View {
    var hour: Int
    var symbol: String?
    var color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(hour == 24 ? "24时" : "\(hour)时")
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.white.opacity(0.48))
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(color)
            } else {
                Color.clear.frame(width: 16, height: 16)
            }
        }
    }
}

private struct RhythmBottomMetric: View {
    var symbol: String
    var title: String
    var value: String
    var color: Color

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption.weight(.black))
                Text(title)
                    .font(.caption.weight(.heavy))
            }
            .foregroundStyle(color)

            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.68)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RhythmMetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.20))
            .frame(width: 1, height: 54)
    }
}

private struct RhythmChevronCluster: View {
    var mirrored: Bool
    var palette: RhythmCardPalette

    var body: some View {
        HStack(spacing: -3) {
            ForEach(0..<4, id: \.self) { index in
                Image(systemName: mirrored ? "chevron.right" : "chevron.left")
                    .font(.system(size: 27, weight: .black))
                    .foregroundStyle(index == 1 ? palette.secondary : palette.accent.opacity(index == 2 ? 0.54 : 0.25))
            }
        }
        .shadow(color: palette.accent.opacity(0.34), radius: 9, x: 0, y: 0)
    }
}

private struct RhythmPeakMarker: View {
    var values: [Double]
    var peakHour: Int?
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            if let peakHour, values.indices.contains(peakHour) {
                let point = point(in: proxy.size, hour: peakHour)
                Path { path in
                    path.move(to: CGPoint(x: point.x, y: point.y))
                    path.addLine(to: CGPoint(x: point.x, y: proxy.size.height - 8))
                }
                .stroke(color.opacity(0.36), style: StrokeStyle(lineWidth: 1.5, dash: [5, 7]))

                Circle()
                    .fill(Color.white)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(color, lineWidth: 3))
                    .shadow(color: color.opacity(0.8), radius: 14, x: 0, y: 0)
                    .position(point)
            }
        }
    }

    private func point(in size: CGSize, hour: Int) -> CGPoint {
        let x = size.width * CGFloat(hour) / CGFloat(max(values.count - 1, 1))
        let value = values[hour]
        let y = size.height - 20 - CGFloat(value) * (size.height - 42)
        return CGPoint(x: x, y: y)
    }
}

private struct RhythmLineShape: Shape {
    var values: [Double]

    func path(in rect: CGRect) -> Path {
        rhythmPath(in: rect, closeToBottom: false)
    }
}

private struct RhythmAreaShape: Shape {
    var values: [Double]

    func path(in rect: CGRect) -> Path {
        rhythmPath(in: rect, closeToBottom: true)
    }
}

private extension RhythmLineShape {
    func rhythmPath(in rect: CGRect, closeToBottom: Bool) -> Path {
        makeRhythmPath(values: values, in: rect, closeToBottom: closeToBottom)
    }
}

private extension RhythmAreaShape {
    func rhythmPath(in rect: CGRect, closeToBottom: Bool) -> Path {
        makeRhythmPath(values: values, in: rect, closeToBottom: closeToBottom)
    }
}

private func makeRhythmPath(values: [Double], in rect: CGRect, closeToBottom: Bool) -> Path {
    let points = rhythmPoints(values: values, in: rect)
    var path = Path()
    guard let first = points.first else { return path }

    if closeToBottom {
        path.move(to: CGPoint(x: first.x, y: rect.maxY - 8))
        path.addLine(to: first)
    } else {
        path.move(to: first)
    }

    guard points.count > 1 else {
        return path
    }

    for index in 0..<(points.count - 1) {
        let p0 = points[max(index - 1, 0)]
        let p1 = points[index]
        let p2 = points[index + 1]
        let p3 = points[min(index + 2, points.count - 1)]
        let control1 = CGPoint(
            x: p1.x + (p2.x - p0.x) / 6,
            y: p1.y + (p2.y - p0.y) / 6
        )
        let control2 = CGPoint(
            x: p2.x - (p3.x - p1.x) / 6,
            y: p2.y - (p3.y - p1.y) / 6
        )
        path.addCurve(to: p2, control1: control1, control2: control2)
    }

    if closeToBottom, let last = points.last {
        path.addLine(to: CGPoint(x: last.x, y: rect.maxY - 8))
        path.closeSubpath()
    }
    return path
}

private func rhythmPoints(values: [Double], in rect: CGRect) -> [CGPoint] {
    guard !values.isEmpty else { return [] }
    let denominator = CGFloat(max(values.count - 1, 1))
    return values.enumerated().map { index, value in
        let x = rect.minX + rect.width * CGFloat(index) / denominator
        let clamped = min(max(value, 0), 1)
        let y = rect.maxY - 20 - CGFloat(clamped) * (rect.height - 42)
        return CGPoint(x: x, y: y)
    }
}

private struct LaurelBranch: Shape {
    var mirrored: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let xBase = mirrored ? rect.maxX * 0.36 : rect.maxX * 0.64
        let xTip = mirrored ? rect.minX + 3 : rect.maxX - 3
        path.move(to: CGPoint(x: xBase, y: rect.maxY - 4))
        path.addQuadCurve(
            to: CGPoint(x: xTip, y: rect.minY + 8),
            control: CGPoint(x: mirrored ? rect.minX + 7 : rect.maxX - 7, y: rect.midY)
        )
        for index in 0..<5 {
            let y = rect.maxY - 13 - CGFloat(index) * rect.height * 0.15
            let x = mirrored ? rect.midX - CGFloat(index) * 2.4 : rect.midX + CGFloat(index) * 2.4
            let leafWidth: CGFloat = 12
            let leafHeight: CGFloat = 6
            let direction: CGFloat = mirrored ? -1 : 1
            path.move(to: CGPoint(x: x, y: y))
            path.addQuadCurve(
                to: CGPoint(x: x + direction * leafWidth, y: y - leafHeight),
                control: CGPoint(x: x + direction * leafWidth * 0.72, y: y - leafHeight * 1.25)
            )
            path.addQuadCurve(
                to: CGPoint(x: x, y: y),
                control: CGPoint(x: x + direction * leafWidth * 0.34, y: y - leafHeight * 0.16)
            )
        }
        return path
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

private struct RhythmCardBackdrop: View {
    var palette: RhythmCardPalette

    var body: some View {
        ZStack {
            LinearGradient(colors: palette.background, startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(
                colors: [palette.accent.opacity(0.26), .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 440
            )
            RadialGradient(
                colors: [palette.secondary.opacity(0.16), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 380
            )
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 420, bottomTrailingRadius: 0, topTrailingRadius: 22, style: .continuous)
                .fill(palette.accent.opacity(0.10))
                .frame(width: 360, height: 380)
                .rotationEffect(.degrees(-23))
                .offset(x: 250, y: -48)
            RhythmGridShape(columns: 11, rows: 14)
                .stroke(Color.white.opacity(0.026), lineWidth: 1)
        }
    }
}

private struct RhythmCardPalette {
    var background: [Color]
    var accent: Color
    var secondary: Color
    var night: Color
    var panel: Color

    static func palette(for rhythm: DailyRhythm) -> RhythmCardPalette {
        switch rhythm.primaryTag {
        case .nightAgent:
            return RhythmCardPalette(
                background: [
                    Color(red: 2 / 255, green: 6 / 255, blue: 17 / 255),
                    Color(red: 3 / 255, green: 14 / 255, blue: 25 / 255),
                    Color(red: 8 / 255, green: 12 / 255, blue: 35 / 255)
                ],
                accent: Color(red: 74 / 255, green: 247 / 255, blue: 139 / 255),
                secondary: Color(red: 62 / 255, green: 192 / 255, blue: 255 / 255),
                night: Color(red: 45 / 255, green: 108 / 255, blue: 255 / 255),
                panel: Color(red: 4 / 255, green: 38 / 255, blue: 43 / 255)
            )
        case .morningPlanner, .earlyStarter:
            return RhythmCardPalette(
                background: [
                    Color(red: 3 / 255, green: 15 / 255, blue: 12 / 255),
                    Color(red: 4 / 255, green: 35 / 255, blue: 27 / 255),
                    Color(red: 31 / 255, green: 30 / 255, blue: 13 / 255)
                ],
                accent: Color(red: 85 / 255, green: 246 / 255, blue: 151 / 255),
                secondary: Color(red: 255 / 255, green: 190 / 255, blue: 44 / 255),
                night: Color(red: 47 / 255, green: 152 / 255, blue: 255 / 255),
                panel: Color(red: 4 / 255, green: 41 / 255, blue: 34 / 255)
            )
        case .fragmented, .doublePeak:
            return RhythmCardPalette(
                background: [
                    Color(red: 5 / 255, green: 8 / 255, blue: 18 / 255),
                    Color(red: 4 / 255, green: 28 / 255, blue: 27 / 255),
                    Color(red: 20 / 255, green: 12 / 255, blue: 42 / 255)
                ],
                accent: Color(red: 80 / 255, green: 246 / 255, blue: 144 / 255),
                secondary: Color(red: 46 / 255, green: 214 / 255, blue: 255 / 255),
                night: Color(red: 105 / 255, green: 92 / 255, blue: 255 / 255),
                panel: Color(red: 5 / 255, green: 37 / 255, blue: 42 / 255)
            )
        default:
            return RhythmCardPalette(
                background: [
                    Color(red: 1 / 255, green: 10 / 255, blue: 7 / 255),
                    Color(red: 3 / 255, green: 22 / 255, blue: 17 / 255),
                    Color(red: 2 / 255, green: 19 / 255, blue: 31 / 255)
                ],
                accent: Color(red: 79 / 255, green: 244 / 255, blue: 138 / 255),
                secondary: Color(red: 49 / 255, green: 205 / 255, blue: 255 / 255),
                night: Color(red: 41 / 255, green: 104 / 255, blue: 255 / 255),
                panel: Color(red: 3 / 255, green: 38 / 255, blue: 41 / 255)
            )
        }
    }
}
