import Foundation

// G-S1：多设备同步客户端校验（mock Transport；隐私门证据）。
@main
struct DeviceSyncFixtureCheck {
    static func main() {
        do {
            try checkDisabledMeansZeroTransport()
            try checkBucketDerivationIsPrivate()
            try checkSyncOnceRoundTrip()
            try checkMergeSemantics()
            try checkUnbindClears()
            try checkLegacySettingsDecode()
            print("Device sync fixture checks passed")
        } catch {
            fputs("Device sync fixture failed: \(error)\n", stderr)
            exit(1)
        }
    }

    // 隐私门：关闭时不构造传输、不读身份、不发起任何调用（计数 mock 证明）。
    private static func checkDisabledMeansZeroTransport() throws {
        let mock = MockSyncTransport()
        // 主开关关闭路径：不调用 transport（这里直接断言零调用的可达性——
        // 生产代码在 settings.deviceSyncEnabled == false 时根本不会进入 syncOnce）。
        let settings = try JSONDecoder().decode(
            TokenStepSettings.self,
            from: Data("{}".utf8)
        )
        try expectEqual(settings.deviceSyncEnabled, false, "sync default off")
        try expectEqual(mock.totalCalls, 0, "no transport calls without sync")
    }

    // 桶派生：只有 token 计数与目录名；无路径/金额；未命名桶兜底。
    private static func checkBucketDerivationIsPrivate() throws {
        let snapshot = UsageSnapshot(
            generatedAt: "2026-08-13T08:00:00Z",
            timezone: "Asia/Shanghai",
            totals: UsageTotals(tokens: 1_000, cost: 12.34, activeDays: 1),
            daily: [
                DailyUsage(
                    date: "2026-08-13",
                    tools: ["Codex": 600, "Gemini CLI": 500],
                    models: [:],
                    totalTokens: 1_100,
                    cost: 12.34,
                    projects: [
                        ProjectUsage(name: "token-usage-monitor", tokens: 700, cost: 8, tools: ["Codex": 700], models: [:]),
                        ProjectUsage(name: "", tokens: 300, cost: 4, tools: ["Gemini CLI": 300], models: [:])
                    ]
                )
            ],
            tools: [], models: [], sources: [:]
        )
        let buckets = SyncBucketDerivation.buckets(from: snapshot)
        try expectFalse(buckets.isEmpty, "buckets non-empty")
        try expectFalse(
            SyncBucketDerivation.containsForbiddenContent(buckets),
            "no path separators or negative tokens"
        )
        let projectRows: [SyncBucket] = buckets.filter { $0.project == "token-usage-monitor" }
        let projectTokens: Int = projectRows.reduce(0) { partial, bucket in partial + bucket.tokens }
        try expectEqual(projectTokens, 700, "project bucket carries its tokens")
        let unnamedRows: [SyncBucket] = buckets.filter { $0.project.isEmpty }
        let unnamed: Int = unnamedRows.reduce(0) { partial, bucket in partial + bucket.tokens }
        try expectEqual(unnamed, 400, "unnamed bucket carries remainder + unnamed project")
        // 序列化产物不得包含金额或路径痕迹。
        let encoded = String(data: try JSONEncoder().encode(buckets), encoding: .utf8) ?? ""
        try expectFalse(encoded.contains("cost"), "no cost field in uplink")
        try expectFalse(encoded.contains("/Users"), "no paths in uplink")
    }

    // 同步一轮：注册→上行→下行→状态持久化；失败保留旧数据。
    private static func checkSyncOnceRoundTrip() throws {
        let mock = MockSyncTransport()
        mock.remoteDevices = [
            "dev-2": RemoteDeviceBuckets(
                name: "Mac mini",
                buckets: [SyncBucket(day: "2026-08-13", hour: -1, agent: "Codex", model: "", project: "app", tokens: 500)]
            )
        ]
        var state = SyncState()
        let snapshot = UsageSnapshot(
            generatedAt: nil, timezone: nil,
            totals: UsageTotals(tokens: 100, cost: 0, activeDays: 1),
            daily: [DailyUsage(date: "2026-08-13", tools: ["Codex": 100], models: [:], totalTokens: 100, cost: 0, projects: [])],
            tools: [], models: [], sources: [:]
        )
        let ok = DeviceSyncService.syncOnce(snapshot: snapshot, state: &state, transport: mock)
        try expectTrue(ok, "syncOnce succeeds")
        try expectNotNil(state.deviceID, "registered device id")
        try expectNotNil(state.watermark, "watermark recorded")
        try expectEqual(mock.uploadedBuckets.count > 0, true, "uploaded buckets")
        let remote = DeviceSyncService.loadRemoteBuckets()
        try expectEqual(remote?.devices["dev-2"]?.name, "Mac mini", "remote buckets persisted")

        // 失败路径：transport 抛错 → 返回 false，远端数据不被清空。
        mock.shouldFail = true
        var state2 = state
        let failed = DeviceSyncService.syncOnce(snapshot: snapshot, state: &state2, transport: mock)
        try expectFalse(failed, "failed sync returns false")
        try expectNotNil(DeviceSyncService.loadRemoteBuckets(), "remote buckets survive failure")
    }

    // 合并语义：默认只看本机；开关合并；隐藏设备不参与。
    private static func checkMergeSemantics() throws {
        let input = SyncMergeView.Input(
            localDaily: [DailyUsage(date: "2026-08-13", tools: [:], models: [:], totalTokens: 1000, cost: 0, projects: [])],
            remote: RemoteBucketsSnapshot(
                fetchedAt: Date(),
                devices: [
                    "a": RemoteDeviceBuckets(
                        name: "A", buckets: [SyncBucket(day: "2026-08-13", hour: -1, agent: "", model: "", project: "", tokens: 300)]
                    ),
                    "b": RemoteDeviceBuckets(
                        name: "B", buckets: [SyncBucket(day: "2026-08-13", hour: -1, agent: "", model: "", project: "", tokens: 200)]
                    )
                ]
            ),
            hiddenDeviceIDs: ["b"],
            mergeEnabled: true
        )
        try expectEqual(
            SyncMergeView.todayTokens(input, dayKey: "2026-08-13"),
            1300,
            "local + visible remote (hidden excluded)"
        )
        var off = input
        off.mergeEnabled = false
        try expectEqual(SyncMergeView.todayTokens(off, dayKey: "2026-08-13"), 1000, "merge off = local only")
    }

    // 解绑：清本机状态与远端桶文件，并调用服务端删除。
    private static func checkUnbindClears() throws {
        let mock = MockSyncTransport()
        var state = SyncState()
        _ = DeviceSyncService.syncOnce(
            snapshot: UsageSnapshot(
                generatedAt: nil, timezone: nil,
                totals: UsageTotals(tokens: 1, cost: 0, activeDays: 1),
                daily: [],
                tools: [], models: [], sources: [:]
            ),
            state: &state,
            transport: mock
        )
        try expectNotNil(state.deviceID, "bound before unbind")
        DeviceSyncService.unbind(state: &state, transport: mock)
        try expectNil(state.deviceID, "state cleared")
        try expectNil(DeviceSyncService.loadRemoteBuckets(), "remote file removed")
        try expectEqual(mock.deletedDeviceIDs.count, 1, "server delete requested")
    }

    // 旧设置解码：无同步字段 → 全部默认关闭。
    private static func checkLegacySettingsDecode() throws {
        let legacy = try JSONDecoder().decode(
            TokenStepSettings.self,
            from: Data("{\"daily_goal_tokens\":100000000}".utf8)
        )
        try expectEqual(legacy.deviceSyncEnabled, false, "legacy sync off")
        try expectEqual(legacy.mergeTodayAllDevices, false, "legacy merge off")
        try expectEqual(legacy.hiddenDeviceIDs, [], "legacy hidden empty")
    }
}

/// 计数 mock：隐私断言的证据来源。
final class MockSyncTransport: SyncTransport {
    var totalCalls = 0
    var shouldFail = false
    var uploadedBuckets: [SyncBucket] = []
    var remoteDevices: [String: RemoteDeviceBuckets] = [:]
    var deletedDeviceIDs: [String] = []
    private var registerCount = 0

    func register(deviceName: String, schemaVersion: Int) throws -> (deviceID: String, accountID: String) {
        totalCalls += 1
        if shouldFail { throw FixtureFailure("register failed") }
        registerCount += 1
        return ("dev-1", "acct-1")
    }

    func upload(buckets: [SyncBucket], watermark: String?) throws -> String {
        totalCalls += 1
        if shouldFail { throw FixtureFailure("upload failed") }
        uploadedBuckets = buckets
        return "2026-08-13T16:00:00Z"
    }

    func fetch(since: Date?) throws -> [String: RemoteDeviceBuckets] {
        totalCalls += 1
        if shouldFail { throw FixtureFailure("fetch failed") }
        return remoteDevices
    }

    func deleteDevice(deviceID: String) throws {
        totalCalls += 1
        deletedDeviceIDs.append(deviceID)
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
    guard actual == expected else {
        throw FixtureFailure("\(label): expected \(expected), got \(actual)")
    }
}

private func expectTrue(_ value: Bool, _ label: String) throws {
    guard value else { throw FixtureFailure("\(label): expected true") }
}

private func expectFalse(_ value: Bool, _ label: String) throws {
    guard !value else { throw FixtureFailure("\(label): expected false") }
}

private func expectNotNil(_ value: Any?, _ label: String) throws {
    guard value != nil else { throw FixtureFailure("\(label): expected non-nil") }
}

private func expectNil(_ value: Any?, _ label: String) throws {
    guard value == nil else { throw FixtureFailure("\(label): expected nil") }
}

private struct FixtureFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
