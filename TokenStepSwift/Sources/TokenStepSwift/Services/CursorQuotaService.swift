import Foundation

enum CursorQuotaService {
    static var databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")

    static func read() throws -> ProviderQuota {
        if let cached = readFreshCache() {
            return cached
        }
        let token = try readAccessToken()
        guard let userId = userId(fromJWT: token) else {
            throw TokenStepError.message(L("未登录 Cursor"))
        }
        let usage = try fetchBestUsage(userId: userId, accessToken: token)
        let windows = windows(from: usage)
        let snapshot = ProviderQuota(
            provider: .cursor,
            windows: windows,
            status: windows.isEmpty ? .unavailable : .available,
            fetchedAt: Date(),
            message: windows.isEmpty ? L("Cursor 额度暂不可用") : nil
        )
        if snapshot.isAvailable {
            writeCache(snapshot)
        }
        return snapshot
    }

    static func userId(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload += "="
        }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let sub = object["sub"] as? String, !sub.isEmpty {
            return sub
        }
        return nil
    }

    private static func readAccessToken() throws -> String {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw TokenStepError.message(L("未登录 Cursor"))
        }
        let rows = SQLiteReadonly.jsonRows(
            database: databaseURL,
            query: "select value from ItemTable where key='cursorAuth/accessToken' limit 1"
        )
        guard let value = rows?.first?["value"] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw TokenStepError.message(L("未登录 Cursor"))
        }
        return value
    }

    private static func fetchBestUsage(userId: String, accessToken: String) throws -> Any {
        if let summary = try? fetchJSON(
            url: "https://cursor.com/api/usage-summary",
            userId: userId,
            accessToken: accessToken
        ), !windows(from: summary).isEmpty {
            return summary
        }
        return try fetchLegacyUsage(userId: userId, accessToken: accessToken)
    }

    private static func fetchLegacyUsage(userId: String, accessToken: String) throws -> Any {
        guard var components = URLComponents(string: "https://cursor.com/api/usage") else {
            throw TokenStepError.message(L("Cursor 额度暂不可用"))
        }
        components.queryItems = [URLQueryItem(name: "user", value: userId)]
        guard let url = components.url else {
            throw TokenStepError.message(L("Cursor 额度暂不可用"))
        }
        return try fetchJSON(url: url.absoluteString, userId: userId, accessToken: accessToken)
    }

    private static func fetchJSON(url: String, userId: String, accessToken: String) throws -> Any {
        guard let requestURL = URL(string: url) else {
            throw TokenStepError.message(L("Cursor 额度暂不可用"))
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 6
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("WorkosCursorSessionToken=\(userId)::\(accessToken)", forHTTPHeaderField: "Cookie")
        return try HTTPJSONClient.jsonObject(for: request)
    }

    static func windows(from payload: Any) -> [QuotaWindow] {
        if let pools = twoPoolWindows(from: payload), !pools.isEmpty {
            return pools
        }
        return legacyWindows(from: payload)
    }

    static func twoPoolWindows(from payload: Any) -> [QuotaWindow]? {
        guard let object = payload as? [String: Any] else { return nil }
        let individual = object["individualUsage"] as? [String: Any]
        let plan = individual?["plan"] as? [String: Any] ?? object["plan"] as? [String: Any] ?? object
        let reset = date(from: object["billingCycleEnd"] ?? object["resetsAt"] ?? object["resetAt"] ?? plan["resetsAt"])

        let auto = QuotaJSON.number(
            plan["autoPercentUsed"]
                ?? object["autoPercentUsed"]
                ?? object["cursorModelsPercentUsed"]
                ?? object["firstPartyPercentUsed"]
        ) ?? percentFromDisplayMessage(object["autoModelSelectedDisplayMessage"])
        let api = QuotaJSON.number(
            plan["apiPercentUsed"]
                ?? object["apiPercentUsed"]
                ?? object["otherModelsPercentUsed"]
                ?? object["namedPercentUsed"]
        ) ?? percentFromDisplayMessage(object["namedModelSelectedDisplayMessage"])

        var windows: [QuotaWindow] = []
        if let auto, let used = normalizedUsedPercent(auto) {
            windows.append(
                QuotaWindow(kind: .cursorModels, usedPercent: used, remaining: 100 - used, total: 100, resetsAt: reset)
            )
        }
        if let api, let used = normalizedUsedPercent(api) {
            windows.append(
                QuotaWindow(kind: .otherModels, usedPercent: used, remaining: 100 - used, total: 100, resetsAt: reset)
            )
        }
        return windows.isEmpty ? nil : windows
    }

    static func percentFromDisplayMessage(_ value: Any?) -> Double? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        let patterns = [#"used\s+(\d+(?:\.\d+)?)\s*%"#, #"已使用\s*(\d+(?:\.\d+)?)\s*%"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  match.numberOfRanges >= 2,
                  let capture = Range(match.range(at: 1), in: text)
            else { continue }
            return Double(text[capture])
        }
        return nil
    }

    private static func legacyWindows(from payload: Any) -> [QuotaWindow] {
        guard let object = payload as? [String: Any] else { return [] }
        var windows: [QuotaWindow] = []

        if let plan = object["planUsage"] as? [String: Any] ?? object["usage"] as? [String: Any] {
            if let window = window(from: plan, kind: .monthlyCredits) {
                windows.append(window)
            }
        }

        for (key, value) in object {
            guard let nested = value as? [String: Any] else { continue }
            let kind: QuotaWindowKind
            let lowered = key.lowercased()
            if lowered.contains("gpt") || lowered.contains("premium") || lowered.contains("request") {
                kind = .monthlyCredits
            } else if lowered.contains("spend") || lowered.contains("dollar") {
                kind = .spend
            } else {
                continue
            }
            if let window = window(from: nested, kind: kind),
               !windows.contains(where: { $0.kind == kind }) {
                windows.append(window)
            }
        }

        if windows.isEmpty, let window = window(from: object, kind: .monthlyCredits) {
            windows.append(window)
        }
        return windows
    }

    private static func normalizedUsedPercent(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        // usage-summary reports 0–100 (1 = 1% used, not 100%).
        return min(max(value, 0), 100)
    }

    private static func window(from object: [String: Any], kind: QuotaWindowKind) -> QuotaWindow? {
        let used = QuotaJSON.number(object["used"] ?? object["numRequests"] ?? object["numRequestsTotal"])
        let remaining = QuotaJSON.number(object["remaining"] ?? object["remain"])
        let total = QuotaJSON.number(object["limit"] ?? object["maxRequestUsage"] ?? object["maxTokenUsage"] ?? object["total"])
        guard let usedPercent = QuotaJSON.percent(used: used, remaining: remaining, total: total) else {
            return nil
        }
        return QuotaWindow(
            kind: kind,
            usedPercent: usedPercent,
            remaining: remaining,
            total: total,
            resetsAt: date(from: object["startOfMonth"] ?? object["resetsAt"] ?? object["resetAt"])
        )
    }

    private static func date(from value: Any?) -> Date? {
        if let text = value as? String {
            if let date = ISO8601DateFormatter.tokenStep.date(from: text) {
                return date
            }
            return ISO8601DateFormatter.tokenStepNoFraction.date(from: text)
        }
        if let seconds = QuotaJSON.number(value) {
            return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
        }
        return nil
    }

    private static func readFreshCache(now: Date = Date()) -> ProviderQuota? {
        guard let data = try? Data(contentsOf: AppPaths.cursorQuotaCacheJSON),
              let cache = try? JSONDecoder().decode(ProviderQuotaCache.self, from: data),
              now.timeIntervalSince(cache.fetchedAt) <= 10 * 60
        else { return nil }
        let quota = cache.quota
        guard quota.isAvailable else { return nil }
        let hasTwoPools = quota.windows.contains { $0.kind == .cursorModels || $0.kind == .otherModels }
        return hasTwoPools ? quota : nil
    }

    private static func writeCache(_ quota: ProviderQuota) {
        let cache = ProviderQuotaCache(fetchedAt: quota.fetchedAt ?? Date(), quota: quota)
        do {
            let directory = AppPaths.cursorQuotaCacheJSON.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(cache).write(to: AppPaths.cursorQuotaCacheJSON, options: [.atomic])
        } catch {
            // Cache is best-effort.
        }
    }
}

struct ProviderQuotaCache: Codable {
    var fetchedAt: Date
    var quota: ProviderQuota
}

private extension ISO8601DateFormatter {
    static let tokenStep: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let tokenStepNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
