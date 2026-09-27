import AppKit
import SwiftUI

@main
struct TodayDashboardRender {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        try validateIsolatedAppSupport()
        let scenario = ProcessInfo.processInfo.environment["TOKENSTEP_TODAY_SCENARIO"] ?? "zh-normal"
        let theme = ProcessInfo.processInfo.environment["TOKENSTEP_TODAY_THEME"] == "voyage"
            ? TokenStepTheme.voyage
            : TokenStepTheme.green
        try seedAppSupport(scenario: scenario, theme: theme)
        if let iconPath = ProcessInfo.processInfo.environment["TOKENSTEP_ICON_PATH"],
           let icon = NSImage(contentsOfFile: iconPath) {
            NSApp.applicationIconImage = icon
        }
        let appState = AppState()
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TOKENSTEP_TODAY_RENDER_PATH"] ?? "/tmp/tokenstep-today.png")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

        let isNarrow = scenario == "zh-narrow"
        let content = Group {
            if let section = ProcessInfo.processInfo.environment["TOKENSTEP_TODAY_SECTION"],
               section.hasPrefix("settings") {
                SettingsView(
                    captureMode: true,
                    capturePane: SettingsPane(rawValue: String(section.dropFirst("settings-".count)))
                )
                .environmentObject(appState)
            } else if isNarrow {
                ZStack {
                    TokenStepBackdrop()
                    TodayView().environmentObject(appState).padding(16)
                }
                .frame(width: 720)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                DashboardScreenshotView(
                    section: ProcessInfo.processInfo.environment["TOKENSTEP_TODAY_SECTION"] == "history" ? .history : .today
                )
                    .environmentObject(appState)
            }
        }
        .environment(\.colorScheme, theme.colorScheme)
        .environment(\.isScreenshotRendering, true)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "TodayDashboardRender", code: 1)
        }
        try png.write(to: output, options: .atomic)
        let isSettings = ProcessInfo.processInfo.environment["TOKENSTEP_TODAY_SECTION"]?.hasPrefix("settings") == true
        let expectedWidth = isSettings ? 1_840 : (isNarrow ? 1_440 : 2_000)
        guard bitmap.pixelsWide == expectedWidth, bitmap.pixelsHigh > (isSettings ? 400 : 900) else {
            throw NSError(domain: "TodayDashboardRender", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected render size: \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)"
            ])
        }
        print("\(scenario): \(bitmap.pixelsWide)x\(bitmap.pixelsHigh) -> \(output.path)")
    }

    private static func validateIsolatedAppSupport() throws {
        guard let override = ProcessInfo.processInfo.environment["TOKENSTEP_TEST_APP_SUPPORT_ROOT"], !override.isEmpty else {
            throw NSError(domain: "TodayDashboardRender", code: 3)
        }
        let expected = URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        guard AppPaths.appSupportRoot.standardizedFileURL == expected else {
            throw NSError(domain: "TodayDashboardRender", code: 4)
        }
    }

    @MainActor
    private static func seedAppSupport(scenario: String, theme: TokenStepTheme) throws {
        let today = DateFormatter.tokenStepDay.string(from: Date())
        let language: TokenStepLanguage = scenario == "en-normal" ? .en : .zhHans
        let models: [String: Int]
        let costs: [String: Double]
        let total: Int

        switch scenario {
        case "zh-empty":
            models = [:]; costs = [:]; total = 0
        case "zh-waiting-details":
            models = [:]; costs = [:]; total = 615_000_000
        case "zh-long-large":
            models = [
                "vendor/extraordinarily-long-model-name-with-version-2026-08-21": 9_876_543_210,
                "unknown": 1_234_567_890,
                "model-3": 700_000_000,
                "model-4": 600_000_000,
                "model-5": 500_000_000,
                "model-6": 400_000_000,
                "model-7": 300_000_000
            ]
            costs = ["unknown": 12.34]
            total = 13_611_111_100
        default:
            models = ["gpt-5.2-codex": 462_000_000, "claude-opus-4.1": 104_000_000, "gemini-2.5-pro": 49_000_000]
            costs = ["gpt-5.2-codex": 487.20, "claude-opus-4.1": 108.60, "gemini-2.5-pro": 28.40]
            total = 615_000_000
        }

        let tools = total > 0 ? ["Codex": total * 87 / 100, "Cursor": total * 8 / 100, "Hermes Agent": total - total * 95 / 100] : [:]
        let daily = DailyUsage(date: today, tools: tools, models: models, modelCosts: costs, totalTokens: total, cost: costs.values.reduce(0, +))
        // Three clients over the hours so far, weighted like a working day.
        let weights = [2, 1, 0, 0, 0, 0, 0, 0, 1, 4, 7, 9, 8]
        let weightSum = weights.reduce(0, +)
        func hourly(_ total: Int) -> [AgentWorkHourBucket] {
            guard total > 0 else { return [] }
            return weights.enumerated().compactMap { hour, weight in
                guard weight > 0 else { return nil }
                let tokens = total * weight / weightSum
                return AgentWorkHourBucket(hour: hour, sources: [
                    ("Codex", 87), ("Cursor", 8), ("Hermes Agent", 5)
                ].map { source, share in
                    AgentWorkHourlySource(
                        source: source,
                        tokens: tokens * share / 100,
                        inputTokens: tokens * share / 100,
                        cachedInputTokens: tokens * share * 97 / 10_000,
                        outputTokens: tokens * share / 26_000,
                        cacheCoverageComplete: true
                    )
                })
            }
        }
        let hourlySources = hourly(total)
        let work = DailyAgentWork(
            date: today,
            totalTokens: total,
            activeHours: total > 0 ? 10 : 0,
            modelRequestCount: total > 0 ? 3_324 : 0,
            toolCallCount: total > 0 ? 312 : 0,
            sources: [],
            inputTokens: total > 0 ? 612_000_000 : 0,
            cachedInputTokens: total > 0 ? 594_000_000 : 0,
            outputTokens: total > 0 ? 2_370_000 : 0,
            cacheCoverageComplete: total > 0,
            hourlyBuckets: hourlySources,
            unbucketedTokens: 0
        )

        // Five weeks of history for the heatmap and the goal streak; empty
        // scenarios keep none.
        var history: [DailyUsage] = []
        var yesterdayWork: DailyAgentWork?
        if total > 0 {
            let pattern = [1.3, 0.9, 1.1, 0.4, 0.0, 1.6, 1.2, 0.7, 1.05, 0.2, 1.4, 0.95, 1.1, 1.25]
            for offset in stride(from: 34, through: 1, by: -1) {
                guard let day = TokenStepClock.calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
                let tokens = Int(500_000_000 * pattern[offset % pattern.count])
                let key = DateFormatter.tokenStepDay.string(from: day)
                history.append(DailyUsage(date: key, tools: ["Codex": tokens], totalTokens: tokens, cost: Double(tokens) / 1_000_000))
                if offset == 1 {
                    yesterdayWork = DailyAgentWork(
                        date: key,
                        totalTokens: tokens,
                        activeHours: 9,
                        modelRequestCount: 2_900,
                        toolCallCount: 280,
                        sources: [],
                        hourlyBuckets: hourly(tokens * 3 / 4)
                    )
                }
            }
        }
        let snapshot = UsageSnapshot(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            timezone: "Asia/Shanghai",
            totals: UsageTotals(
                tokens: total + history.map(\.totalTokens).reduce(0, +),
                cost: daily.cost,
                activeDays: (total > 0 ? 1 : 0) + history.filter { $0.totalTokens > 0 }.count
            ),
            daily: history + [daily],
            agentWork: [yesterdayWork, work].compactMap { $0 },
            tools: total > 0 ? [
                ToolUsage(tool: "Codex", tokens: 14_000_000_000, percent: 85.5),
                ToolUsage(tool: "Cursor", tokens: 1_600_000_000, percent: 9.8),
                ToolUsage(tool: "Hermes Agent", tokens: 765_000_000, percent: 4.7)
            ] : [],
            models: total > 0 ? [
                ModelUsage(model: "gpt-5.2-codex", tool: "Codex", tokens: 12_100_000_000, percent: 73.9),
                ModelUsage(model: "claude-opus-4.1", tool: "Claude Code", tokens: 2_900_000_000, percent: 17.7),
                ModelUsage(model: "gemini-2.5-pro", tool: "Cursor", tokens: 1_365_000_000, percent: 8.4)
            ] : [],
            sources: [:]
        )
        let settings = TokenStepSettings(
            dailyGoalTokens: 500_000_000,
            refreshIntervalSeconds: 0,
            historyDays: 30,
            theme: theme,
            autoUpdateEnabled: false,
            askBeforeDownloadingUpdates: true,
            requireVerifiedUpdates: true,
            tokenIslandEnabled: false,
            tokenIslandPlacement: .menuBar,
            enabledQuotaProviders: [],
            cursorQuotaEnabled: false,
            cursorCodeSignalEnabled: false,
            agentWorkRankVisibility: .hidden,
            showExperimentalAgentSources: true,
            language: language,
            skippedUpdateVersion: nil
        )
        try writeJSON(snapshot, to: AppPaths.usageJSON)
        try writeJSON(settings, to: AppPaths.settingsJSON)
        // Without these markers the theme migrations switch a classic-theme
        // fixture to Odyssey.
        for marker in [AppPaths.voyageThemeMigrationMarker, AppPaths.odysseyThemePackMigrationMarker] {
            try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: marker)
        }
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
