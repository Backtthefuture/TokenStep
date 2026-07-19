import SwiftUI

struct TodayAgentWorkCard: View {
    @EnvironmentObject private var appState: AppState
    @State private var period: AgentWorkPeriod = .today
    @State private var sourceFilter: AgentWorkSourceFilter = .all

    private var work: DailyAgentWork {
        appState.todayAgentWork
    }

    var body: some View {
        TokenCard {
            VStack(alignment: .leading, spacing: 16) {
                header
                sourceFilterRow
                metricStrip

                AgentWorkActivityChart(
                    hours: chartHours,
                    legendSources: legendSources,
                    period: period,
                    unbucketedTokens: selectedUnbucketedTokens
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L("Agent 工作强度"))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color.tokenInk)
                Text(AgentWorkCopy.disclaimer)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            HStack(spacing: 4) {
                ForEach(AgentWorkPeriod.allCases) { item in
                    AgentWorkSegmentButton(
                        title: item.title,
                        selected: period == item
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            period = item
                        }
                    }
                }
            }
            .padding(4)
            .background(Color.tokenTrack.opacity(0.42), in: Capsule())
        }
    }

    private var sourceFilterRow: some View {
        HStack(spacing: 8) {
            ForEach(AgentWorkSourceFilter.allCases) { item in
                AgentWorkFilterButton(
                    title: item.title,
                    selected: sourceFilter == item,
                    color: item.tint
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        sourceFilter = item
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var metricStrip: some View {
        HStack(spacing: 10) {
            AgentWorkMetricTile(
                title: L("Agent Token"),
                value: TokenStepFormat.tokens(selectedPeriodTokens, compact: true),
                detail: period.metricDetail,
                symbol: "bolt.horizontal.circle.fill",
                color: .tokenGreen
            )
            AgentWorkMetricTile(
                title: AgentWorkCopy.recordedHours,
                value: "\(selectedActiveHours)/\(period.maximumHours)",
                detail: AgentWorkCopy.recordedHourDetail,
                symbol: "clock.fill",
                color: Color(red: 0.20, green: 0.52, blue: 0.92)
            )
            AgentWorkMetricTile(
                title: L("近 7 日均"),
                value: TokenStepFormat.tokens(selectedSevenDayAverage, compact: true),
                detail: AgentWorkCopy.calendarDayAverage,
                symbol: "calendar.badge.clock",
                color: Color(red: 0.50, green: 0.28, blue: 0.92)
            )
            AgentWorkMetricTile(
                title: AgentWorkCopy.cacheHitRate,
                value: cacheRateText(selectedCacheHitRate),
                detail: selectedCacheHitRate == nil
                    ? AgentWorkCopy.coverageUnavailable
                    : AgentWorkCopy.completeCoverageOnly,
                symbol: "arrow.triangle.2.circlepath",
                color: .tokenGreenDark
            )
        }
    }

    private var trailingSevenDayWorks: [DailyAgentWork] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let todayKey = DateFormatter.tokenStepDay.string(from: Date())
        guard let today = DateFormatter.tokenStepDay.date(from: todayKey) else {
            return [work]
        }
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            return appState.agentWork(for: DateFormatter.tokenStepDay.string(from: date))
        }
    }

    private var periodWorks: [DailyAgentWork] {
        switch period {
        case .today:
            return [work]
        case .sevenDays:
            return trailingSevenDayWorks
        }
    }

    private var selectedPeriodTokens: Int {
        periodWorks.map(selectedTokens(in:)).reduce(0, +)
    }

    private var selectedSevenDayAverage: Int {
        trailingSevenDayWorks.map(selectedTokens(in:)).reduce(0, +) / 7
    }

    private var selectedActiveHours: Int {
        periodWorks.reduce(0) { partial, work in
            partial + work.hourlyBuckets.filter { selectedTokens(in: $0) > 0 }.count
        }
    }

    private var selectedBucketedTokens: Int {
        periodWorks
            .flatMap(\.hourlyBuckets)
            .map(selectedTokens(in:))
            .reduce(0, +)
    }

    private var selectedUnbucketedTokens: Int {
        max(0, selectedPeriodTokens - selectedBucketedTokens)
    }

    private var selectedCacheHitRate: Double? {
        if sourceFilter == .all {
            let activeWorks = periodWorks.filter { $0.totalTokens > 0 }
            guard !activeWorks.isEmpty,
                  activeWorks.allSatisfy(\.cacheCoverageComplete)
            else {
                return nil
            }
            let totalInput = activeWorks.map(\.inputTokens).reduce(0, +)
            guard totalInput > 0 else { return nil }
            let cachedInput = activeWorks.map(\.cachedInputTokens).reduce(0, +)
            return Double(cachedInput) / Double(totalInput)
        }

        guard selectedUnbucketedTokens == 0 else { return nil }
        let sources = periodWorks
            .flatMap(\.hourlyBuckets)
            .flatMap(\.sources)
            .filter { sourceFilter.includes($0.source) && $0.tokens > 0 }
        guard !sources.isEmpty,
              sources.allSatisfy(\.cacheCoverageComplete)
        else {
            return nil
        }
        let totalInput = sources.map(\.inputTokens).reduce(0, +)
        guard totalInput > 0 else { return nil }
        return Double(sources.map(\.cachedInputTokens).reduce(0, +)) / Double(totalInput)
    }

    private var chartHours: [AgentWorkChartHour] {
        var hourly = Array(repeating: [String: AgentWorkChartSource](), count: 24)

        for work in periodWorks {
            for bucket in work.hourlyBuckets where (0..<24).contains(bucket.hour) {
                for source in bucket.sources where sourceFilter.includes(source.source) {
                    var aggregate = hourly[bucket.hour][source.source]
                        ?? AgentWorkChartSource(
                            source: source.source,
                            tokens: 0,
                            inputTokens: 0,
                            cachedInputTokens: 0,
                            outputTokens: 0,
                            cacheCoverageComplete: true
                        )
                    aggregate.tokens += max(0, source.tokens)
                    aggregate.inputTokens += max(0, source.inputTokens)
                    aggregate.cachedInputTokens += max(0, source.cachedInputTokens)
                    aggregate.outputTokens += max(0, source.outputTokens)
                    aggregate.cacheCoverageComplete = aggregate.cacheCoverageComplete
                        && source.cacheCoverageComplete
                    hourly[bucket.hour][source.source] = aggregate
                }
            }
        }

        return (0..<24).map { hour in
            AgentWorkChartHour(
                hour: hour,
                sources: hourly[hour].values
                    .filter { $0.tokens > 0 }
                    .sorted {
                        if $0.tokens == $1.tokens {
                            return $0.source < $1.source
                        }
                        return $0.tokens > $1.tokens
                    }
            )
        }
    }

    private var legendSources: [AgentWorkLegendSource] {
        var tokensBySource: [String: Int] = [:]
        for work in periodWorks {
            for source in work.sources where sourceFilter.includes(source.source) {
                tokensBySource[source.source, default: 0] += source.tokens
            }
        }
        return tokensBySource
            .filter { $0.value > 0 }
            .map { AgentWorkLegendSource(source: $0.key, tokens: $0.value) }
            .sorted {
                if $0.tokens == $1.tokens {
                    return $0.source < $1.source
                }
                return $0.tokens > $1.tokens
            }
    }

    private func selectedTokens(in work: DailyAgentWork) -> Int {
        guard sourceFilter != .all else { return work.totalTokens }
        return work.sources
            .filter { sourceFilter.includes($0.source) }
            .map(\.tokens)
            .reduce(0, +)
    }

    private func selectedTokens(in bucket: AgentWorkHourBucket) -> Int {
        bucket.sources
            .filter { sourceFilter.includes($0.source) }
            .map(\.tokens)
            .reduce(0, +)
    }
}

struct PopoverAgentWorkStrip: View {
    @EnvironmentObject private var appState: AppState
    static let destination: AppSection = .today

    private var work: DailyAgentWork {
        appState.todayAgentWork
    }

    var body: some View {
        Button {
            MainWindowPresenter.shared.show(appState: appState, section: Self.destination)
        } label: {
            HStack(spacing: 8) {
                Label(AgentWorkCopy.agentActivity, systemImage: "bolt.horizontal.circle.fill")
                    .labelStyle(.titleAndIcon)
                Text(popoverSummary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.heavy))
            .foregroundStyle(Color.tokenInk.opacity(0.78))
            .padding(.horizontal, 13)
            .frame(height: 40)
            .background(Color.tokenSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.black.opacity(0.055)))
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(L("打开今日页"))
    }

    private var popoverSummary: String {
        [
            TokenStepFormat.tokens(work.totalTokens, compact: true),
            AgentWorkCopy.recordedShort("\(work.activeHours)/24"),
            "\(AgentWorkCopy.cacheShort) \(cacheRateText(work.cacheHitRate))"
        ]
        .joined(separator: " · ")
    }
}

private struct AgentWorkMetricTile: View {
    var title: String
    var value: String
    var detail: String
    var symbol: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption.weight(.black))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 23, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.tokenInk)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .monospacedDigit()
            Text(detail)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.tokenTrack.opacity(0.24), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.black.opacity(0.025))
        )
    }
}

private struct AgentWorkActivityChart: View {
    var hours: [AgentWorkChartHour]
    var legendSources: [AgentWorkLegendSource]
    var period: AgentWorkPeriod
    var unbucketedTokens: Int

    @State private var hoveredHour: Int?

    private var maxTokens: Int {
        max(1, hours.map(\.tokens).max() ?? 0)
    }

    private var hasBucketedData: Bool {
        hours.contains { $0.tokens > 0 }
    }

    private var hasCacheLine: Bool {
        hours.contains { $0.cacheHitRate != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(period.chartTitle)
                    .font(.callout.weight(.heavy))
                    .foregroundStyle(Color.tokenInk)
                Spacer(minLength: 10)
                Text(chartContext)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .monospacedDigit()
            }

            if hasBucketedData {
                ZStack(alignment: .trailing) {
                    AgentWorkPlot(
                        hours: hours,
                        maxTokens: maxTokens,
                        hasCacheLine: hasCacheLine,
                        displayDivisor: period == .sevenDays ? 7 : 1,
                        hoveredHour: $hoveredHour
                    )
                    .padding(.trailing, hasCacheLine ? 34 : 0)

                    if hasCacheLine {
                        AgentWorkCacheAxis()
                    }
                }
                .frame(height: 184)

                HStack {
                    AgentWorkAxisLabel("00")
                    Spacer()
                    AgentWorkAxisLabel("06")
                    Spacer()
                    AgentWorkAxisLabel("12")
                    Spacer()
                    AgentWorkAxisLabel("18")
                    Spacer()
                    AgentWorkAxisLabel("24")
                }
                .padding(.trailing, hasCacheLine ? 34 : 0)
            } else {
                HStack(spacing: 9) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.callout.weight(.heavy))
                    Text(unbucketedTokens > 0 ? AgentWorkCopy.noTimedData : AgentWorkCopy.noAgentWork)
                        .font(.callout.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 184)
                .background(Color.tokenTrack.opacity(0.18), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }

            footer
        }
        .padding(14)
        .background(Color.tokenSurface.opacity(0.64), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.055))
        )
        .animation(.easeOut(duration: 0.24), value: hours.map(\.tokens))
    }

    private var chartContext: String {
        guard let hoveredHour,
              let hour = hours.first(where: { $0.hour == hoveredHour })
        else {
            return hasCacheLine ? AgentWorkCopy.chartLegendHint : AgentWorkCopy.tokenBarHint
        }
        let displayedTokens = period == .sevenDays
            ? max(hour.tokens > 0 ? 1 : 0, Int((Double(hour.tokens) / 7).rounded()))
            : hour.tokens
        var parts = [
            String(format: "%02d:00", hour.hour),
            TokenStepFormat.tokens(displayedTokens, compact: true)
                + (period == .sevenDays ? AgentWorkCopy.averageSuffix : "")
        ]
        let sources = agentWorkSourceBreakdown(
            hour.sources,
            displayDivisor: period == .sevenDays ? 7 : 1,
            limit: 2
        )
        if !sources.isEmpty {
            parts.append(sources)
        }
        if let rate = hour.cacheHitRate {
            parts.append("\(AgentWorkCopy.cacheShort) \(cacheRateText(rate))")
        }
        return parts.joined(separator: " · ")
    }

    private var footer: some View {
        HStack(spacing: 12) {
            ForEach(Array(legendSources.prefix(4))) { source in
                HStack(spacing: 5) {
                    Circle()
                        .fill(tokenToolColor(source.source))
                        .frame(width: 8, height: 8)
                    Text(source.source)
                        .lineLimit(1)
                }
            }

            if legendSources.count > 4 {
                Text("+\(legendSources.count - 4)")
            }

            if hasCacheLine {
                HStack(spacing: 5) {
                    Capsule()
                        .fill(Color.tokenGreenDark)
                        .frame(width: 15, height: 2)
                    Text(AgentWorkCopy.cacheHitRate)
                }
            }

            Spacer(minLength: 8)

            if unbucketedTokens > 0 {
                Text(
                    period == .sevenDays
                        ? AgentWorkCopy.unbucketedSevenDayTotal(
                            TokenStepFormat.tokens(unbucketedTokens, compact: true)
                        )
                        : AgentWorkCopy.unbucketed(
                            TokenStepFormat.tokens(unbucketedTokens, compact: true)
                        )
                )
                    .foregroundStyle(Color.orange)
                    .help(AgentWorkCopy.unbucketedHelp)
            }
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.68)
    }
}

private struct AgentWorkPlot: View {
    var hours: [AgentWorkChartHour]
    var maxTokens: Int
    var hasCacheLine: Bool
    var displayDivisor: Int
    @Binding var hoveredHour: Int?

    var body: some View {
        GeometryReader { proxy in
            let slotWidth = proxy.size.width / 24

            ZStack {
                AgentWorkGrid()

                if let hoveredHour {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.tokenMint.opacity(0.20))
                        .frame(width: max(6, slotWidth - 2), height: proxy.size.height)
                        .position(
                            x: slotWidth * (CGFloat(hoveredHour) + 0.5),
                            y: proxy.size.height / 2
                        )
                }

                ForEach(hours) { hour in
                    let height = hour.tokens > 0
                        ? max(3, proxy.size.height * CGFloat(hour.tokens) / CGFloat(max(maxTokens, 1)))
                        : 2
                    AgentWorkStackedBar(
                        sources: hour.sources,
                        totalTokens: hour.tokens,
                        empty: hour.tokens == 0
                    )
                    .frame(
                        width: min(18, max(5, slotWidth * 0.58)),
                        height: height
                    )
                    .position(
                        x: slotWidth * (CGFloat(hour.hour) + 0.5),
                        y: proxy.size.height - height / 2
                    )
                }

                if hasCacheLine {
                    AgentCacheHitLineShape(values: hours.map(\.cacheHitRate))
                        .stroke(
                            Color.tokenGreenDark,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: Color.tokenGreen.opacity(0.16), radius: 4)

                    ForEach(hours) { hour in
                        if let rate = hour.cacheHitRate {
                            Circle()
                                .fill(Color.tokenSurface)
                                .overlay(Circle().stroke(Color.tokenGreenDark, lineWidth: 2))
                                .frame(width: 7, height: 7)
                                .position(
                                    x: slotWidth * (CGFloat(hour.hour) + 0.5),
                                    y: cachePointY(rate: rate, height: proxy.size.height)
                                )
                        }
                    }
                }

                ForEach(hours) { hour in
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: slotWidth, height: proxy.size.height)
                        .position(
                            x: slotWidth * (CGFloat(hour.hour) + 0.5),
                            y: proxy.size.height / 2
                        )
                        .onHover { hovering in
                            if hovering {
                                hoveredHour = hour.hour
                            } else if hoveredHour == hour.hour {
                                hoveredHour = nil
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityText(for: hour))
                }
            }
        }
    }

    private func accessibilityText(for hour: AgentWorkChartHour) -> String {
        let displayedTokens = max(
            hour.tokens > 0 ? 1 : 0,
            Int((Double(hour.tokens) / Double(max(displayDivisor, 1))).rounded())
        )
        var text = "\(String(format: "%02d:00", hour.hour)), \(TokenStepFormat.tokens(displayedTokens))"
        if displayDivisor > 1 {
            text += AgentWorkCopy.averageSuffix
        }
        let sources = agentWorkSourceBreakdown(
            hour.sources,
            displayDivisor: displayDivisor,
            limit: nil
        )
        if !sources.isEmpty {
            text += ", \(sources)"
        }
        if let rate = hour.cacheHitRate {
            text += ", \(AgentWorkCopy.cacheHitRate) \(cacheRateText(rate))"
        }
        return text
    }
}

private struct AgentWorkGrid: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
                Rectangle()
                    .fill(Color.tokenTrack.opacity(index == 4 ? 0.72 : 0.44))
                    .frame(height: 1)
                if index < 4 {
                    Spacer()
                }
            }
        }
    }
}

private struct AgentWorkStackedBar: View {
    var sources: [AgentWorkChartSource]
    var totalTokens: Int
    var empty: Bool

    var body: some View {
        if empty {
            Capsule()
                .fill(Color.tokenTrack.opacity(0.72))
        } else {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    ForEach(Array(sources.reversed())) { source in
                        Rectangle()
                            .fill(tokenToolColor(source.source))
                            .frame(
                                height: proxy.size.height
                                    * CGFloat(source.tokens)
                                    / CGFloat(max(totalTokens, 1))
                            )
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.white.opacity(0.42), lineWidth: 0.5)
            )
        }
    }
}

private struct AgentCacheHitLineShape: Shape {
    var values: [Double?]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var hasCurrentSegment = false
        let slotWidth = rect.width / CGFloat(max(values.count, 1))

        for (index, value) in values.enumerated() {
            guard let value else {
                hasCurrentSegment = false
                continue
            }
            let point = CGPoint(
                x: slotWidth * (CGFloat(index) + 0.5),
                y: cachePointY(rate: value, height: rect.height)
            )
            if hasCurrentSegment {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                hasCurrentSegment = true
            }
        }
        return path
    }
}

private struct AgentWorkCacheAxis: View {
    var body: some View {
        VStack {
            Text("100%")
            Spacer()
            Text("0%")
        }
        .font(.system(size: 9, weight: .bold, design: .rounded))
        .foregroundStyle(Color.tokenGreenDark.opacity(0.72))
        .monospacedDigit()
        .frame(width: 30)
        .padding(.vertical, 1)
        .accessibilityHidden(true)
    }
}

private struct AgentWorkAxisLabel: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
}

private struct AgentWorkSegmentButton: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.heavy))
                .foregroundStyle(selected ? Color.tokenSurface : Color.tokenInk.opacity(0.62))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(selected ? Color.tokenInk : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct AgentWorkFilterButton: View {
    var title: String
    var selected: Bool
    var color: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(selected ? Color.tokenSurface : color)
                    .frame(width: 7, height: 7)
                Text(title)
                    .lineLimit(1)
            }
            .font(.caption.weight(.heavy))
            .foregroundStyle(selected ? Color.tokenSurface : Color.tokenInk.opacity(0.68))
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(
                selected ? color : Color.tokenTrack.opacity(0.25),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(selected ? Color.clear : Color.black.opacity(0.045))
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct AgentWorkChartSource: Identifiable {
    var id: String { source }
    var source: String
    var tokens: Int
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var cacheCoverageComplete: Bool
}

private struct AgentWorkChartHour: Identifiable {
    var id: Int { hour }
    var hour: Int
    var sources: [AgentWorkChartSource]

    var tokens: Int {
        sources.map(\.tokens).reduce(0, +)
    }

    var cacheHitRate: Double? {
        let activeSources = sources.filter { $0.tokens > 0 }
        guard !activeSources.isEmpty,
              activeSources.allSatisfy(\.cacheCoverageComplete)
        else {
            return nil
        }
        let input = activeSources.map(\.inputTokens).reduce(0, +)
        guard input > 0 else { return nil }
        return Double(activeSources.map(\.cachedInputTokens).reduce(0, +)) / Double(input)
    }
}

private struct AgentWorkLegendSource: Identifiable {
    var id: String { source }
    var source: String
    var tokens: Int
}

private enum AgentWorkPeriod: String, CaseIterable, Identifiable {
    case today
    case sevenDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return AgentWorkCopy.today
        case .sevenDays: return AgentWorkCopy.sevenDays
        }
    }

    var metricDetail: String {
        switch self {
        case .today: return AgentWorkCopy.today
        case .sevenDays: return AgentWorkCopy.sevenDayTotal
        }
    }

    var maximumHours: Int {
        switch self {
        case .today: return 24
        case .sevenDays: return 168
        }
    }

    var chartTitle: String {
        switch self {
        case .today: return AgentWorkCopy.hourlyDistribution
        case .sevenDays: return AgentWorkCopy.sevenDayHourlyDistribution
        }
    }
}

private enum AgentWorkSourceFilter: String, CaseIterable, Identifiable {
    case all
    case codex
    case hermes
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return AgentWorkCopy.all
        case .codex: return "Codex"
        case .hermes: return "Hermes"
        case .other: return AgentWorkCopy.other
        }
    }

    var tint: Color {
        switch self {
        case .all: return Color.tokenInk
        case .codex: return tokenToolColor("Codex")
        case .hermes: return tokenToolColor("Hermes Agent")
        case .other: return Color(red: 0.20, green: 0.52, blue: 0.92)
        }
    }

    func includes(_ source: String) -> Bool {
        let normalized = source.lowercased()
        let isCodex = normalized == "codex" || normalized.hasPrefix("codex via")
        let isHermes = normalized.contains("hermes")
        switch self {
        case .all:
            return true
        case .codex:
            return isCodex
        case .hermes:
            return isHermes
        case .other:
            return !isCodex && !isHermes
        }
    }
}

enum AgentWorkCopy {
    static var today: String {
        localized("今日", "Today", "今日")
    }

    static var sevenDays: String {
        localized("近 7 天", "Last 7 Days", "近 7 天")
    }

    static var sevenDayTotal: String {
        localized("7 个日历日合计", "7 calendar days total", "7 個日曆日合計")
    }

    static var all: String {
        localized("全部", "All", "全部")
    }

    static var other: String {
        localized("其他", "Other", "其他")
    }

    static var disclaimer: String {
        localized(
            "按本机 Token 记录展示活跃节奏，不代表实际工时或生产力。",
            "Shows local Token activity, not actual work time or productivity.",
            "按本機 Token 記錄展示活躍節奏，不代表實際工時或生產力。"
        )
    }

    static var agentActivity: String {
        localized("Agent 活跃", "Agent Activity", "Agent 活躍")
    }

    static var recordedHours: String {
        localized("有记录小时", "Hours with Records", "有記錄小時")
    }

    static var recordedHourDetail: String {
        localized("有 Token 记录，非工时", "Token records, not work time", "有 Token 記錄，非工時")
    }

    static func recordedShort(_ value: String) -> String {
        localized("记录 \(value)", "Recorded \(value)", "記錄 \(value)")
    }

    static var calendarDayAverage: String {
        localized("按 7 个日历日折算", "Across 7 calendar days", "按 7 個日曆日折算")
    }

    static var cacheHitRate: String {
        localized("缓存命中率", "Cache Hit Rate", "快取命中率")
    }

    static var cacheShort: String {
        localized("缓存", "Cache", "快取")
    }

    static var completeCoverageOnly: String {
        localized("仅展示完整口径", "Complete coverage only", "僅展示完整口徑")
    }

    static var coverageUnavailable: String {
        localized("口径不完整", "Incomplete coverage", "口徑不完整")
    }

    static var hourlyDistribution: String {
        localized("24 小时 Token 记录", "24-Hour Token Records", "24 小時 Token 記錄")
    }

    static var sevenDayHourlyDistribution: String {
        localized("近 7 天分时日均", "7-Day Hourly Average", "近 7 天分時日均")
    }

    static var chartLegendHint: String {
        localized("柱形为 Token · 折线为缓存", "Bars: Tokens · Line: Cache", "柱形為 Token · 折線為快取")
    }

    static var tokenBarHint: String {
        localized("柱形为 Token", "Bars: Tokens", "柱形為 Token")
    }

    static var noTimedData: String {
        localized("已有 Token，但缺少可用时段", "Tokens found, but hourly timing is unavailable", "已有 Token，但缺少可用時段")
    }

    static var noAgentWork: String {
        localized("这个时段还没有可统计的 Agent Token", "No countable Agent Tokens in this period", "這個時段還沒有可統計的 Agent Token")
    }

    static var averageSuffix: String {
        localized(" 日均", " daily avg", " 日均")
    }

    static var unbucketedHelp: String {
        localized(
            "这些 Token 有总量，但缺少可靠时间戳，因此没有放进小时柱。",
            "These Tokens have totals but no reliable timestamps, so they are excluded from hourly bars.",
            "這些 Token 有總量，但缺少可靠時間戳，因此沒有放進小時柱。"
        )
    }

    static func unbucketed(_ value: String) -> String {
        localized("未分时 \(value)", "Unbucketed \(value)", "未分時 \(value)")
    }

    static func unbucketedSevenDayTotal(_ value: String) -> String {
        localized(
            "未分时 7 天合计 \(value)",
            "Unbucketed 7d total \(value)",
            "未分時 7 天合計 \(value)"
        )
    }

    static func hourLabel(_ hour: Int) -> String {
        localized("\(hour)时", "\(hour)h", "\(hour)時")
    }

    private static func localized(_ zhHans: String, _ en: String, _ zhHant: String) -> String {
        switch TokenStepLocalization.language {
        case .en:
            return en
        case .zhHant:
            return zhHant
        case .zhHans, .system:
            return zhHans
        }
    }
}

private func cacheRateText(_ rate: Double?) -> String {
    guard let rate else { return "--" }
    return TokenStepFormat.percent(min(max(rate, 0), 1) * 100)
}

private func agentWorkSourceBreakdown(
    _ sources: [AgentWorkChartSource],
    displayDivisor: Int,
    limit: Int?
) -> String {
    let activeSources = sources.filter { $0.tokens > 0 }
    let visibleCount = min(limit ?? activeSources.count, activeSources.count)
    var parts = activeSources.prefix(visibleCount).map { source in
        let displayedTokens = max(
            1,
            Int((Double(source.tokens) / Double(max(displayDivisor, 1))).rounded())
        )
        return "\(source.source) \(TokenStepFormat.tokens(displayedTokens, compact: true))"
    }
    if visibleCount < activeSources.count {
        parts.append("+\(activeSources.count - visibleCount)")
    }
    return parts.joined(separator: " + ")
}

private func cachePointY(rate: Double, height: CGFloat) -> CGFloat {
    let inset: CGFloat = 6
    let clamped = min(max(rate, 0), 1)
    return height - inset - CGFloat(clamped) * max(1, height - inset * 2)
}
