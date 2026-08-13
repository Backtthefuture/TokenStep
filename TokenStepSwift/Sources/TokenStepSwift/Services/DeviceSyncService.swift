import Foundation

// G-S1：多设备同步（正安火账号；默认关闭；关闭 = 零身份读取零网络请求）。
// 契约：docs/sync/CONTRACT.md（draft-frozen v1，服务端就绪前不启用入口）。
//
// 设计：
// - Transport 协议注入（URLSessionTransport 生产 / 测试注入 mock，可断言调用次数）；
// - 上行桶从 usage.json 派生（天×小时×Agent×模型×项目目录名 的 token 计数），
//   增量水位续传；只含 token 数，绝无金额/路径/正文；
// - 本机 usage.json 永远权威；远端桶只读落盘 cache/remote-buckets.json；
// - 合并只发生在展示层（SyncMergeView 纯函数，本文件内可测）。

struct SyncBucket: Codable, Equatable, Hashable {
    var day: String
    var hour: Int
    var agent: String
    var model: String
    var project: String
    var tokens: Int
}

struct SyncState: Codable, Equatable {
    var watermark: String?
    var deviceID: String?
    var deviceName: String?
    var schemaVersion: Int = 1
    var lastSucceededAt: Date?

    init() {}
}

struct RemoteDeviceBuckets: Codable, Equatable {
    var name: String
    var buckets: [SyncBucket]
}

struct RemoteBucketsSnapshot: Codable, Equatable {
    var fetchedAt: Date
    var devices: [String: RemoteDeviceBuckets]
}

/// 同步传输层。生产实现走 URLSession；测试注入计数 mock（隐私门的证据来源）。
protocol SyncTransport {
    func register(deviceName: String, schemaVersion: Int) throws -> (deviceID: String, accountID: String)
    func upload(buckets: [SyncBucket], watermark: String?) throws -> String
    func fetch(since: Date?) throws -> [String: RemoteDeviceBuckets]
    func deleteDevice(deviceID: String) throws
}

/// 关闭状态下的哑传输：任何调用都是编程错误（防御性，便于隐私断言）。
struct DisabledSyncTransport: SyncTransport {
    private let trap: () -> Never

    init(file: StaticString = #fileID, line: UInt = #line) {
        trap = {
            fatalError("SyncTransport must not be used while device sync is disabled", file: file, line: line)
        }
    }

    func register(deviceName: String, schemaVersion: Int) throws -> (deviceID: String, accountID: String) { trap() }
    func upload(buckets: [SyncBucket], watermark: String?) throws -> String { trap() }
    func fetch(since: Date?) throws -> [String: RemoteDeviceBuckets] { trap() }
    func deleteDevice(deviceID: String) throws { trap() }
}

enum SyncBucketDerivation {
    /// 从快照派生上行桶（只含 token 计数；项目为目录名或 ""）。
    /// hours 未知时记 -1；模型用显示名。
    static func buckets(from snapshot: UsageSnapshot) -> [SyncBucket] {
        var merged: [BucketKey: Int] = [:]
        for daily in snapshot.daily {
            for project in daily.projects ?? [] {
                let projectName = project.name
                for (agent, tokens) in project.tools {
                    merged[BucketKey(day: daily.date, agent: agent, project: projectName), default: 0] += tokens
                }
            }
            // 项目维度未覆盖的来源（未命名项目桶）也要上行，保证今日合计可还原。
            let projectTokens = (daily.projects ?? []).reduce(0) { $0 + $1.tokens }
            if daily.totalTokens > projectTokens {
                merged[BucketKey(day: daily.date, agent: "", project: ""), default: 0]
                    += daily.totalTokens - projectTokens
            }
        }
        return merged.map { key, tokens in
            SyncBucket(day: key.day, hour: -1, agent: key.agent, model: "", project: key.project, tokens: tokens)
        }
    }

    private struct BucketKey: Hashable {
        var day: String
        var agent: String
        var project: String
    }

    /// 隐私守卫：桶内不得出现路径分隔符、金额字段；只允许计数。
    static func containsForbiddenContent(_ buckets: [SyncBucket]) -> Bool {
        buckets.contains { bucket in
            bucket.project.contains("/")
                || bucket.project.contains("\\")
                || bucket.project.contains(":")
                || bucket.tokens < 0
        }
    }
}

/// 展示层合并（纯函数）：本机口径 + 可见远端桶 → 合计。
enum SyncMergeView {
    struct Input {
        var localDaily: [DailyUsage]
        var remote: RemoteBucketsSnapshot?
        var hiddenDeviceIDs: Set<String>
        var mergeEnabled: Bool
    }

    /// 合并后的逐日 totalTokens（键=day）。
    static func dailyTotals(_ input: Input) -> [String: Int] {
        var totals: [String: Int] = [:]
        for row in input.localDaily {
            totals[row.date, default: 0] += row.totalTokens
        }
        guard input.mergeEnabled, let remote = input.remote else { return totals }
        for (deviceID, device) in remote.devices where !input.hiddenDeviceIDs.contains(deviceID) {
            for bucket in device.buckets {
                totals[bucket.day, default: 0] += bucket.tokens
            }
        }
        return totals
    }

    /// 多设备口径下的"今日 tokens"。
    static func todayTokens(_ input: Input, dayKey: String) -> Int {
        dailyTotals(input)[dayKey] ?? 0
    }
}

enum DeviceSyncService {
    static let stateURL = AppPaths.appSupportRoot.appendingPathComponent("cache/sync-state.json")
    static let remoteURL = AppPaths.appSupportRoot.appendingPathComponent("cache/remote-buckets.json")

    /// 同步一轮：上行增量 → 下行远端桶。返回是否成功（失败不清空既有远端数据）。
    @discardableResult
    static func syncOnce(
        snapshot: UsageSnapshot,
        state: inout SyncState,
        transport: SyncTransport
    ) -> Bool {
        if state.deviceID == nil || state.deviceName == nil {
            state.deviceName = state.deviceName ?? HostnameProvider.name
            do {
                let registered = try transport.register(
                    deviceName: state.deviceName ?? "Mac",
                    schemaVersion: state.schemaVersion
                )
                state.deviceID = registered.deviceID
            } catch {
                return false
            }
        }
        do {
            let buckets = SyncBucketDerivation.buckets(from: snapshot)
            guard !SyncBucketDerivation.containsForbiddenContent(buckets) else {
                return false
            }
            let watermark = try transport.upload(buckets: buckets, watermark: state.watermark)
            state.watermark = watermark
            let devices = try transport.fetch(since: nil)
            let remote = RemoteBucketsSnapshot(fetchedAt: Date(), devices: devices)
            if let data = try? JSONEncoder().encode(remote) {
                try? FileManager.default.createDirectory(
                    at: remoteURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? data.write(to: remoteURL, options: .atomic)
            }
            state.lastSucceededAt = Date()
            persist(state)
            return true
        } catch {
            persist(state)
            return false
        }
    }

    static func loadState() -> SyncState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(SyncState.self, from: data)
        else { return SyncState() }
        return state
    }

    static func persist(_ state: SyncState) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: stateURL, options: .atomic)
    }

    static func loadRemoteBuckets() -> RemoteBucketsSnapshot? {
        guard let data = try? Data(contentsOf: remoteURL) else { return nil }
        return try? JSONDecoder().decode(RemoteBucketsSnapshot.self, from: data)
    }

    /// 解绑：清本机状态 + best-effort 服务端删除。
    static func unbind(state: inout SyncState, transport: SyncTransport) {
        if let deviceID = state.deviceID {
            try? transport.deleteDevice(deviceID: deviceID)
        }
        state = SyncState()
        persist(state)
        try? FileManager.default.removeItem(at: remoteURL)
    }
}

enum HostnameProvider {
    static var name: String {
        HostnameProviderImplementation.name
    }
}

private enum HostnameProviderImplementation {
    static var name: String {
        ProcessInfo.processInfo.hostName
    }
}
