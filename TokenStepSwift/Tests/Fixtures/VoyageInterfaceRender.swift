import AppKit
import SwiftUI

@main
struct VoyageInterfaceRender {
    @MainActor private static var renderColorScheme: ColorScheme = .dark

    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        try validateIsolatedAppSupport()

        let snapshot = fixtureSnapshot()
        let chapter = ProcessInfo.processInfo.environment["TOKENSTEP_ODYSSEY_CHAPTER"]
            .flatMap(TokenStepOdysseyChapter.init(rawValue:))
            ?? .directorsCut
        let theme: TokenStepTheme
        switch ProcessInfo.processInfo.environment["TOKENSTEP_THEME_PACK"] {
        case "classic": theme = .green
        case "interstellar": theme = .eventHorizon
        default: theme = .voyage
        }
        let settings = fixtureSettings(theme: theme, chapter: chapter)
        renderColorScheme = settings.theme.colorScheme
        try writeJSON(snapshot, to: AppPaths.usageJSON)
        try writeJSON(settings, to: AppPaths.settingsJSON)

        if let iconPath = ProcessInfo.processInfo.environment["TOKENSTEP_ICON_PATH"],
           let icon = NSImage(contentsOfFile: iconPath) {
            NSApp.applicationIconImage = icon
        }

        let rank = fixtureRank()
        let appState = AppState()
        appState.installRenderFixture(
            snapshot: snapshot,
            settings: settings,
            quotas: fixtureQuotas(),
            tokenRank: rank.leaderboard,
            agentWorkRankIdentity: rank.identity
        )

        let outputDirectory = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["TOKENSTEP_VOYAGE_RENDER_DIR"]
                ?? "/tmp/tokenstep-voyage-interfaces"
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        try render(
            PopoverPanelView()
                .environmentObject(appState)
                .fixedSize(horizontal: false, vertical: true),
            named: "popover",
            in: outputDirectory
        )

        try render(
            DashboardScreenshotView(section: .today)
                .environmentObject(appState),
            named: "main-today",
            in: outputDirectory
        )
        try render(
            DashboardScreenshotView(section: .history)
                .environmentObject(appState),
            named: "main-history",
            in: outputDirectory
        )
        try render(
            DashboardScreenshotView(section: .privacy)
                .environmentObject(appState),
            named: "main-privacy",
            in: outputDirectory
        )

        for pane in SettingsPane.allCases {
            try render(
                SettingsView(captureMode: true, capturePane: pane)
                    .environmentObject(appState),
                named: "settings-\(pane.rawValue)",
                in: outputDirectory
            )
        }
        try render(
            SettingsView(captureMode: true)
                .environmentObject(appState),
            named: "settings-full",
            in: outputDirectory
        )

        try render(
            UpdateWindowView(update: fixtureUpdate())
                .environmentObject(appState),
            named: "update-window",
            in: outputDirectory
        )
        try render(
            TokenIslandPopoverWindowView(onHoverChanged: { _ in })
                .environmentObject(appState),
            named: "token-island-expanded",
            in: outputDirectory
        )
        try render(
            TokenIslandRingView(
                tokens: appState.today.totalTokens,
                lap: appState.todayLap,
                refreshing: false,
                theme: settings.theme,
                language: .zhHans
            ),
            named: "token-island-collapsed",
            in: outputDirectory
        )

        let today = appState.today
        let yesterday = snapshot.daily.dropLast().last
        try render(
            ShareDailyCardView(mode: .today, day: today, previousDay: yesterday)
                .environmentObject(appState),
            named: "share-daily",
            in: outputDirectory
        )
        if let rhythm = snapshot.rhythms.first,
           let rhythmDay = snapshot.daily.first(where: { $0.date == rhythm.date }) {
            try render(
                ShareRhythmCardView(day: rhythmDay, rhythm: rhythm, previousDay: snapshot.daily.dropLast(2).last)
                    .environmentObject(appState),
                named: "share-rhythm",
                in: outputDirectory
            )
        }
    }

    @MainActor
    private static func render<Content: View>(
        _ content: Content,
        named name: String,
        in directory: URL
    ) throws {
        let prepared = content
            .environment(\.colorScheme, renderColorScheme)
            .environment(\.isScreenshotRendering, true)
        let renderer = ImageRenderer(content: prepared)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "VoyageInterfaceRender", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unable to render \(name)"
            ])
        }

        let output = directory.appendingPathComponent("\(name).png")
        try png.write(to: output, options: .atomic)
        print("\(name): \(bitmap.pixelsWide)x\(bitmap.pixelsHigh) -> \(output.path)")
    }

    private static func fixtureSettings(
        theme: TokenStepTheme,
        chapter: TokenStepOdysseyChapter
    ) -> TokenStepSettings {
        TokenStepSettings(
            dailyGoalTokens: 500_000_000,
            refreshIntervalSeconds: 300,
            historyDays: 180,
            theme: theme,
            autoUpdateEnabled: true,
            askBeforeDownloadingUpdates: true,
            requireVerifiedUpdates: true,
            tokenIslandEnabled: true,
            tokenIslandPlacement: .automatic,
            enabledQuotaProviders: [.codex, .claude, .cursor],
            cursorQuotaEnabled: true,
            cursorCodeSignalEnabled: true,
            agentWorkRankVisibility: .visible,
            showExperimentalAgentSources: true,
            language: .zhHans,
            skippedUpdateVersion: nil,
            classicTheme: .green,
            odysseyChapter: chapter
        )
    }

    private static func fixtureSnapshot() -> UsageSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let start = calendar.startOfDay(for: Date())
        let days: [DailyUsage] = (0..<60).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: start) else { return nil }
            let dateText = DateFormatter.tokenStepDay.string(from: date)
            let factor = 48 + ((offset * 37) % 84)
            let total = offset == 0 ? 615_000_000 : factor * 4_300_000
            return DailyUsage(
                date: dateText,
                tools: [
                    "Codex": total * 72 / 100,
                    "Claude Code": total * 18 / 100,
                    "Cursor": total - total * 90 / 100
                ],
                models: [
                    "gpt-5.2-codex": total * 75 / 100,
                    "claude-opus-4.1": total * 17 / 100,
                    "gemini-2.5-pro": total - total * 92 / 100
                ],
                modelCosts: [
                    "gpt-5.2-codex": Double(total) / 1_000_000 * 0.79,
                    "claude-opus-4.1": Double(total) / 1_000_000 * 1.02
                ],
                totalTokens: total,
                cost: Double(total) / 1_000_000 * 0.98
            )
        }

        let today = days.last!
        let yesterday = days[days.count - 2]
        let hourlySources = (0..<24).map { hour in
            AgentWorkHourBucket(
                hour: hour,
                sources: hour < 13
                    ? [
                        AgentWorkHourlySource(
                            source: "Codex",
                            tokens: today.totalTokens / 13,
                            inputTokens: today.totalTokens / 14,
                            cachedInputTokens: today.totalTokens / 15,
                            outputTokens: today.totalTokens / 182,
                            cacheCoverageComplete: true
                        )
                    ]
                    : []
            )
        }
        let todayWork = DailyAgentWork(
            date: today.date,
            totalTokens: today.totalTokens,
            activeHours: 13,
            modelRequestCount: 3_324,
            toolCallCount: 312,
            sources: [
                AgentWorkSource(source: "Codex", tokens: 535_000_000, modelRequestCount: 2_840, toolCallCount: 268),
                AgentWorkSource(source: "Cursor", tokens: 49_200_000, modelRequestCount: 310, toolCallCount: 31),
                AgentWorkSource(source: "Hermes Agent", tokens: 30_800_000, modelRequestCount: 174, toolCallCount: 13)
            ],
            inputTokens: 612_000_000,
            cachedInputTokens: 594_000_000,
            outputTokens: 2_370_000,
            cacheCoverageComplete: true,
            hourlyBuckets: hourlySources,
            unbucketedTokens: 0
        )
        let yesterdayWork = DailyAgentWork(
            date: yesterday.date,
            totalTokens: yesterday.totalTokens,
            activeHours: 9,
            modelRequestCount: 2_184,
            toolCallCount: 206,
            sources: [AgentWorkSource(source: "Codex", tokens: yesterday.totalTokens, modelRequestCount: 2_184, toolCallCount: 206)]
        )
        let rhythmBuckets = (0..<24).map { hour in
            HourlyTokenBucket(
                hour: hour,
                tokens: (7...10).contains(hour) || (18...21).contains(hour)
                    ? yesterday.totalTokens / 8
                    : 0
            )
        }
        let rhythm = DailyRhythm(
            date: yesterday.date,
            buckets: rhythmBuckets,
            totalTokens: yesterday.totalTokens,
            peakHour: 20,
            peakTokens: yesterday.totalTokens / 8,
            activeHours: 8,
            firstActiveHour: 7,
            lastActiveHour: 21,
            primaryTag: .doublePeak,
            companionTag: .steadyCruise
        )

        return UsageSnapshot(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            timezone: "Asia/Shanghai",
            totals: UsageTotals(
                tokens: days.map(\.totalTokens).reduce(0, +),
                cost: days.map(\.cost).reduce(0, +),
                activeDays: days.count
            ),
            daily: days,
            rhythms: [rhythm],
            agentWork: [yesterdayWork, todayWork],
            tools: [],
            models: [],
            sources: [:]
        )
    }

    private static func fixtureQuotas() -> [QuotaProviderID: ProviderQuota] {
        let now = Date()
        return [
            .codex: ProviderQuota(
                provider: .codex,
                windows: [
                    QuotaWindow(kind: .fiveHour, usedPercent: 18, remaining: 82, total: 100, resetsAt: now.addingTimeInterval(7_200)),
                    QuotaWindow(kind: .sevenDay, usedPercent: 36, remaining: 64, total: 100, resetsAt: now.addingTimeInterval(259_200))
                ],
                status: .available,
                fetchedAt: now,
                message: nil
            ),
            .claude: ProviderQuota(
                provider: .claude,
                windows: [
                    QuotaWindow(kind: .fiveHour, usedPercent: 41, remaining: 59, total: 100, resetsAt: now.addingTimeInterval(9_000)),
                    QuotaWindow(kind: .sevenDay, usedPercent: 24, remaining: 76, total: 100, resetsAt: now.addingTimeInterval(345_600))
                ],
                status: .available,
                fetchedAt: now,
                message: nil
            ),
            .cursor: ProviderQuota(
                provider: .cursor,
                windows: [
                    QuotaWindow(kind: .cursorModels, usedPercent: 67, remaining: 33, total: 100, resetsAt: now.addingTimeInterval(172_800)),
                    QuotaWindow(kind: .otherModels, usedPercent: 12, remaining: 88, total: 100, resetsAt: now.addingTimeInterval(172_800))
                ],
                status: .available,
                fetchedAt: now,
                message: nil
            )
        ]
    }

    private static func fixtureRank() -> (leaderboard: TokenRankLeaderboard, identity: AgentWorkRankIdentity) {
        let identity = AgentWorkRankIdentity(
            id: 42,
            name: "Agent 黄叔",
            avatarURL: nil,
            lastSyncedAt: Date()
        )
        let entry = TokenRankEntry(
            rank: 1,
            userID: identity.id,
            name: identity.name,
            avatarURL: nil,
            totalTokens: 6_932_000_000,
            callCount: 8_124,
            sessionCount: 286,
            clients: ["codex": 6_570_000_000, "cursor": 362_000_000],
            models: ["gpt-5.2-codex": 5_800_000_000]
        )
        return (
            TokenRankLeaderboard(
                fetchedAt: Date().addingTimeInterval(-9 * 60),
                range: "today",
                client: "all",
                usageMode: "total_token_usage",
                totalTokens: 20_971_000_000,
                totalRankedUsers: 105,
                topLimit: 100,
                entries: [entry]
            ),
            identity
        )
    }

    private static func fixtureUpdate() -> AvailableUpdate {
        AvailableUpdate(
            version: "0.2.4",
            tagName: "v0.2.4",
            title: "TokenStep 0.2.4",
            notes: "- 经典与奥德赛主题皮肤包\n- 奥德赛四个视觉篇章\n- 全界面电影母题与横向浮窗",
            pageURL: URL(string: "https://example.com/tokenstep")!,
            assetURL: URL(string: "https://example.com/TokenStep-0.2.4.dmg")!,
            assetName: "TokenStep-0.2.4.dmg",
            assetSize: 18_400_000
        )
    }

    private static func validateIsolatedAppSupport() throws {
        guard let override = ProcessInfo.processInfo.environment["TOKENSTEP_TEST_APP_SUPPORT_ROOT"],
              !override.isEmpty else {
            throw NSError(domain: "VoyageInterfaceRender", code: 2)
        }
        let expected = URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        guard AppPaths.appSupportRoot.standardizedFileURL == expected else {
            throw NSError(domain: "VoyageInterfaceRender", code: 3)
        }
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
