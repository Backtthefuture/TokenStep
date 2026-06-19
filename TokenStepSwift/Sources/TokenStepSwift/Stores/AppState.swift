import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot = .empty
    @Published private(set) var settings: TokenStepSettings = .defaults
    @Published private(set) var isRefreshing = false
    @Published private(set) var autostartEnabled = false
    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var isDownloadingUpdate = false
    @Published private(set) var updateDownloadProgress = 0.0
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var lastUpdateCheckAt: Date?
    @Published private(set) var updateDownloadedURL: URL?
    @Published var lastError: String?

    private var timer: Timer?

    init() {
        load()
        applyDefaultAutostartIfNeeded()
        configureTimer()
        refresh()
        checkForUpdatesIfNeeded()
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

    func load() {
        settings = DataService.loadSettings()
        snapshot = (try? DataService.loadSnapshot()) ?? .empty
        autostartEnabled = AutostartService.isEnabled
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        Task {
            do {
                try await Task.detached(priority: .utility) {
                    try DataService.runCollector()
                }.value
            } catch {
                lastError = error.localizedDescription
            }
            load()
            isRefreshing = false
        }
    }

    func clearError() {
        lastError = nil
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

    func downloadAvailableUpdate() {
        guard let update = availableUpdate, !isDownloadingUpdate else { return }
        isDownloadingUpdate = true
        updateDownloadProgress = 0
        updateDownloadedURL = nil
        lastError = nil
        Task {
            do {
                let url = try await UpdateService.downloadAndOpen(update) { [weak self] progress in
                    self?.updateDownloadProgress = progress
                }
                updateDownloadedURL = url
                updateDownloadProgress = 1
            } catch {
                lastError = error.localizedDescription
            }
            isDownloadingUpdate = false
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
            settings = DataService.loadSettings()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func configureTimer() {
        timer?.invalidate()
        timer = nil
        guard settings.refreshIntervalSeconds > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.refreshIntervalSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.load()
                self?.refresh()
            }
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
}
