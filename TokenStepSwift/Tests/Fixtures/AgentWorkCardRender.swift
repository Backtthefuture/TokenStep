import AppKit
import SwiftUI

@main
struct AgentWorkCardRender {
    @MainActor
    static func main() throws {
        try validateIsolatedAppSupport()
        try validatePopoverNavigation()
        try seedAppSupport()

        let appState = AppState()
        let outputURL = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["TOKENSTEP_AGENT_WORK_CARD_RENDER_PATH"]
                ?? "/tmp/tokenstep-agent-work-card.png"
        ).standardizedFileURL

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let content = ZStack {
            TokenStepBackdrop()
            TodayAgentWorkCard()
                .environmentObject(appState)
                .frame(width: 776)
                .padding(20)
        }
        .frame(width: 816)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.colorScheme, .light)
        .environment(\.isScreenshotRendering, true)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(
                domain: "AgentWorkCardRender",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to render Agent work card"]
            )
        }

        try png.write(to: outputURL, options: .atomic)
        print(outputURL.path)
    }

    @MainActor
    private static func validatePopoverNavigation() throws {
        let navigation = MainWindowNavigation(section: .history)
        navigation.select(PopoverAgentWorkStrip.destination)
        guard navigation.section == .today else {
            throw NSError(
                domain: "AgentWorkCardRender",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Popover Agent entry must select the Today section"]
            )
        }
    }

    private static func validateIsolatedAppSupport() throws {
        guard let override = ProcessInfo.processInfo.environment["TOKENSTEP_TEST_APP_SUPPORT_ROOT"],
              !override.isEmpty
        else {
            throw NSError(
                domain: "AgentWorkCardRender",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "TOKENSTEP_TEST_APP_SUPPORT_ROOT is required"]
            )
        }

        let expected = URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        guard AppPaths.appSupportRoot.standardizedFileURL == expected else {
            throw NSError(
                domain: "AgentWorkCardRender",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Fixture refused to use non-test App Support"]
            )
        }
    }

    @MainActor
    private static func seedAppSupport() throws {
        let works = makeAgentWorks()
        let daily = works.map { work in
            DailyUsage(
                date: work.date,
                tools: Dictionary(
                    uniqueKeysWithValues: work.sources.map { ($0.source, $0.tokens) }
                ),
                models: ["gpt-5.6-sol": work.totalTokens],
                totalTokens: work.totalTokens,
                cost: 0
            )
        }
        let codexTotal = works
            .flatMap(\.sources)
            .filter { $0.source == "Codex" }
            .map(\.tokens)
            .reduce(0, +)
        let hermesTotal = works
            .flatMap(\.sources)
            .filter { $0.source == "Hermes Agent" }
            .map(\.tokens)
            .reduce(0, +)
        let total = codexTotal + hermesTotal

        let snapshot = UsageSnapshot(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            timezone: "Asia/Shanghai",
            totals: UsageTotals(tokens: total, cost: 0, activeDays: works.count),
            daily: daily,
            agentWork: works,
            tools: [
                ToolUsage(
                    tool: "Codex",
                    tokens: codexTotal,
                    percent: total > 0 ? Double(codexTotal) * 100 / Double(total) : 0
                ),
                ToolUsage(
                    tool: "Hermes Agent",
                    tokens: hermesTotal,
                    percent: total > 0 ? Double(hermesTotal) * 100 / Double(total) : 0
                )
            ],
            models: [
                ModelUsage(model: "gpt-5.6-sol", tool: nil, tokens: total, percent: 100)
            ],
            sources: [
                "Codex": SourceInfo(
                    status: "ok",
                    files: 665,
                    records: 2_440,
                    accountingRevision: UsageCollector.codexAccountingRevision
                ),
                "Hermes Agent": SourceInfo(
                    status: "ok",
                    files: 12,
                    records: 149
                )
            ]
        )

        let settings = TokenStepSettings(
            dailyGoalTokens: 100_000_000,
            refreshIntervalSeconds: 0,
            historyDays: 30,
            theme: .green,
            autoUpdateEnabled: false,
            askBeforeDownloadingUpdates: true,
            requireVerifiedUpdates: true,
            tokenIslandEnabled: false,
            tokenIslandPlacement: .menuBar,
            showCodexQuota: false,
            showTokenRank: false,
            showExperimentalAgentSources: true,
            tokenRankUserID: "",
            language: .zhHans,
            skippedUpdateVersion: nil
        )

        try writeJSON(snapshot, to: AppPaths.usageJSON)
        try writeJSON(settings, to: AppPaths.settingsJSON)
    }

    private static func makeAgentWorks() -> [DailyAgentWork] {
        let calendar = Calendar(identifier: .gregorian)
        let todayKey = DateFormatter.tokenStepDay.string(from: Date())
        let today = DateFormatter.tokenStepDay.date(from: todayKey) ?? Date()
        let historicalTotals: [(codex: Int, hermes: Int)] = [
            (214_000_000, 8_400_000),
            (356_000_000, 11_800_000),
            (188_000_000, 6_900_000),
            (421_000_000, 13_600_000),
            (279_000_000, 9_700_000),
            (334_000_000, 12_200_000)
        ]

        var works: [DailyAgentWork] = []
        for offset in stride(from: 6, through: 1, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                continue
            }
            let totals = historicalTotals[6 - offset]
            works.append(
                historicalWork(
                    date: DateFormatter.tokenStepDay.string(from: date),
                    codexTokens: totals.codex,
                    hermesTokens: totals.hermes,
                    peakHour: 13 + (offset % 5)
                )
            )
        }
        works.append(todayWork(date: todayKey))
        return works
    }

    private static func todayWork(date: String) -> DailyAgentWork {
        let codexTokens = [
            64_000_000, 40_000_000, 49_000_000, 32_000_000,
            700_000, 16_000_000, 1_100_000, 7_000_000,
            500_000, 0, 6_000_000, 350_000,
            0, 800_000, 53_000_000, 4_000_000,
            300_000, 8_000_000, 45_000_000, 0,
            12_000_000, 0, 0, 0
        ]
        let hermesTokens = [
            600_000, 420_000, 510_000, 380_000,
            0, 750_000, 0, 260_000,
            0, 0, 0, 830_000,
            0, 0, 1_640_000, 0,
            0, 540_000, 2_300_000, 0,
            1_100_000, 0, 0, 0
        ]
        let missingCacheHours: Set<Int> = [3, 11, 15, 20]

        let buckets = (0..<24).map { hour -> AgentWorkHourBucket in
            var sources: [AgentWorkHourlySource] = []
            if codexTokens[hour] > 0 {
                sources.append(
                    hourlySource(
                        name: "Codex",
                        tokens: codexTokens[hour],
                        cacheRatio: 0.91 + Double(hour % 4) * 0.015,
                        cacheCoverageComplete: !missingCacheHours.contains(hour)
                    )
                )
            }
            if hermesTokens[hour] > 0 {
                sources.append(
                    hourlySource(
                        name: "Hermes Agent",
                        tokens: hermesTokens[hour],
                        cacheRatio: 0.84 + Double(hour % 3) * 0.025,
                        cacheCoverageComplete: !missingCacheHours.contains(hour)
                    )
                )
            }
            return AgentWorkHourBucket(hour: hour, sources: sources)
        }

        return work(
            date: date,
            buckets: buckets,
            modelRequestCount: 2_589,
            toolCallCount: 3_886
        )
    }

    private static func historicalWork(
        date: String,
        codexTokens: Int,
        hermesTokens: Int,
        peakHour: Int
    ) -> DailyAgentWork {
        let hours = [max(0, peakHour - 4), peakHour, min(23, peakHour + 4)]
        let codexParts = split(codexTokens)
        let hermesParts = split(hermesTokens)
        let buckets = (0..<24).map { hour -> AgentWorkHourBucket in
            guard let index = hours.firstIndex(of: hour) else {
                return AgentWorkHourBucket(hour: hour, sources: [])
            }
            return AgentWorkHourBucket(
                hour: hour,
                sources: [
                    hourlySource(
                        name: "Codex",
                        tokens: codexParts[index],
                        cacheRatio: 0.92,
                        cacheCoverageComplete: true
                    ),
                    hourlySource(
                        name: "Hermes Agent",
                        tokens: hermesParts[index],
                        cacheRatio: 0.86,
                        cacheCoverageComplete: true
                    )
                ]
            )
        }

        return work(
            date: date,
            buckets: buckets,
            modelRequestCount: max(60, (codexTokens + hermesTokens) / 190_000),
            toolCallCount: max(90, (codexTokens + hermesTokens) / 125_000)
        )
    }

    private static func work(
        date: String,
        buckets: [AgentWorkHourBucket],
        modelRequestCount: Int,
        toolCallCount: Int
    ) -> DailyAgentWork {
        let hourlySources = buckets.flatMap(\.sources)
        let sourceNames = Array(Set(hourlySources.map(\.source))).sorted()
        let sources = sourceNames.map { name in
            AgentWorkSource(
                source: name,
                tokens: hourlySources
                    .filter { $0.source == name }
                    .map(\.tokens)
                    .reduce(0, +),
                modelRequestCount: name == "Codex"
                    ? Int(Double(modelRequestCount) * 0.94)
                    : max(1, Int(Double(modelRequestCount) * 0.06)),
                toolCallCount: name == "Codex"
                    ? Int(Double(toolCallCount) * 0.96)
                    : max(1, Int(Double(toolCallCount) * 0.04))
            )
        }
        let totalTokens = hourlySources.map(\.tokens).reduce(0, +)
        let inputTokens = hourlySources.map(\.inputTokens).reduce(0, +)
        let cachedInputTokens = hourlySources.map(\.cachedInputTokens).reduce(0, +)
        let outputTokens = hourlySources.map(\.outputTokens).reduce(0, +)
        let activeHours = buckets.filter { $0.totalTokens > 0 }.count

        return DailyAgentWork(
            date: date,
            totalTokens: totalTokens,
            activeHours: activeHours,
            modelRequestCount: modelRequestCount,
            toolCallCount: toolCallCount,
            sources: sources,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            cacheCoverageComplete: hourlySources
                .filter { $0.tokens > 0 }
                .allSatisfy(\.cacheCoverageComplete),
            hourlyBuckets: buckets,
            unbucketedTokens: 0
        )
    }

    private static func hourlySource(
        name: String,
        tokens: Int,
        cacheRatio: Double,
        cacheCoverageComplete: Bool
    ) -> AgentWorkHourlySource {
        let output = max(1, Int(Double(tokens) * 0.025))
        let input = max(0, tokens - output)
        let cached = min(input, max(0, Int(Double(input) * cacheRatio)))
        return AgentWorkHourlySource(
            source: name,
            tokens: tokens,
            inputTokens: input,
            cachedInputTokens: cached,
            outputTokens: output,
            cacheCoverageComplete: cacheCoverageComplete
        )
    }

    private static func split(_ value: Int) -> [Int] {
        let first = Int(Double(value) * 0.28)
        let second = Int(Double(value) * 0.47)
        return [first, second, value - first - second]
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
