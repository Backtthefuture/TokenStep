import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot = .empty
    @Published private(set) var settings: TokenStepSettings = .defaults
    @Published private(set) var isRefreshing = false
    @Published private(set) var autostartEnabled = false
    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var isRefreshingCodexQuota = false
    @Published private(set) var quotas: [QuotaProviderID: ProviderQuota] = [:]
    @Published private(set) var cursorCodeSignal: CursorCodeSignal?
    @Published private(set) var cursorCodeSignalError: String?
    @Published private(set) var isRefreshingTokenRank = false
    @Published private(set) var tokenRank: TokenRankLeaderboard?
    @Published private(set) var agentWorkRankIdentity: AgentWorkRankIdentity?
    @Published private(set) var tokenRankError: String?
    @Published private(set) var isDownloadingUpdate = false
    @Published private(set) var updateDownloadProgress = 0.0
    @Published private(set) var updateInstallStatus = L("准备更新")
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var lastUpdateCheckAt: Date?
    @Published private(set) var updateCheckPhase: UpdateCheckPhase = .idle
    @Published private(set) var updateDownloadedURL: URL?
    @Published private(set) var tokenIslandAvailable = TokenIslandDisplayDetector.isAvailable
    @Published private(set) var showsUsageRecalibrationNotice = false
    @Published var lastError: String?

    private var timer: Timer?
    private var foregroundTimer: Timer?
    private var updateCheckTimer: Timer?
    private var deferredUpdateCheckTask: Task<Void, Never>?
    private var updatePhaseResetTask: Task<Void, Never>?
    private var startupUpdateCheckPending = false
    private var updateCheckGate = UpdateCheckGate()
    private var foregroundRefreshSurfaces = Set<String>()
    private var pendingRefreshAfterCurrent = false
    private var pendingForcedRefresh = false
    private var lastQuotaRefreshAttemptAt: Date?
    private var lastCursorUsageRefreshAttemptAt: Date?
    private var lastRankRefreshAttemptAt: Date?
    private var lastAutomaticUsageRefreshAttemptAt: Date?
    private var lastUsageObservedAt: Date?
    private var ledgerSnapshot: UsageSnapshot = .empty
    private var isRefreshingCursorUsage = false

    init() {
        load()
        refreshIfSnapshotIsStale()
        applyDefaultAutostartIfNeeded()
        configureTimer()
        refreshCodexQuota()
        refreshTokenRank()
        scheduleDeferredUpdateCheck()
        configureUpdateCheckTimer()
    }

    deinit {
        timer?.invalidate()
        foregroundTimer?.invalidate()
        updateCheckTimer?.invalidate()
        deferredUpdateCheckTask?.cancel()
        updatePhaseResetTask?.cancel()
    }

    var today: DailyUsage {
        let key = DateFormatter.tokenStepDay.string(from: Date())
        return snapshot.daily.last(where: { $0.date == key })
            ?? DailyUsage(date: key, tools: [:], totalTokens: 0, cost: 0)
    }

    var todayAgentWork: DailyAgentWork {
        let key = DateFormatter.tokenStepDay.string(from: Date())
        return agentWork(for: key)
    }

    var sevenDayAgentAverage: Int {
        sevenDayAgentAverage(endingAt: DateFormatter.tokenStepDay.string(from: Date()))
    }

    var lastUpdateCheckAttemptAt: Date? {
        updateCheckGate.lastAttemptAt
    }

    var progress: Double {
        guard settings.dailyGoalTokens > 0 else { return 0 }
        return Double(today.totalTokens) / Double(settings.dailyGoalTokens)
    }

    var todayLap: TokenStepLapProgress {
        TokenStepLapProgress(tokens: today.totalTokens, goal: settings.dailyGoalTokens)
    }

    var monthAverage: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let endDate = calendar.startOfDay(for: Date())
        let values = (0..<30).map { offset -> Int in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: endDate) else {
                return 0
            }
            let key = DateFormatter.tokenStepDay.string(from: date)
            return snapshot.daily.last(where: { $0.date == key })?.totalTokens ?? 0
        }
        return values.reduce(0, +) / 30
    }

    var goalDays: Int {
        snapshot.daily.filter { $0.totalTokens >= settings.dailyGoalTokens }.count
    }

    var visibleHistoryRows: [DailyUsage] {
        Array(snapshot.daily.reversed())
    }

    var shouldShowTokenIsland: Bool {
        settings.tokenIslandPlacement != .menuBar
            && TokenIslandDisplayDetector.isAvailable(for: settings.tokenIslandPlacement, size: TokenIslandWindowPresenter.collapsedSize)
    }

    var tokenIslandStatus: String {
        switch settings.tokenIslandPlacement {
        case .menuBar:
            return L("菜单栏模式")
        case .automatic:
            return shouldShowTokenIsland ? L("自动：刘海旁") : L("自动：菜单栏")
        case .notchLeft:
            return shouldShowTokenIsland ? L("刘海左侧") : L("菜单栏模式")
        case .notchRight:
            return shouldShowTokenIsland ? L("刘海右侧") : L("菜单栏模式")
        }
    }

    var tokenIslandStatusDetail: String {
        if shouldShowTokenIsland {
            return L("鼠标移入后展开 Island")
        }
        if settings.tokenIslandPlacement == .menuBar {
            return L("仅使用右上角菜单栏入口")
        }
        return TokenIslandDisplayDetector.fallbackReason
    }

    var appearanceID: String {
        "\(settings.theme.id)-\(settings.classicTheme.id)-\(settings.odysseyChapter.id)-\(settings.language.resolved.id)"
    }

    var shouldShowAgentWorkRank: Bool {
        settings.agentWorkRankVisibility.shouldShow(hasLocalIdentity: agentWorkRankIdentity != nil)
    }

    func load() {
        defer { MemoryPressure.relieveAllocatorPressure() }
        let loadedSettings = DataService.loadSettingsForAppLaunch()
        TokenStepLocalization.apply(loadedSettings.language)
        TokenStepThemeRuntime.apply(
            loadedSettings.theme,
            odysseyChapter: loadedSettings.odysseyChapter
        )
        settings = loadedSettings
        snapshot = (try? DataService.loadSnapshot()) ?? .empty
        ledgerSnapshot = snapshot
        applyCursorOfficialUsageOverlay()
        showsUsageRecalibrationNotice = DataService.hasPendingUsageRecalibrationNotice
        if loadedSettings.enabledQuotaProviders.isEmpty {
            quotas = [:]
        }
        if !loadedSettings.cursorCodeSignalEnabled {
            cursorCodeSignal = nil
            cursorCodeSignalError = nil
        }
        if !loadedSettings.agentWorkRankVisibility.readsLocalIdentity {
            clearTokenRankState()
        } else {
            agentWorkRankIdentity = AgentWorkRankService.loadLocalIdentity()
            if loadedSettings.agentWorkRankVisibility == .automatic,
               agentWorkRankIdentity == nil {
                clearTokenRankState()
            }
        }
        autostartEnabled = AutostartService.isEnabled
    }

    func refresh(forceCollection: Bool = true) {
        guard !isRefreshing else {
            if forceCollection {
                pendingRefreshAfterCurrent = true
                pendingForcedRefresh = true
            }
            return
        }
        let refreshStartedAt = Date()
        if !forceCollection,
           EnergyRefreshPolicy.isFresh(
               lastAttemptAt: lastAutomaticUsageRefreshAttemptAt,
               ttl: EnergyRefreshPolicy.automaticRetryTTL(
                   requestedSeconds: settings.refreshIntervalSeconds
               ),
               now: refreshStartedAt
           ) {
            return
        }
        if !forceCollection {
            lastAutomaticUsageRefreshAttemptAt = refreshStartedAt
        }
        isRefreshing = true
        lastError = nil
        let historyDays = settings.historyDays
        Task {
            var outcome: CollectionRunOutcome = .unchanged
            var collectionSucceeded = false
            do {
                outcome = try await Task.detached(priority: .utility) {
                    try DataService.runCollectorInHelper(
                        historyDays: historyDays,
                        force: forceCollection
                    )
                }.value
                collectionSucceeded = true
            } catch {
                lastError = error.localizedDescription
            }
            if outcome != .unchanged {
                load()
            }
            if collectionSucceeded, outcome != .updatedWhileSourcesChanged {
                lastUsageObservedAt = Date()
            }
            applyCursorOfficialUsageOverlay()
            refreshCursorOfficialUsage()
            isRefreshing = false
            if pendingRefreshAfterCurrent {
                let force = pendingForcedRefresh
                pendingRefreshAfterCurrent = false
                pendingForcedRefresh = false
                refresh(forceCollection: force)
            }
        }
    }

    func refreshForForeground(now: Date = Date()) {
        let snapshotDate = UsageSnapshotRefreshPolicy.generatedDate(snapshot.generatedAt)
        let freshestObservation = [snapshotDate, lastUsageObservedAt]
            .compactMap { $0 }
            .max()
        if EnergyRefreshPolicy.shouldRefreshForForeground(
            generatedAt: freshestObservation,
            requestedSeconds: settings.refreshIntervalSeconds,
            now: now
        ) {
            refresh(forceCollection: false)
        }
        refreshCodexQuota(now: now)
        refreshCursorCodeSignal(now: now)
        refreshTokenRank()
        performUpdateCheck(trigger: .foreground, now: now)
    }

    func setForegroundRefreshSurface(_ identifier: String, visible: Bool) {
        if visible {
            foregroundRefreshSurfaces.insert(identifier)
            refreshForForeground()
        } else {
            foregroundRefreshSurfaces.remove(identifier)
        }
        configureForegroundTimer()
    }

    func refreshCodexQuota(force: Bool = false, now: Date = Date()) {
        refreshCursorOfficialUsage(force: force, now: now)
        let providers = settings.enabledQuotaProviders
        guard !providers.isEmpty else {
            quotas = [:]
            isRefreshingCodexQuota = false
            return
        }
        guard !isRefreshingCodexQuota else { return }
        if !force,
           EnergyRefreshPolicy.isFresh(
               lastAttemptAt: lastQuotaRefreshAttemptAt,
               ttl: EnergyRefreshPolicy.quotaTTL,
               now: now
           ) {
            return
        }
        lastQuotaRefreshAttemptAt = now
        isRefreshingCodexQuota = true
        Task {
            let fetched = await Task.detached(priority: .utility) {
                QuotaRefreshCoordinator.fetch(providers: providers)
            }.value
            for provider in providers {
                if let quota = fetched[provider] {
                    quotas[provider] = quota
                } else if quotas[provider]?.isAvailable != true {
                    quotas[provider] = .unavailable(provider)
                }
            }
            quotas = quotas.filter { providers.contains($0.key) }
            isRefreshingCodexQuota = false
        }
    }

    func refreshCursorCodeSignal(force: Bool = false, now: Date = Date()) {
        guard settings.cursorCodeSignalEnabled else {
            cursorCodeSignal = nil
            cursorCodeSignalError = nil
            return
        }
        Task {
            let result = await Task.detached(priority: .utility) {
                Result { try CursorCodeSignalService.read() }
            }.value
            switch result {
            case let .success(signal):
                cursorCodeSignal = signal
                cursorCodeSignalError = nil
            case .failure:
                if cursorCodeSignal == nil {
                    cursorCodeSignalError = L("Cursor 代码产出暂不可用")
                }
            }
        }
    }

    var hasAnyQuota: Bool {
        visibleQuotas.contains(where: \.isAvailable)
    }

    var showsQuotaColumn: Bool {
        !visibleQuotas.isEmpty
    }

    var visibleQuotas: [ProviderQuota] {
        let items = QuotaProviderID.allCases.compactMap { id -> ProviderQuota? in
            guard settings.enabledQuotaProviders.contains(id) else { return nil }
            guard let quota = quotas[id], quota.isAvailable else { return nil }
            return quota
        }
        return items.sorted { lhs, rhs in
            let left = quotaSortRank(lhs)
            let right = quotaSortRank(rhs)
            if left != right { return left < right }
            return false
        }
    }

    private func quotaSortRank(_ quota: ProviderQuota) -> Int {
        if quota.isAvailable && quota.isLow { return 0 }
        if !quota.isAvailable { return 1 }
        return 2
    }

    var hasLowQuotaWarning: Bool {
        visibleQuotas.contains { $0.isAvailable && $0.isLow }
    }

    var codexQuota: CodexQuotaSnapshot {
        quotas[.codex]?.asCodexSnapshot ?? .unavailable
    }

    var claudeQuota: CodexQuotaSnapshot {
        quotas[.claude]?.asCodexSnapshot ?? .unavailable
    }

    func quota(for tool: String) -> CodexQuotaSnapshot {
        if AgentSourceRegistry.matches(tool, family: "claude") {
            return claudeQuota
        }
        return codexQuota
    }

    func agentWork(for date: String) -> DailyAgentWork {
        snapshot.agentWork(for: date)
            ?? DailyAgentWork(
                date: date,
                totalTokens: 0,
                activeHours: 0,
                modelRequestCount: 0,
                toolCallCount: 0,
                sources: []
            )
    }

    func sevenDayAgentAverage(endingAt dateKey: String) -> Int {
        guard let endDate = DateFormatter.tokenStepDay.date(from: dateKey) else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let total = (0..<7).reduce(0) { partial, offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: endDate) else {
                return partial
            }
            let key = DateFormatter.tokenStepDay.string(from: date)
            return partial + agentWork(for: key).totalTokens
        }
        return total / 7
    }

    func clearError() {
        lastError = nil
    }

    func dismissUsageRecalibrationNotice() {
        DataService.acknowledgeUsageRecalibrationNotice()
        showsUsageRecalibrationNotice = false
    }

    func refreshTokenIslandAvailability() {
        tokenIslandAvailable = TokenIslandDisplayDetector.isAvailable(for: settings.tokenIslandPlacement, size: TokenIslandWindowPresenter.collapsedSize)
    }

    func setGoal(_ tokens: Int) {
        settings.dailyGoalTokens = max(1_000_000, tokens)
        saveSettingsAndReload()
    }

    func setRefreshInterval(_ seconds: Int) {
        settings.refreshIntervalSeconds = seconds
        saveSettingsAndReload()
        configureTimer()
        configureForegroundTimer()
    }

    func setTheme(_ theme: TokenStepTheme) {
        if theme == .voyage {
            settings.theme = .voyage
        } else {
            settings.classicTheme = theme
            settings.theme = theme
        }
        TokenStepThemeRuntime.apply(
            settings.theme,
            odysseyChapter: settings.odysseyChapter
        )
        saveSettingsAndReload()
    }

    func setThemePack(_ pack: TokenStepThemePack) {
        settings.theme = pack == .odyssey ? .voyage : settings.classicTheme
        TokenStepThemeRuntime.apply(
            settings.theme,
            odysseyChapter: settings.odysseyChapter
        )
        saveSettingsAndReload()
    }

    func setClassicTheme(_ theme: TokenStepTheme) {
        guard TokenStepTheme.classicCases.contains(theme) else { return }
        settings.classicTheme = theme
        if settings.themePack == .classic {
            settings.theme = theme
        }
        TokenStepThemeRuntime.apply(
            settings.theme,
            odysseyChapter: settings.odysseyChapter
        )
        saveSettingsAndReload()
    }

    func setOdysseyChapter(_ chapter: TokenStepOdysseyChapter) {
        settings.odysseyChapter = chapter
        TokenStepThemeRuntime.apply(
            settings.theme,
            odysseyChapter: settings.odysseyChapter
        )
        saveSettingsAndReload()
    }

    func setLanguage(_ language: TokenStepLanguage) {
        TokenStepLocalization.apply(language)
        settings.language = language
        saveSettingsAndReload()
        updateInstallStatus = L("准备更新")
    }

    func setTokenIslandEnabled(_ enabled: Bool) {
        setTokenIslandPlacement(enabled ? .automatic : .menuBar)
    }

    func setTokenIslandPlacement(_ placement: TokenIslandDisplayPlacement) {
        settings.tokenIslandPlacement = placement
        settings.tokenIslandEnabled = placement != .menuBar
        saveSettingsAndReload()
        refreshTokenIslandAvailability()
    }

    func setCodexQuotaVisible(_ visible: Bool) {
        if visible {
            settings.enabledQuotaProviders.formUnion([.codex, .claude])
        } else {
            settings.enabledQuotaProviders.subtract([.codex, .claude])
        }
        saveSettingsAndReload()
        if settings.showCodexQuota {
            refreshCodexQuota(force: true)
        } else {
            quotas = [:]
            isRefreshingCodexQuota = false
        }
    }

    func setQuotaProvider(_ id: QuotaProviderID, enabled: Bool, confirmNetworkAccess: Bool = true) {
        if enabled, id == .cursor, confirmNetworkAccess, !settings.cursorQuotaEnabled {
            let confirmed = confirmCursorNetworkAccess()
            if !confirmed { return }
        }
        settings.setQuotaProvider(id, enabled: enabled)
        saveSettingsAndReload()
        if settings.enabledQuotaProviders.isEmpty {
            quotas = [:]
            isRefreshingCodexQuota = false
            applyCursorOfficialUsageOverlay()
        } else {
            refreshCodexQuota(force: true)
        }
    }

    func hasQuotaSecret(_ id: QuotaProviderID) -> Bool {
        guard let account = id.secretAccount else { return false }
        return TokenStepSecrets.has(account)
    }

    func saveQuotaSecret(_ id: QuotaProviderID, value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let account = id.secretAccount else { return }
        if id == .kimi, trimmed.lowercased().hasPrefix("sk-") {
            lastError = L("Kimi 需要 OAuth，不要用开放平台 key")
            return
        }
        if id == .grok, trimmed.lowercased().hasPrefix("xai-") {
            lastError = L("Grok 需要 grok login，普通 xAI key 无效")
            return
        }
        TokenStepSecrets.set(account, value: trimmed)
        objectWillChange.send()
        if !settings.enabledQuotaProviders.contains(id) {
            setQuotaProvider(id, enabled: true, confirmNetworkAccess: false)
        } else {
            refreshCodexQuota(force: true)
        }
    }

    func clearQuotaSecret(_ id: QuotaProviderID) {
        guard let account = id.secretAccount else { return }
        TokenStepSecrets.delete(account)
        objectWillChange.send()
        refreshCodexQuota(force: true)
    }

    func revealQuotaCredentialFolder(_ id: QuotaProviderID) {
        let relative: String
        switch id {
        case .kimi: relative = ".kimi"
        case .grok: relative = ".grok"
        default: return
        }
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relative, isDirectory: true)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
        }
    }

    func openGrokLoginInTerminal() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"Terminal\" to activate",
            "-e", "tell application \"Terminal\" to do script \"grok login\""
        ]
        try? process.run()
    }

    func setCursorCodeSignalEnabled(_ enabled: Bool) {
        if enabled, !settings.cursorCodeSignalEnabled {
            let confirmed = confirmCursorLocalAccess()
            if !confirmed { return }
        }
        settings.cursorCodeSignalEnabled = enabled
        saveSettingsAndReload()
        refreshCursorCodeSignal(force: true)
    }

    func setHistoryDays(_ days: Int) {
        settings.historyDays = days
        saveSettingsAndReload()
        refresh()
    }

    func revealLocalDataInFinder() {
        let urls = [AppPaths.usageJSON, AppPaths.settingsJSON].filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        if urls.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting([AppPaths.appSupportRoot])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    func clearLocalUsageData() {
        let alert = NSAlert()
        alert.messageText = L("确认清除本地用量数据？")
        alert.informativeText = L("将删除 usage.json 与本地缓存，设置会保留。下次同步会重新采集。")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("清除"))
        alert.addButton(withTitle: L("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let removable = [
            AppPaths.usageJSON,
            AppPaths.collectorCacheJSON,
            AppPaths.collectionCheckpointJSON,
            AppPaths.codexIncrementalCacheSQLite,
            AppPaths.claudeQuotaCacheJSON,
            AppPaths.cursorQuotaCacheJSON,
            AppPaths.cursorUsageCacheJSON,
            AppPaths.glmQuotaCacheJSON,
            AppPaths.kimiQuotaCacheJSON,
            AppPaths.grokQuotaCacheJSON
        ]
        for url in removable {
            try? FileManager.default.removeItem(at: url)
        }
        snapshot = .empty
        ledgerSnapshot = .empty
        quotas = [:]
        cursorCodeSignal = nil
        lastError = L("已清除本地用量数据")
        refresh(forceCollection: true)
    }

    @discardableResult
    private func confirmCursorNetworkAccess() -> Bool {
        let alert = NSAlert()
        alert.messageText = L("开启 Cursor 额度？")
        alert.informativeText = L("会只读本机 Cursor 登录态，向 cursor.com 查询两档额度和官方用量事件。用量事件会计入圆环。登录态不落盘、不上传第三方。该接口非官方，可能随时失效。")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("开启"))
        alert.addButton(withTitle: L("取消"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    @discardableResult
    private func confirmCursorLocalAccess() -> Bool {
        let alert = NSAlert()
        alert.messageText = L("开启 Cursor 代码产出？")
        alert.informativeText = L("只读取本机 ai_code_hashes 的计数与模型名，不读取代码、摘要或文件路径。该表每天会被 Cursor 清空，TokenStep 不做历史留存。")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("开启"))
        alert.addButton(withTitle: L("取消"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    func setAgentWorkRankVisibility(_ visibility: AgentWorkRankVisibility) {
        settings.agentWorkRankVisibility = visibility
        saveSettingsAndReload()
        if shouldShowAgentWorkRank {
            refreshTokenRank(force: true)
        } else {
            clearTokenRankState()
        }
    }

    func setExperimentalAgentSourcesVisible(_ visible: Bool) {
        settings.showExperimentalAgentSources = visible
        saveSettingsAndReload()
        refresh()
    }

    func refreshTokenRank(force: Bool = false, now: Date = Date()) {
        guard settings.agentWorkRankVisibility.readsLocalIdentity else {
            clearTokenRankState()
            return
        }
        agentWorkRankIdentity = AgentWorkRankService.loadLocalIdentity()
        guard shouldShowAgentWorkRank else {
            clearTokenRankState()
            return
        }
        guard !isRefreshingTokenRank else { return }
        if !force {
            if EnergyRefreshPolicy.isFresh(
                lastAttemptAt: lastRankRefreshAttemptAt,
                ttl: EnergyRefreshPolicy.rankTTL,
                now: now
            ) {
                return
            }
            if let fetchedAt = tokenRank?.fetchedAt,
               now.timeIntervalSince(fetchedAt) < AgentWorkRankService.cacheTTL {
                return
            }
        }
        lastRankRefreshAttemptAt = now

        agentWorkRankIdentity = AgentWorkRankService.loadLocalIdentity()
        isRefreshingTokenRank = true
        Task {
            defer {
                isRefreshingTokenRank = false
            }
            do {
                let leaderboard = try await AgentWorkRankService.fetchLeaderboard()
                guard shouldShowAgentWorkRank else {
                    clearTokenRankState()
                    return
                }
                tokenRank = leaderboard
                tokenRankError = nil
            } catch {
                guard shouldShowAgentWorkRank else {
                    clearTokenRankState()
                    return
                }
                if tokenRank == nil {
                    tokenRankError = L("暂时无法读取榜单")
                } else {
                    tokenRankError = L("榜单同步失败，显示上次结果")
                }
            }
        }
    }

    func openTokenRankLeaderboardPage() {
        NSWorkspace.shared.open(AgentWorkRankService.leaderboardPageURL)
    }

    func openTokenRankUserPage() {
        NSWorkspace.shared.open(AgentWorkRankService.myPageURL)
    }

    func setAutoUpdateEnabled(_ enabled: Bool) {
        settings.autoUpdateEnabled = enabled
        saveSettingsAndReload()
        if enabled {
            startupUpdateCheckPending = false
            deferredUpdateCheckTask?.cancel()
            deferredUpdateCheckTask = nil
            configureUpdateCheckTimer()
            performUpdateCheck(trigger: .settingsEnabled)
        } else {
            startupUpdateCheckPending = false
            deferredUpdateCheckTask?.cancel()
            deferredUpdateCheckTask = nil
            updateCheckTimer?.invalidate()
            updateCheckTimer = nil
        }
    }

    func setAskBeforeDownloadingUpdates(_ enabled: Bool) {
        settings.askBeforeDownloadingUpdates = enabled
        saveSettingsAndReload()
    }

    func setRequireVerifiedUpdates(_ enabled: Bool) {
        settings.requireVerifiedUpdates = enabled
        saveSettingsAndReload()
    }

    func setAutostart(_ enabled: Bool) {
        do {
            try AutostartService.setEnabled(enabled)
            try markAutostartDefaultApplied()
            autostartEnabled = AutostartService.isEnabled
        } catch {
            lastError = error.localizedDescription
        }
    }

    func checkForUpdates(silent: Bool = false) {
        performUpdateCheck(trigger: silent ? .foreground : .manual)
    }

    private func performUpdateCheck(
        trigger: UpdateCheckTrigger,
        now: Date = Date()
    ) {
        guard updateCheckGate.begin(
            trigger: trigger,
            autoUpdateEnabled: settings.autoUpdateEnabled,
            now: now,
            startupCheckPending: startupUpdateCheckPending
        ) else {
            return
        }

        isCheckingForUpdates = true
        updatePhaseResetTask?.cancel()
        updatePhaseResetTask = nil
        updateCheckPhase = .checking
        if trigger.isManual {
            lastError = nil
        }
        LifecycleLogger.log(
            "Update check attempt trigger=\(trigger.rawValue) current=\(UpdateService.currentVersion)."
        )

        Task {
            do {
                let result = try await UpdateService.checkForUpdates()
                let checkedAt = Date()
                lastUpdateCheckAt = checkedAt
                let visibleUpdate = UpdateCheckPolicy.visibleUpdate(
                    from: result,
                    skippedVersion: settings.skippedUpdateVersion,
                    trigger: trigger
                )
                availableUpdate = visibleUpdate

                if let visibleUpdate {
                    updateCheckPhase = .available(visibleUpdate, checkedAt: checkedAt)
                    LifecycleLogger.log(
                        "Update check success trigger=\(trigger.rawValue) result=available version=\(visibleUpdate.version)."
                    )
                    if UpdatePresentationPolicy.shouldPresentWindow(
                        trigger: trigger,
                        update: visibleUpdate
                    ) {
                        LifecycleLogger.log(
                            "Presenting update window trigger=\(trigger.rawValue) version=\(visibleUpdate.version)."
                        )
                        UpdateWindowPresenter.shared.show(appState: self, update: visibleUpdate)
                    }
                } else {
                    updateCheckPhase = .upToDate(checkedAt: checkedAt)
                    if case let .available(update) = result,
                       settings.skippedUpdateVersion == update.version,
                       !trigger.isManual {
                        LifecycleLogger.log(
                            "Update check success trigger=\(trigger.rawValue) result=skipped version=\(update.version)."
                        )
                    } else {
                        LifecycleLogger.log(
                            "Update check success trigger=\(trigger.rawValue) result=up-to-date."
                        )
                    }
                    scheduleUpdatePhaseReset()
                }
            } catch {
                let failedAt = Date()
                let message = error.localizedDescription
                updateCheckPhase = .failed(checkedAt: failedAt, message: message)
                if trigger.isManual {
                    lastError = message
                }
                LifecycleLogger.log(
                    "Update check failure trigger=\(trigger.rawValue) error=\(message)."
                )
            }
            updateCheckGate.finish()
            isCheckingForUpdates = false
        }
    }

    func showUpdateDetails() {
        guard let availableUpdate else {
            checkForUpdates(silent: false)
            return
        }
        UpdateWindowPresenter.shared.show(appState: self, update: availableUpdate)
    }

    func installAvailableUpdate() {
        guard let update = availableUpdate, !isDownloadingUpdate else { return }
        LifecycleLogger.log(
            "Update install requested version=\(update.version) asset=\(update.assetName)."
        )
        isDownloadingUpdate = true
        updateDownloadProgress = 0
        updateInstallStatus = L("正在下载")
        updateDownloadedURL = nil
        lastError = nil
        Task {
            do {
                let url = try await UpdateService.downloadAndInstall(
                    update,
                    requireVerified: settings.requireVerifiedUpdates
                ) { [weak self] progress in
                    self?.updateDownloadProgress = progress
                }
                updateDownloadedURL = url
                updateDownloadProgress = 1
                updateInstallStatus = L("正在安装并重启")
                LifecycleLogger.log(
                    "Update installer launched version=\(update.version) dmg=\(url.path)."
                )
            } catch {
                lastError = error.localizedDescription
                updateInstallStatus = L("更新失败")
                isDownloadingUpdate = false
                LifecycleLogger.log(
                    "Update install failed version=\(update.version) error=\(error.localizedDescription)."
                )
            }
        }
    }

    func postponeUpdateNotice() {
        availableUpdate = nil
        updateCheckPhase = .idle
    }

#if TOKENSTEP_TESTING
    func installRenderFixture(
        snapshot: UsageSnapshot,
        settings: TokenStepSettings,
        quotas: [QuotaProviderID: ProviderQuota] = [:],
        tokenRank: TokenRankLeaderboard? = nil,
        agentWorkRankIdentity: AgentWorkRankIdentity? = nil,
        updateCheckPhase: UpdateCheckPhase = .idle,
        availableUpdate: AvailableUpdate? = nil
    ) {
        timer?.invalidate()
        foregroundTimer?.invalidate()
        updateCheckTimer?.invalidate()
        deferredUpdateCheckTask?.cancel()
        updatePhaseResetTask?.cancel()
        timer = nil
        foregroundTimer = nil
        updateCheckTimer = nil
        deferredUpdateCheckTask = nil
        updatePhaseResetTask = nil
        startupUpdateCheckPending = false
        updateCheckGate = UpdateCheckGate()
        TokenStepLocalization.apply(settings.language)
        TokenStepThemeRuntime.apply(
            settings.theme,
            odysseyChapter: settings.odysseyChapter
        )
        self.settings = settings
        self.snapshot = snapshot
        ledgerSnapshot = snapshot
        self.quotas = quotas
        self.tokenRank = tokenRank
        self.agentWorkRankIdentity = agentWorkRankIdentity
        tokenRankError = nil
        isRefreshingTokenRank = false
        isRefreshing = false
        isRefreshingCodexQuota = false
        self.availableUpdate = availableUpdate
        self.updateCheckPhase = updateCheckPhase
        isCheckingForUpdates = updateCheckPhase == .checking
        lastError = nil
        showsUsageRecalibrationNotice = false
    }
#endif

    func skipAvailableUpdate() {
        guard let version = availableUpdate?.version else { return }
        settings.skippedUpdateVersion = version
        availableUpdate = nil
        updateCheckPhase = .upToDate(checkedAt: lastUpdateCheckAt ?? Date())
        scheduleUpdatePhaseReset()
        saveSettingsAndReload()
    }

    func refreshCursorOfficialUsage(force: Bool = false, now: Date = Date()) {
        applyCursorOfficialUsageOverlay()
        guard settings.cursorQuotaEnabled else { return }
        guard !isRefreshingCursorUsage else { return }
        if !force,
           EnergyRefreshPolicy.isFresh(
               lastAttemptAt: lastCursorUsageRefreshAttemptAt,
               ttl: EnergyRefreshPolicy.quotaTTL,
               now: now
           ) {
            return
        }
        lastCursorUsageRefreshAttemptAt = now
        isRefreshingCursorUsage = true
        let historyDays = settings.historyDays
        Task {
            _ = await Task.detached(priority: .utility) {
                Result { try CursorUsageService.refresh(historyDays: historyDays) }
            }.value
            applyCursorOfficialUsageOverlay()
            isRefreshingCursorUsage = false
        }
    }

    private func applyCursorOfficialUsageOverlay() {
        guard settings.cursorQuotaEnabled,
              let cache = CursorUsageService.readCache(),
              cache.days.contains(where: { $0.totalTokens > 0 })
        else {
            snapshot = ledgerSnapshot
            return
        }
        snapshot = CursorUsageService.merge(ledgerSnapshot, days: cache.days)
    }

    private func saveSettingsAndReload() {
        do {
            try DataService.saveSettings(settings)
            let loadedSettings = DataService.loadSettings()
            TokenStepLocalization.apply(loadedSettings.language)
            TokenStepThemeRuntime.apply(
                loadedSettings.theme,
                odysseyChapter: loadedSettings.odysseyChapter
            )
            settings = loadedSettings
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func clearTokenRankState() {
        tokenRank = nil
        agentWorkRankIdentity = nil
        tokenRankError = nil
        isRefreshingTokenRank = false
    }

    private func configureTimer() {
        timer?.invalidate()
        timer = nil
        guard let interval = EnergyRefreshPolicy.backgroundInterval(
            requestedSeconds: settings.refreshIntervalSeconds,
            powerSource: TokenStepPowerState.source,
            lowPowerMode: TokenStepPowerState.lowPowerModeEnabled
        ) else {
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refresh(forceCollection: false)
                self.refreshCodexQuota()
                self.refreshCursorCodeSignal()
                self.refreshTokenRank()
                self.configureTimer()
            }
        }
        timer?.tolerance = min(TimeInterval(interval) * 0.1, 60)
    }

    private func configureForegroundTimer() {
        foregroundTimer?.invalidate()
        foregroundTimer = nil
        guard !foregroundRefreshSurfaces.isEmpty,
              let interval = EnergyRefreshPolicy.foregroundTickInterval(
                  requestedSeconds: settings.refreshIntervalSeconds
              )
        else {
            return
        }
        foregroundTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(interval),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshForForeground()
                self.configureForegroundTimer()
            }
        }
        foregroundTimer?.tolerance = min(TimeInterval(interval) * 0.1, 10)
    }

    private func refreshIfSnapshotIsStale() {
        guard let reason = UsageSnapshotRefreshPolicy.reason(
            snapshot: snapshot,
            refreshIntervalSeconds: settings.refreshIntervalSeconds,
            now: Date()
        ) else {
            return
        }

        if reason == .accountingRevision {
            let storedRevision = snapshot.sources["Codex"]?.accountingRevision
                .map(String.init) ?? "legacy"
            LifecycleLogger.log(
                "Codex accounting revision \(storedRevision) is older than "
                    + "\(UsageCollector.codexAccountingRevision); starting immediate recalibration."
            )
        }
        refresh(forceCollection: reason != .stale)
    }

    private func scheduleDeferredUpdateCheck() {
        deferredUpdateCheckTask?.cancel()
        deferredUpdateCheckTask = nil
        startupUpdateCheckPending = settings.autoUpdateEnabled
        guard settings.autoUpdateEnabled else { return }

        deferredUpdateCheckTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 30_000_000_000)
            } catch {
                return
            }
            guard let self else { return }
            self.startupUpdateCheckPending = false
            self.performUpdateCheck(trigger: .startup)
            self.deferredUpdateCheckTask = nil
        }
    }

    private func configureUpdateCheckTimer() {
        updateCheckTimer?.invalidate()
        updateCheckTimer = nil
        guard settings.autoUpdateEnabled else { return }

        updateCheckTimer = Timer.scheduledTimer(
            withTimeInterval: UpdateCheckPolicy.automaticInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.performUpdateCheck(trigger: .timer)
            }
        }
        updateCheckTimer?.tolerance = UpdateCheckPolicy.timerTolerance
    }

    private func scheduleUpdatePhaseReset() {
        updatePhaseResetTask?.cancel()
        updatePhaseResetTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 4_000_000_000)
            } catch {
                return
            }
            guard let self, case .upToDate = self.updateCheckPhase else { return }
            self.updateCheckPhase = .idle
            self.updatePhaseResetTask = nil
        }
    }

    private func applyDefaultAutostartIfNeeded() {
        repairAutostartIfNeeded()
        guard !FileManager.default.fileExists(atPath: AppPaths.autostartDefaultMarker.path) else { return }
        guard AutostartService.canEnableForCurrentBundle else {
            autostartEnabled = AutostartService.isEnabled
            return
        }
        do {
            if !AutostartService.isEnabled {
                try AutostartService.setEnabled(true)
            }
            try markAutostartDefaultApplied()
            autostartEnabled = AutostartService.isEnabled
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func repairAutostartIfNeeded() {
        guard AutostartService.needsRepairForCurrentBundle else {
            autostartEnabled = AutostartService.isEnabled
            return
        }
        do {
            if try AutostartService.repairForCurrentBundleIfNeeded() {
                try markAutostartDefaultApplied()
            }
            autostartEnabled = AutostartService.isEnabled
        } catch {
            LifecycleLogger.log("Failed to repair login item target: \(error.localizedDescription)")
            lastError = error.localizedDescription
            autostartEnabled = AutostartService.isEnabled
        }
    }

    private func markAutostartDefaultApplied() throws {
        try FileManager.default.createDirectory(
            at: AppPaths.autostartDefaultMarker.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("applied\n".utf8).write(to: AppPaths.autostartDefaultMarker, options: .atomic)
    }
}

enum UsageSnapshotRefreshReason: Equatable {
    case accountingRevision
    case missingModelBreakdown
    case missingSnapshotTimestamp
    case stale
}

enum UsageSnapshotRefreshPolicy {
    static func reason(
        snapshot: UsageSnapshot,
        refreshIntervalSeconds: Int,
        now: Date
    ) -> UsageSnapshotRefreshReason? {
        if DataService.requiresImmediateCodexRecalibration(snapshot) {
            return .accountingRevision
        }
        if snapshot.daily.contains(where: { $0.totalTokens > 0 && $0.models.isEmpty }) {
            return .missingModelBreakdown
        }
        guard refreshIntervalSeconds > 0 else {
            return snapshot.generatedAt == nil ? .missingSnapshotTimestamp : nil
        }
        guard let generatedDate = generatedDate(snapshot.generatedAt)
        else {
            return .missingSnapshotTimestamp
        }
        if now.timeIntervalSince(generatedDate) >= TimeInterval(refreshIntervalSeconds) {
            return .stale
        }
        return nil
    }

    static func generatedDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let date = generatedAtISOWithFractional.date(from: value) {
            return date
        }
        return generatedAtISO.date(from: value)
    }

    private static let generatedAtISOWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let generatedAtISO: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
