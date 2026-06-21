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
    @Published private(set) var tokenRankError: String?
    @Published private(set) var isDownloadingUpdate = false
    @Published private(set) var updateDownloadProgress = 0.0
    @Published private(set) var updateInstallStatus = L("准备更新")
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var lastUpdateCheckAt: Date?
    @Published private(set) var updateDownloadedURL: URL?
    @Published private(set) var tokenIslandAvailable = TokenIslandDisplayDetector.isAvailable
    @Published var lastError: String?

    private var timer: Timer?

    init() {
        load()
        applyDefaultAutostartIfNeeded()
        configureTimer()
        refreshCodexQuota()
        refreshIfSnapshotIsStale()
        scheduleDeferredUpdateCheck()
    }

    deinit {
        timer?.invalidate()
    }

    var today: DailyUsage {
        let key = DateFormatter.tokenStepDay.string(from: Date())
        return snapshot.daily.last(where: { $0.date == key })
            ?? snapshot.daily.last
            ?? DailyUsage(date: key, tools: [:], totalTokens: 0, cost: 0)
    }

    var progress: Double {
        guard settings.dailyGoalTokens > 0 else { return 0 }
        return Double(today.totalTokens) / Double(settings.dailyGoalTokens)
    }

    var todayLap: TokenStepLapProgress {
        TokenStepLapProgress(tokens: today.totalTokens, goal: settings.dailyGoalTokens)
    }

    var monthAverage: Int {
        let rows = Array(snapshot.daily.suffix(30))
        guard !rows.isEmpty else { return 0 }
        return rows.map(\.totalTokens).reduce(0, +) / rows.count
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

    func load() {
        defer { MemoryPressure.relieveAllocatorPressure() }
        let loadedSettings = DataService.loadSettings()
        TokenStepLocalization.apply(loadedSettings.language)
        TokenStepThemeRuntime.apply(loadedSettings.theme)
        settings = loadedSettings
        snapshot = (try? DataService.loadSnapshot()) ?? .empty
        if !loadedSettings.showCodexQuota {
            codexQuota = .unavailable
            claudeQuota = .unavailable
        }
        if !loadedSettings.showTokenRank {
            clearTokenRankState()
        }
        autostartEnabled = AutostartService.isEnabled
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        let historyDays = settings.historyDays
        Task {
            do {
                try await Task.detached(priority: .utility) {
                    try DataService.runCollectorInHelper(historyDays: historyDays)
                }.value
            } catch {
                lastError = error.localizedDescription
            }
            load()
            isRefreshing = false
            refreshCodexQuota()
            refreshTokenRank(force: true)
        }
    }

    func refreshCodexQuota() {
        guard settings.showCodexQuota else {
            codexQuota = .unavailable
            claudeQuota = .unavailable
            isRefreshingCodexQuota = false
            return
        }
        guard !isRefreshingCodexQuota else { return }
        isRefreshingCodexQuota = true
        Task {
            let quotas = await Task.detached(priority: .utility) {
                let codex = Result { try CodexQuotaService.read() }
                let claude = Result { try ClaudeQuotaService.read() }
                return (try? codex.get(), try? claude.get())
            }.value

            if let quota = quotas.0 {
                codexQuota = quota
            } else if !codexQuota.isAvailable {
                codexQuota = .unavailable
            }

            if let quota = quotas.1 {
                claudeQuota = quota
            } else if !claudeQuota.isAvailable {
                claudeQuota = .unavailable
            }

            isRefreshingCodexQuota = false
        }
    }

    var hasAnyQuota: Bool {
        codexQuota.isAvailable || claudeQuota.isAvailable
    }

    func quota(for tool: String) -> CodexQuotaSnapshot {
        switch tool {
        case "Claude Code":
            return claudeQuota
        default:
            return codexQuota
        }
    }

    func clearError() {
        lastError = nil
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
            refreshCodexQuota()
        } else {
            codexQuota = .unavailable
            claudeQuota = .unavailable
            isRefreshingCodexQuota = false
        }
    }

    func setTokenRankVisible(_ visible: Bool) {
        settings.showTokenRank = visible
        saveSettingsAndReload()
        if settings.showTokenRank {
            refreshTokenRank(force: true)
        } else {
            clearTokenRankState()
        }
    }

    func setTokenRankUserID(_ userID: String) {
        settings.tokenRankUserID = TokenStepSettings.cleanedTokenRankUserID(userID)
        saveSettingsAndReload()
        if settings.showTokenRank, tokenRank == nil {
            refreshTokenRank(force: true)
        }
    }

    func refreshTokenRank(force: Bool = false) {
        guard settings.showTokenRank else {
            clearTokenRankState()
            return
        }
        guard !isRefreshingTokenRank else { return }
        if !force,
           let fetchedAt = tokenRank?.fetchedAt,
           Date().timeIntervalSince(fetchedAt) < TokenRankService.cacheTTL {
            return
        }

        isRefreshingTokenRank = true
        Task {
            defer {
                isRefreshingTokenRank = false
            }
            do {
                let leaderboard = try await TokenRankService.fetchLeaderboard()
                guard settings.showTokenRank else {
                    clearTokenRankState()
                    return
                }
                tokenRank = leaderboard
                tokenRankError = nil
            } catch {
                guard settings.showTokenRank else {
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
        NSWorkspace.shared.open(TokenRankService.leaderboardPageURL)
    }

    func openTokenRankUserPage() {
        guard let url = TokenRankService.userPageURL(userID: settings.tokenRankUserID) else {
            openTokenRankLeaderboardPage()
            return
        }
        NSWorkspace.shared.open(url)
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
        tokenRankError = nil
        isRefreshingTokenRank = false
    }

    private func configureTimer() {
        timer?.invalidate()
        timer = nil
        guard settings.refreshIntervalSeconds > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.refreshIntervalSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        timer?.tolerance = min(TimeInterval(settings.refreshIntervalSeconds) * 0.1, 30)
    }

    private func refreshIfSnapshotIsStale() {
        if snapshot.daily.contains(where: { $0.totalTokens > 0 && $0.models.isEmpty }) {
            refresh()
            return
        }
        guard settings.refreshIntervalSeconds > 0 else {
            if snapshot.generatedAt == nil {
                refresh()
            }
            return
        }
        guard let generatedAt = snapshot.generatedAt,
              let generatedDate = Self.parseGeneratedAt(generatedAt)
        else {
            refresh()
            return
        }
        if Date().timeIntervalSince(generatedDate) >= TimeInterval(settings.refreshIntervalSeconds) {
            refresh()
        }
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
        guard !FileManager.default.fileExists(atPath: AppPaths.autostartDefaultMarker.path) else { return }
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

    private func markAutostartDefaultApplied() throws {
        try FileManager.default.createDirectory(
            at: AppPaths.autostartDefaultMarker.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("applied\n".utf8).write(to: AppPaths.autostartDefaultMarker, options: .atomic)
    }

    private static func parseGeneratedAt(_ value: String) -> Date? {
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
