import AppKit
import SwiftUI

struct StatusBarLabelView: View {
    var tokens: Int
    var lap: TokenStepLapProgress
    var refreshing: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: StatusBarIconRenderer.progressRing(progress: lap.currentLapProgress, lap: lap.currentLap, refreshing: refreshing))
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .accessibilityLabel("\(lap.lapTitle) \(lap.lapPercentText)")

            Text(TokenStepFormat.tokens(tokens, compact: true))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.primary)
        }
        .padding(.horizontal, 2)
        .frame(height: 24)
    }
}

struct TokenStepBackdrop: View {
    var body: some View {
        ZStack {
            Color.tokenCanvas
            LinearGradient(
                colors: [
                    Color.tokenMint.opacity(0.22),
                    Color.clear,
                    Color.tokenGreen.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct TokenStepMark: View {
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color.tokenSurface)
                .shadow(color: Color.tokenGreenDark.opacity(0.16), radius: size * 0.22, x: 0, y: size * 0.12)

            Circle()
                .stroke(Color.tokenTrack, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
                .frame(width: size * 0.66, height: size * 0.66)

            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(
                    LinearGradient(
                        colors: [.tokenMint, .tokenGreen, .tokenGreenDark],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: size * 0.66, height: size * 0.66)

            VStack(spacing: size * 0.045) {
                HStack(spacing: size * 0.045) {
                    roundedDot(opacity: 0.34)
                    roundedDot(opacity: 0.70)
                    roundedDot(opacity: 0.34)
                }
                HStack(spacing: size * 0.045) {
                    roundedDot(opacity: 0.70)
                    roundedDot(opacity: 1.00)
                    roundedDot(opacity: 0.70)
                }
                HStack(spacing: size * 0.045) {
                    roundedDot(opacity: 0.34)
                    roundedDot(opacity: 0.70)
                    roundedDot(opacity: 0.34)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private func roundedDot(opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: size * 0.035, style: .continuous)
            .fill(Color.tokenGreen.opacity(opacity))
            .frame(width: size * 0.095, height: size * 0.095)
    }
}

struct ErrorBanner: View {
    var message: String
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.quaternary))
    }
}

struct ProgressRingView: View {
    var progress: Double
    var lineWidth: CGFloat = 18
    var color: Color = .tokenGreen

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.tokenTrack, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    LinearGradient(colors: [color.opacity(0.82), color, Color.tokenGreenDark], startPoint: .bottomLeading, endPoint: .topTrailing),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.18), radius: 8, x: 0, y: 4)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct MetricPill: View {
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.bold))
                .foregroundStyle(Color.tokenInk)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.tokenSurface, in: Capsule())
        .overlay(Capsule().stroke(Color.black.opacity(0.055)))
    }
}

struct TokenCard<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(24)
            .background(Color.tokenSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.black.opacity(0.06)))
            .shadow(color: Color.black.opacity(0.055), radius: 24, x: 0, y: 14)
    }
}

struct UsageProgressRow: View {
    var name: String
    var value: String
    var percent: Double
    var color: Color = .tokenGreen

    var body: some View {
        HStack(spacing: 14) {
            Text(name)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.tokenInk.opacity(0.76))
                .lineLimit(1)
                .frame(width: 132, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.tokenTrack)
                    if percent > 0 {
                        Capsule()
                            .fill(color)
                            .frame(width: max(5, proxy.size.width * min(max(percent, 0), 100) / 100))
                    }
                }
            }
            .frame(height: 8)

            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 132, alignment: .trailing)
        }
        .frame(height: 24)
    }
}

struct ActivityBarsView: View {
    var rows: [DailyUsage]
    var goal: Int
    var maxCount: Int = 30

    var visibleRows: [DailyUsage] {
        Array(rows.suffix(maxCount))
    }

    var body: some View {
        GeometryReader { proxy in
            let days = visibleRows
            let gap: CGFloat = 5
            let width = max(4, (proxy.size.width - gap * CGFloat(max(days.count - 1, 0))) / CGFloat(max(days.count, 1)))
            let maxTokens = max(goal, days.map(\.totalTokens).max() ?? 1, 1)

            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 1)
                    .offset(y: -proxy.size.height * CGFloat(goal) / CGFloat(maxTokens))

                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(days) { day in
                        RoundedRectangle(cornerRadius: min(4, width / 2), style: .continuous)
                            .fill(contributionColor(tokens: day.totalTokens, goal: goal))
                            .frame(width: width, height: max(4, proxy.size.height * CGFloat(day.totalTokens) / CGFloat(maxTokens)))
                    }
                }
            }
        }
    }
}

struct ContributionWallView: View {
    var rows: [DailyUsage]
    var goal: Int
    var weeks: Int = 34

    private var rowByDate: [String: DailyUsage] {
        Dictionary(uniqueKeysWithValues: rows.map { ($0.date, $0) })
    }

    var body: some View {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let rawStart = calendar.date(byAdding: .day, value: -(weeks * 7 - 1), to: today) ?? today
        let weekday = calendar.component(.weekday, from: rawStart)
        let mondayOffset = (weekday + 5) % 7
        let start = calendar.date(byAdding: .day, value: -mondayOffset, to: rawStart) ?? rawStart

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 5) {
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: 5) {
                        ForEach(0..<7, id: \.self) { dayIndex in
                            let day = calendar.date(byAdding: .day, value: week * 7 + dayIndex, to: start) ?? today
                            let key = DateFormatter.tokenStepDay.string(from: day)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(day > today ? Color.clear : contributionColor(tokens: rowByDate[key]?.totalTokens ?? 0, goal: goal))
                                .frame(width: 15, height: 15)
                                .overlay {
                                    if calendar.isDate(day, inSameDayAs: today) {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .stroke(Color.tokenGreenDark, lineWidth: 1.5)
                                    }
                                }
                        }
                    }
                }
            }

            HStack {
                MetricPill(label: "活跃", value: "\(rows.filter { $0.totalTokens > 0 }.count) 天")
                MetricPill(label: "达标", value: "\(rows.filter { $0.totalTokens >= goal }.count) 天")
                MetricPill(label: "最高", value: TokenStepFormat.tokens(rows.map(\.totalTokens).max() ?? 0, compact: true))
                Spacer()
                Text("少")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach([0, Int(Double(goal) * 0.25), Int(Double(goal) * 0.7), goal, goal * 2, goal * 3], id: \.self) { value in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(contributionColor(tokens: value, goal: goal))
                        .frame(width: 15, height: 15)
                }
                Text("多")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

func contributionColor(tokens: Int, goal: Int) -> Color {
    guard tokens > 0 else { return Color.tokenTrack }
    if tokens >= max(goal, 1) {
        return TokenStepLapProgress(tokens: tokens, goal: goal).color
    }
    let progress = Double(tokens) / Double(max(goal, 1))
    switch progress {
    case 0.65...: return .tokenGreenDark
    case 0.35..<0.65: return .tokenGreen
    case 0.12..<0.35: return .tokenMint
    default: return Color(red: 216 / 255, green: 243 / 255, blue: 220 / 255)
    }
}
