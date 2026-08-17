import Foundation

enum KimiQuotaService {
    static var homeURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kimi")

    static func read() throws -> ProviderQuota {
        guard let token = readOAuthToken() else {
            throw TokenStepError.message(L("未登录 Kimi"))
        }
        var lastError: Error = TokenStepError.message(L("Kimi 额度暂不可用"))
        for url in endpoints {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 6
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let object = try HTTPJSONClient.jsonObject(for: request)
                let windows = windows(from: object)
                if !windows.isEmpty {
                    return ProviderQuota(
                        provider: .kimi,
                        windows: windows,
                        status: .available,
                        fetchedAt: Date(),
                        message: nil
                    )
                }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func windows(from payload: Any) -> [QuotaWindow] {
        let object = (payload as? [String: Any]) ?? [:]
        let data = (object["data"] as? [String: Any]) ?? object
        var windows: [QuotaWindow] = []
        if let session = window(from: data["session"] ?? data["session_usage"], kind: .session) {
            windows.append(session)
        }
        if let weekly = window(from: data["weekly"] ?? data["week"] ?? data["weekly_usage"], kind: .weekly) {
            windows.append(weekly)
        }
        if windows.isEmpty, let fallback = window(from: data, kind: .weekly) {
            windows.append(fallback)
        }
        return windows
    }

    private static func window(from value: Any?, kind: QuotaWindowKind) -> QuotaWindow? {
        guard let object = value as? [String: Any] else { return nil }
        let used = QuotaJSON.number(object["used"] ?? object["used_percent"] ?? object["utilization"])
        let remaining = QuotaJSON.number(object["remaining"] ?? object["remain"])
        let total = QuotaJSON.number(object["total"] ?? object["limit"] ?? object["quota"])
        guard let usedPercent = QuotaJSON.percent(used: used, remaining: remaining, total: total) else {
            return nil
        }
        return QuotaWindow(kind: kind, usedPercent: usedPercent, remaining: remaining, total: total, resetsAt: nil)
    }

    private static func readOAuthToken() -> String? {
        let candidates = [
            homeURL.appendingPathComponent("auth.json"),
            homeURL.appendingPathComponent("credentials.json"),
            homeURL.appendingPathComponent("oauth.json"),
            homeURL.appendingPathComponent("config.json")
        ]
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if let token = firstToken(in: object) {
                return token
            }
        }
        return TokenStepSecrets.get(.kimiAccessToken)
    }

    private static func firstToken(in object: [String: Any]) -> String? {
        let keys = ["access_token", "accessToken", "token", "oauth_token"]
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty, !value.hasPrefix("sk-") {
                return value
            }
        }
        for value in object.values {
            if let nested = value as? [String: Any], let token = firstToken(in: nested) {
                return token
            }
        }
        return nil
    }

    private static var endpoints: [URL] {
        [
            "https://api.kimi.com/coding/usage",
            "https://www.kimi.com/api/coding/usage"
        ].compactMap(URL.init(string:))
    }
}
