import AppKit
import SwiftUI

@main
struct PopoverPanelRender {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        try validateIsolatedAppSupport()
        try seedEmptyAppSupport()
        if let iconPath = ProcessInfo.processInfo.environment["TOKENSTEP_ICON_PATH"],
           let icon = NSImage(contentsOfFile: iconPath) {
            NSApp.applicationIconImage = icon
        }

        let theme: TokenStepTheme
        switch ProcessInfo.processInfo.environment["TOKENSTEP_POPOVER_THEME"] {
        case "voyage": theme = .voyage
        case "event_horizon": theme = .eventHorizon
        default: theme = .green
        }
        let chapter = ProcessInfo.processInfo.environment["TOKENSTEP_ODYSSEY_CHAPTER"]
            .flatMap(TokenStepOdysseyChapter.init(rawValue:))
            ?? .aegeanMist
        let fixture = ProcessInfo.processInfo.environment["TOKENSTEP_POPOVER_FIXTURE"] ?? "standard"
        let language = ProcessInfo.processInfo.environment["TOKENSTEP_POPOVER_LANGUAGE"]
            .flatMap(TokenStepLanguage.init(rawValue:))
            ?? .zhHans
        let showsRank = ProcessInfo.processInfo.environment["TOKENSTEP_POPOVER_RANK"] != "hidden"
        let showsQuotas = ProcessInfo.processInfo.environment["TOKENSTEP_POPOVER_QUOTAS"] != "hidden"
        let updateState = ProcessInfo.processInfo.environment["TOKENSTEP_POPOVER_UPDATE_STATE"] ?? "idle"
        let rank = ProcessInfo.processInfo.environment["TOKENSTEP_POPOVER_RANK"] == "chase" ? chaseRank() : fixtureRank()
        let update = fixtureUpdate()
        let appState = AppState()
        appState.installRenderFixture(
            snapshot: fixtureSnapshot(fixture),
            settings: fixtureSettings(
                theme: theme,
                chapter: chapter,
                showsRank: showsRank,
                showsQuotas: showsQuotas,
                language: language
            ),
            quotas: showsQuotas
                ? (ProcessInfo.processInfo.environment["TOKENSTEP_POPOVER_QUOTAS"] == "many" ? manyQuotas() : fixtureQuotas())
                : [:],
            tokenRank: showsRank ? rank.leaderboard : nil,
            agentWorkRankIdentity: showsRank ? rank.identity : nil,
            updateCheckPhase: fixtureUpdatePhase(updateState, update: update),
            availableUpdate: updateState == "available" ? update : nil
        )

        let output = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["TOKENSTEP_POPOVER_RENDER_PATH"]
                ?? "/tmp/tokenstep-popover-v0.2.7.png"
        )
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let content = PopoverPanelView()
            .environmentObject(appState)
            .environment(\.colorScheme, theme.colorScheme)
            .environment(\.isScreenshotRendering, true)
            .fixedSize(horizontal: false, vertical: true)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "PopoverPanelRender", code: 1)
        }
        try png.write(to: output, options: .atomic)
        guard bitmap.pixelsWide == Int(CompactPopoverStyle.width * 2), bitmap.pixelsHigh >= 300 else {
            throw NSError(domain: "PopoverPanelRender", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected render size: \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)"
            ])
        }
        print("v0.2.7: \(bitmap.pixelsWide)x\(bitmap.pixelsHigh) -> \(output.path)")
    }

    private static func validateIsolatedAppSupport() throws {
        guard let override = ProcessInfo.processInfo.environment["TOKENSTEP_TEST_APP_SUPPORT_ROOT"],
              !override.isEmpty
        else {
            throw NSError(domain: "PopoverPanelRender", code: 3)
        }
        let expected = URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        guard AppPaths.appSupportRoot.standardizedFileURL == expected else {
            throw NSError(domain: "PopoverPanelRender", code: 4)
        }
    }

    @MainActor
    private static func seedEmptyAppSupport() throws {
        try writeJSON(UsageSnapshot.empty, to: AppPaths.usageJSON)
        try writeJSON(TokenStepSettings.defaults, to: AppPaths.settingsJSON)
    }

    private static func fixtureSnapshot(_ fixture: String) -> UsageSnapshot {
        let today = DateFormatter.tokenStepDay.string(from: Date())
        var total = 428_000_000
        var tools = ["Codex": 320_000_000, "Claude Code": 82_000_000, "Cursor": 26_000_000]
        var models = ["gpt-5.2-codex": 310_000_000, "claude-opus-4.1": 82_000_000, "gemini-2.5-pro": 36_000_000]
        var sources = [
            AgentWorkSource(source: "Codex", tokens: 320_000_000, modelRequestCount: 612, toolCallCount: 228),
            AgentWorkSource(source: "Claude Code", tokens: 82_000_000, modelRequestCount: 156, toolCallCount: 66),
            AgentWorkSource(source: "Cursor", tokens: 26_000_000, modelRequestCount: 56, toolCallCount: 18)
        ]
        var cost = 23.9

        switch fixture {
        case "models6", "english":
            models = [
                "gpt-5.2-codex": 200_000_000,
                "claude-opus-4.1": 100_000_000,
                "gemini-2.5-pro": 60_000_000,
                "deepseek-v4": 30_000_000,
                "grok-4": 20_000_000,
                "unknown": 18_000_000
            ]
        case "classic4":
            total = 120_000_000
            tools = ["Codex": 93_000_000, "ZCode": 27_000_000]
            models = [
                "gpt-5.2-codex": 55_000_000,
                "claude-opus-4.1": 28_000_000,
                "gemini-2.5-pro": 19_000_000,
                "grok-4": 11_000_000,
                "deepseek-v4": 7_000_000
            ]
            sources = [
                AgentWorkSource(source: "Codex", tokens: 93_000_000, modelRequestCount: 290, toolCallCount: 88),
                AgentWorkSource(source: "ZCode", tokens: 27_000_000, modelRequestCount: 84, toolCallCount: 19)
            ]
            cost = 8.4
        case "waiting":
            models = [:]
        case "zero":
            total = 0
            tools = [:]
            models = [:]
            sources = []
            cost = 0
        case "long":
            total = 10_000_000_000
            tools = ["Codex": 7_200_000_000, "Hermes Agent": 1_800_000_000, "Cursor": 999_999_999]
            models = [
                "openai-gpt-5.2-codex-ultra-long-context-reasoning-preview": 4_500_000_000,
                "unknown": 2_500_000_000,
                "anthropic-claude-opus-4.1-extended-thinking-202608": 1_500_000_000,
                "grok-4-heavy": 800_000_000,
                "gemini-2.5-pro-exp-very-long-model-name": 699_999_999
            ]
            sources = [
                AgentWorkSource(source: "Codex with an unusually long source name", tokens: 7_200_000_000, modelRequestCount: 8_888, toolCallCount: 3_001),
                AgentWorkSource(source: "Hermes Agent", tokens: 1_800_000_000, modelRequestCount: 1_204, toolCallCount: 488),
                AgentWorkSource(source: "Cursor", tokens: 999_999_999, modelRequestCount: 710, toolCallCount: 202)
            ]
            cost = 8_888.88
        case "agents5":
            models = [
                "gpt-5.2-codex": 200_000_000,
                "claude-opus-4.1": 100_000_000,
                "gemini-2.5-pro": 60_000_000,
                "deepseek-v4": 30_000_000,
                "grok-4": 20_000_000,
                "unknown": 18_000_000
            ]
            sources = [
                AgentWorkSource(source: "Codex", tokens: 240_000_000, modelRequestCount: 480, toolCallCount: 180),
                AgentWorkSource(source: "ZCode", tokens: 80_000_000, modelRequestCount: 160, toolCallCount: 60),
                AgentWorkSource(source: "Hermes Agent", tokens: 55_000_000, modelRequestCount: 110, toolCallCount: 40),
                AgentWorkSource(source: "Cursor", tokens: 33_000_000, modelRequestCount: 66, toolCallCount: 24),
                AgentWorkSource(source: "Claude Code", tokens: 20_000_000, modelRequestCount: 40, toolCallCount: 14)
            ]
            tools = Dictionary(uniqueKeysWithValues: sources.map { ($0.source, $0.tokens) })
        default:
            break
        }

        let daily = DailyUsage(
            date: today,
            tools: tools,
            models: models,
            modelCosts: [:],
            totalTokens: total,
            cost: cost
        )
        let work = DailyAgentWork(
            date: today,
            totalTokens: total,
            activeHours: 8,
            modelRequestCount: total > 0 ? 824 : 0,
            toolCallCount: total > 0 ? 312 : 0,
            sources: sources,
            inputTokens: total,
            cachedInputTokens: total * 7 / 10,
            outputTokens: total / 50,
            cacheCoverageComplete: true
        )
        return UsageSnapshot(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            timezone: "Asia/Shanghai",
            totals: UsageTotals(tokens: total, cost: cost, activeDays: total > 0 ? 58 : 0),
            daily: [daily],
            agentWork: [work],
            tools: [],
            models: [],
            sources: [:]
        )
    }

    private static func fixtureSettings(
        theme: TokenStepTheme,
        chapter: TokenStepOdysseyChapter,
        showsRank: Bool,
        showsQuotas: Bool,
        language: TokenStepLanguage
    ) -> TokenStepSettings {
        TokenStepSettings(
            dailyGoalTokens: 1_000_000_000,
            refreshIntervalSeconds: 300,
            historyDays: 180,
            theme: theme,
            autoUpdateEnabled: false,
            askBeforeDownloadingUpdates: true,
            requireVerifiedUpdates: true,
            tokenIslandEnabled: false,
            tokenIslandPlacement: .menuBar,
            enabledQuotaProviders: showsQuotas ? Set(QuotaProviderID.allCases) : [],
            cursorQuotaEnabled: showsQuotas,
            cursorCodeSignalEnabled: false,
            agentWorkRankVisibility: showsRank ? .visible : .hidden,
            showExperimentalAgentSources: true,
            language: language,
            skippedUpdateVersion: nil,
            classicTheme: .green,
            odysseyChapter: chapter
        )
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

    /// Mid-board: the viewer at #35 chasing #34, with the podium ahead.
    private static func chaseRank() -> (leaderboard: TokenRankLeaderboard, identity: AgentWorkRankIdentity) {
        let identity = AgentWorkRankIdentity(id: 42, name: "Agent 黄叔", avatarURL: nil, lastSyncedAt: Date())
        let rows: [(Int, Int, String, Int)] = [
            (1, 1, "十七°", 860_255_773), (2, 2, "开水庆余年", 716_395_709), (3, 3, "柳间君", 666_412_269),
            (34, 34, "ancson", 32_630_000), (35, 42, identity.name, 28_510_000), (36, 36, "Susan", 20_122_373)
        ]
        return (
            TokenRankLeaderboard(
                fetchedAt: Date().addingTimeInterval(-2 * 60),
                range: "today",
                client: "all",
                usageMode: "all",
                totalTokens: 8_193_118_395,
                totalRankedUsers: 88,
                topLimit: 100,
                entries: rows.map {
                    TokenRankEntry(rank: $0.0, userID: $0.1, name: $0.2, avatarURL: nil, totalTokens: $0.3, callCount: 0, sessionCount: 0, clients: [:], models: [:])
                }
            ),
            identity
        )
    }

    /// Six providers: one critical, one running out early, the rest calm.
    private static func manyQuotas() -> [QuotaProviderID: ProviderQuota] {
        let now = Date()
        func quota(_ provider: QuotaProviderID, _ windows: [QuotaWindow]) -> ProviderQuota {
            ProviderQuota(provider: provider, windows: windows, status: .available, fetchedAt: now.addingTimeInterval(-7 * 60), message: nil)
        }
        return [
            .codex: quota(.codex, [
                QuotaWindow(kind: .fiveHour, usedPercent: 96, resetsAt: now.addingTimeInterval(2 * 3600)),
                QuotaWindow(kind: .sevenDay, usedPercent: 89, resetsAt: now.addingTimeInterval(34.5 * 3600))
            ]),
            .claude: quota(.claude, [
                QuotaWindow(kind: .fiveHour, usedPercent: 58, resetsAt: now.addingTimeInterval(3 * 3600)),
                QuotaWindow(kind: .sevenDay, usedPercent: 71, resetsAt: now.addingTimeInterval(96 * 3600))
            ]),
            .grok: quota(.grok, [QuotaWindow(kind: .monthlyCredits, usedPercent: 32, resetsAt: now.addingTimeInterval(9 * 86_400))]),
            .glm: quota(.glm, [QuotaWindow(kind: .monthlyCredits, usedPercent: 24, resetsAt: now.addingTimeInterval(6 * 86_400))]),
            .kimi: quota(.kimi, [QuotaWindow(kind: .weekly, usedPercent: 12, resetsAt: now.addingTimeInterval(5 * 86_400))]),
            .cursor: quota(.cursor, [QuotaWindow(kind: .cursorModels, usedPercent: 45, resetsAt: now.addingTimeInterval(6 * 86_400))])
        ]
    }

    private static func fixtureUpdatePhase(
        _ state: String,
        update: AvailableUpdate
    ) -> UpdateCheckPhase {
        let checkedAt = Date(timeIntervalSince1970: 1_787_628_600)
        switch state {
        case "checking": return .checking
        case "up-to-date": return .upToDate(checkedAt: checkedAt)
        case "available": return .available(update, checkedAt: checkedAt)
        case "failed": return .failed(checkedAt: checkedAt, message: L("检查更新失败，请稍后再试。"))
        default: return .idle
        }
    }

    private static func fixtureUpdate() -> AvailableUpdate {
        AvailableUpdate(
            version: "0.2.6",
            tagName: "v0.2.6",
            title: "TokenStep 0.2.6",
            notes: "新增浮层更新入口与全局自动更新提醒",
            pageURL: URL(string: "https://example.com/release")!,
            assetURL: URL(string: "https://example.com/TokenStep.dmg")!,
            assetName: "TokenStep-0.2.6.dmg",
            assetSize: 12_000_000
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
