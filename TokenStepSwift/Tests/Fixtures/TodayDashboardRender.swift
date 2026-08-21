import AppKit
import SwiftUI

@main
struct TodayDashboardRender {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        try validateIsolatedAppSupport()
        let scenario = ProcessInfo.processInfo.environment["TOKENSTEP_TODAY_SCENARIO"] ?? "zh-normal"
        try seedAppSupport(scenario: scenario)
        let appState = AppState()
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TOKENSTEP_TODAY_RENDER_PATH"] ?? "/tmp/tokenstep-today.png")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

        let isNarrow = scenario == "zh-narrow"
        let content = Group {
            if isNarrow {
                ZStack {
                    TokenStepBackdrop()
                    TodayView().environmentObject(appState).padding(16)
                }
                .frame(width: 720)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                DashboardScreenshotView(section: .today)
                    .environmentObject(appState)
            }
        }
        .environment(\.colorScheme, .light)
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
        guard bitmap.pixelsWide == (isNarrow ? 1_440 : 2_000), bitmap.pixelsHigh > 900 else {
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
    private static func seedAppSupport(scenario: String) throws {
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
        let hourlySources = total > 0 ? (0..<13).map { hour in
            AgentWorkHourBucket(hour: hour, sources: [
                AgentWorkHourlySource(
                    source: "Codex",
                    tokens: total / 13,
                    inputTokens: total / 14,
                    cachedInputTokens: total / 15,
                    outputTokens: total / 182,
                    cacheCoverageComplete: true
                )
            ])
        } : []
        let work = DailyAgentWork(
            date: today,
            totalTokens: total,
            activeHours: total > 0 ? 13 : 0,
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
        let snapshot = UsageSnapshot(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            timezone: "Asia/Shanghai",
            totals: UsageTotals(tokens: total, cost: daily.cost, activeDays: total > 0 ? 1 : 0),
            daily: [daily],
            agentWork: [work],
            tools: [],
            models: [],
            sources: [:]
        )
        let settings = TokenStepSettings(
            dailyGoalTokens: 500_000_000,
            refreshIntervalSeconds: 0,
            historyDays: 30,
            theme: .green,
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
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
