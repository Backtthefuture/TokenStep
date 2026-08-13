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
    @Published private(set) var codexQuota: CodexQuotaSnapshot = .unavailable
    @Published private(set) var claudeQuota: CodexQuotaSnapshot = .unavailable
    @Published private(set) var isRefreshingTokenRank = false
    @Published private(set) var tokenRank: TokenRankLeaderboard?
    @Published private(set) var agentWorkRankIdentity: AgentWorkRankIdentity?
    @Published private(set) var tokenRankError: String?
    @Published private(set) var isDownloadingUpdate = false
    @Published private(set) var updateDownloadProgress = 0.0
    @Published private(set) var updateInstallStatus = L("准备更新")
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var lastUpdateCheckAt: Date?
    @Published private(set) var updateDownloadedURL: URL?
    @Published private(set) var tokenIslandAvailable = TokenIslandDisplayDetector.isAvailable
    @Published private(set) var showsUsageRecalibrationNotice = false
    @Published var lastError: String?
    // G-V1 / V1-T01：统一新鲜度状态（六态），采集与两家额度分别呈现。
    @Published private(set) var collectionFreshness = UsageFreshness(kind: .neverSucceeded)
    @Published private(set) var codexQuotaFreshness = UsageFreshness(kind: .neverSucceeded)
    @Published private(set) var claudeQuotaFreshness = UsageFreshness(kind: .neverSucceeded)

    private var freshnessState = FreshnessState()

    private var timer: Timer?
    private var foregroundTimer: Timer?
    private var foregroundRefreshSurfaces = Set<String>()
    private var pendingRefreshAfterCurrent = false
    private var pendingForcedRefresh = false
    private var lastQuotaRefreshAttemptAt: Date?
    private var lastRankRefreshAttemptAt: Date?
    private var lastAutomaticUsageRefreshAttemptAt: Date?
    private var lastUsageObservedAt: Date?

    init() {
        loadFreshnessState()
        recomputeFreshness()
        load()
        refreshIfSnapshotIsStale()
        applyDefaultAutostartIfNeeded()
        configureTimer()
        refreshCodexQuota()
        refreshTokenRank()
        scheduleDeferredUpdateCheck()
    }

    deinit {
        timer?.invalidate()
        foregroundTimer?.invalidate()
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
        "\(settings.theme.id)-\(settings.language.resolved.id)"
    }

    var shouldShowAgentWorkRank: Bool {
        settings.agentWorkRankVisibility.shouldShow(hasLocalIdentity: agentWorkRankIdentity != nil)
    }

    func load() {
        defer { MemoryPressure.relieveAllocatorPressure() }
        let loadedSettings = DataService.loadSettings()
        TokenStepLocalization.apply(loadedSettings.language)
        TokenStepThemeRuntime.apply(loadedSettings.theme)
        settings = loadedSettings
        snapshot = (try? DataService.loadSnapshot()) ?? .empty
        showsUsageRecalibrationNotice = DataService.hasPendingUsageRecalibrationNotice
        if !loadedSettings.showCodexQuota {
            codexQuota = .unavailable
            claudeQuota = .unavailable
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
        // 升级/首跑迁移：无采集记录但仓库已有快照时，从 generated_at 继承最后成功时间，
        // 避免"数据明明存在却显示暂无数据"。
        if freshnessState.collection.lastSucceededAt == nil,
           let generatedAt = snapshot.generatedAt,
           let generatedDate = UsageSnapshotRefreshPolicy.generatedDate(generatedAt) {
            freshnessState.collection.lastSucceededAt = generatedDate
        }
        // 快照重载后来源级状态可能变化；把采集尝试信息同步到内存快照并重算新鲜度。
        snapshot.sourceAttempt = freshnessState.collection
        recomputeFreshness()
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
        freshnessState.collection = freshnessState.collection.attempting(at: refreshStartedAt)
        recomputeFreshness(now: refreshStartedAt)
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
                let kind = FreshnessPolicy.classify(error: error)
                freshnessState.collection = freshnessState.collection.failing(kind: kind, at: Date())
                // 用户可见错误使用安全分类文案，不透出原始错误正文。
                lastError = kind.localizedSummary
            }
            if outcome != .unchanged {
                load()
            }
            if collectionSucceeded {
                if outcome != .updatedWhileSourcesChanged {
                    lastUsageObservedAt = Date()
                }
                // 只要 helper 未抛错即视为成功（快照已持久化）；
                // updatedWhileSourcesChanged 的口径警示保留在 source diagnostics，
                // 不影响"最后成功时间"的判定。
                freshnessState.collection = freshnessState.collection.succeeding(at: Date())
            }
            recomputeFreshness()
            persistFreshnessState()
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
        refreshTokenRank()
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
        guard settings.showCodexQuota else {
            codexQuota = .unavailable
            claudeQuota = .unavailable
            isRefreshingCodexQuota = false
            recomputeFreshness(now: now)
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
        // Codex 与 Claude 分别记录尝试，成功/失败互不掩盖（V1-T01）。
        freshnessState.codexQuota = freshnessState.codexQuota.attempting(at: now)
        freshnessState.claudeQuota = freshnessState.claudeQuota.attempting(at: now)
        recomputeFreshness(now: now)
        Task {
            let quotas = await Task.detached(priority: .utility) {
                let codex = Result { try CodexQuotaService.read() }
                let claude = Result { try ClaudeQuotaService.read() }
                return (codex, claude)
            }.value

            let finishedAt = Date()
            // Codex 已取消 5 小时额度（2026-08-13）：读取恢复（周额度仍在），
            // UI 仅展示 7 天窗口；5 小时数据即使返回也不展示。
            switch quotas.0 {
            case .success(let quota):
                codexQuota = quota
                freshnessState.codexQuota = freshnessState.codexQuota.succeeding(at: finishedAt)
            case .failure(let error):
                if !codexQuota.isAvailable {
                    codexQuota = .unavailable
                }
                freshnessState.codexQuota = freshnessState.codexQuota.failing(
                    kind: FreshnessPolicy.classify(error: error),
                    at: finishedAt
                )
            }

            switch quotas.1 {
            case .success(let quota):
                claudeQuota = quota
                freshnessState.claudeQuota = freshnessState.claudeQuota.succeeding(at: finishedAt)
            case .failure(let error):
                if !claudeQuota.isAvailable {
                    claudeQuota = .unavailable
                }
                freshnessState.claudeQuota = freshnessState.claudeQuota.failing(
                    kind: FreshnessPolicy.classify(error: error),
                    at: finishedAt
                )
            }

            recomputeFreshness(now: finishedAt)
            persistFreshnessState()
            isRefreshingCodexQuota = false
        }
    }

    var hasAnyQuota: Bool {
        codexQuota.isAvailable || claudeQuota.isAvailable
    }

    // MARK: - Freshness（G-V1 / V1-T01）

    /// 用集中策略重算三通道新鲜度；来源级 partial 依赖当前快照的 source diagnostics。
    private func recomputeFreshness(now: Date = Date()) {
        let collectionTTL = FreshnessPolicy.collectionNormalTTL(
            refreshIntervalSeconds: settings.refreshIntervalSeconds
        )
        let sourceStatuses = snapshot.sources.reduce(into: [String: String]()) { result, entry in
            result[entry.key] = entry.value.status
        }
        collectionFreshness = FreshnessPolicy.classify(
            enabled: true,
            record: freshnessState.collection,
            normalTTL: collectionTTL,
            now: now,
            sourceStatuses: sourceStatuses
        )
        codexQuotaFreshness = FreshnessPolicy.classify(
            enabled: settings.showCodexQuota,
            record: freshnessState.codexQuota,
            normalTTL: FreshnessPolicy.quotaNormalTTL,
            now: now
        )
        claudeQuotaFreshness = FreshnessPolicy.classify(
            enabled: settings.showCodexQuota,
            record: freshnessState.claudeQuota,
            normalTTL: FreshnessPolicy.quotaNormalTTL,
            now: now
        )
    }

    private func loadFreshnessState() {
        guard let data = try? Data(contentsOf: AppPaths.freshnessStateJSON),
              let state = try? JSONDecoder().decode(FreshnessState.self, from: data)
        else { return }
        freshnessState = state
    }

    private func persistFreshnessState() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(freshnessState) else { return }
        let url = AppPaths.freshnessStateJSON
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    func quota(for tool: String) -> CodexQuotaSnapshot {
        switch tool {
        case "Claude Code":
            return claudeQuota
        default:
            return codexQuota
        }
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
        TokenStepThemeRuntime.apply(theme)
        settings.theme = theme
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
        settings.showCodexQuota = visible
        saveSettingsAndReload()
        if visible {
            refreshCodexQuota(force: true)
        } else {
            codexQuota = .unavailable
            claudeQuota = .unavailable
            isRefreshingCodexQuota = false
        }
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

    /// G-A1：T1 新源逐源开关（仅主开关开启时生效）。
    /// 列表为 nil（自动纳入态）时先物化当前有效集合，避免误关其他自动源。
    func setExperimentalAgentSource(_ sourceID: String, enabled: Bool) {
        var list = AgentSourceRegistry.enabledIDs(
            masterEnabled: settings.showExperimentalAgentSources,
            perSource: settings.experimentalAgentSources
        )
        if enabled, !list.contains(sourceID) {
            list.append(sourceID)
        } else if !enabled {
            list.removeAll { $0 == sourceID }
        }
        settings.experimentalAgentSources = list
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
            checkForUpdates(silent: true)
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
        guard !isCheckingForUpdates else { return }
        guard settings.autoUpdateEnabled || !silent else { return }
        isCheckingForUpdates = true
        if !silent {
            lastError = nil
        }
        Task {
            do {
                let result = try await UpdateService.checkForUpdates()
                lastUpdateCheckAt = Date()
                switch result {
                case .upToDate:
                    availableUpdate = nil
                case let .available(update):
                    availableUpdate = settings.skippedUpdateVersion == update.version ? nil : update
                }
            } catch {
                if !silent {
                    lastError = error.localizedDescription
                }
            }
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
            } catch {
                lastError = error.localizedDescription
                updateInstallStatus = L("更新失败")
                isDownloadingUpdate = false
            }
        }
    }

    func postponeUpdateNotice() {
        availableUpdate = nil
    }

    func skipAvailableUpdate() {
        guard let version = availableUpdate?.version else { return }
        settings.skippedUpdateVersion = version
        availableUpdate = nil
        saveSettingsAndReload()
    }

    private func saveSettingsAndReload() {
        do {
            try DataService.saveSettings(settings)
            let loadedSettings = DataService.loadSettings()
            TokenStepLocalization.apply(loadedSettings.language)
            TokenStepThemeRuntime.apply(loadedSettings.theme)
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
        guard settings.autoUpdateEnabled else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            checkForUpdatesIfNeeded()
        }
    }

    private func checkForUpdatesIfNeeded() {
        guard settings.autoUpdateEnabled else { return }
        checkForUpdates(silent: true)
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
