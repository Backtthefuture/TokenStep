import Foundation

enum GrokQuotaService {
    static var authURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".grok/auth.json")

    static func read() throws -> ProviderQuota {
        guard let session = readSession() else {
            throw TokenStepError.message(L("需要 grok login"))
        }

        var windows: [QuotaWindow] = []
        var lastError: Error = TokenStepError.message(L("Grok 额度暂不可用"))
        for url in endpoints {
            do {
                let payload = try fetchJSON(url: url, session: session)
                windows.append(contentsOf: Self.windows(from: payload).filter { candidate in
                    !windows.contains(where: { $0.kind == candidate.kind })
                })
            } catch {
                lastError = TokenStepError.message(L("Grok 额度暂不可用"))
            }
        }
        if !windows.isEmpty {
            return ProviderQuota(
                provider: .grok,
                windows: windows,
                status: .available,
                fetchedAt: Date(),
                message: nil
            )
        }
        throw lastError
    }

    static func hasLocalSession() -> Bool {
        readSession() != nil
    }

    static func windows(from payload: Any) -> [QuotaWindow] {
        let object = (payload as? [String: Any]) ?? [:]
        let config = (object["config"] as? [String: Any]) ?? object
        var windows: [QuotaWindow] = []

        if let used = QuotaJSON.number(config["creditUsagePercent"] ?? object["creditUsagePercent"]) {
            let period = config["currentPeriod"] as? [String: Any]
            let kind: QuotaWindowKind
            if let type = period?["type"] as? String, type.uppercased().contains("WEEK") {
                kind = .weekly
            } else {
                kind = .monthlyCredits
            }
            let reset = date(from: period?["end"] ?? config["billingPeriodEnd"] ?? object["billingPeriodEnd"])
            let usedPercent = min(max(used, 0), 100)
            windows.append(
                QuotaWindow(kind: kind, usedPercent: usedPercent, remaining: 100 - usedPercent, total: 100, resetsAt: reset)
            )
        }

        if let used = cent(config["used"] ?? object["used"]),
           let total = cent(config["monthlyLimit"] ?? object["monthlyLimit"] ?? object["limit"]),
           total > 0,
           let usedPercent = QuotaJSON.percent(used: used, remaining: nil, total: total) {
            let reset = date(from: config["billingPeriodEnd"] ?? object["billingPeriodEnd"])
            if !windows.contains(where: { $0.kind == .monthlyCredits }) {
                windows.append(
                    QuotaWindow(kind: .monthlyCredits, usedPercent: usedPercent, remaining: max(total - used, 0), total: total, resetsAt: reset)
                )
            }
        }

        if windows.isEmpty,
           let window = window(from: config["credits"] ?? object["credits"] ?? config["credit"] ?? object["credit"], kind: .monthlyCredits) {
            windows.append(window)
        }
        return windows
    }

    static func sessionToken(from object: [String: Any]) -> String? {
        session(from: object)?.token
    }

    static func looksLikeSessionToken(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("xai-") { return false }
        if trimmed.hasPrefix("eyJ") { return true }
        return trimmed.count >= 40
    }

    private static func fetchJSON(url: URL, session: GrokSession) throws -> Any {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        if let userId = session.userId, !userId.isEmpty {
            request.setValue(userId, forHTTPHeaderField: "x-userid")
        }
        return try HTTPJSONClient.jsonObject(for: request)
    }

    private static func window(from value: Any?, kind: QuotaWindowKind) -> QuotaWindow? {
        guard let object = value as? [String: Any] else { return nil }
        let used = QuotaJSON.number(object["used"] ?? object["used_percent"]) ?? cent(object["used"])
        let remaining = QuotaJSON.number(object["remaining"] ?? object["remain"] ?? object["balance"])
        let total = QuotaJSON.number(object["total"] ?? object["limit"] ?? object["quota"]) ?? cent(object["monthlyLimit"])
        guard let usedPercent = QuotaJSON.percent(used: used, remaining: remaining, total: total) else {
            return nil
        }
        return QuotaWindow(kind: kind, usedPercent: usedPercent, remaining: remaining, total: total, resetsAt: nil)
    }

    private static func readSession() -> GrokSession? {
        if let stored = TokenStepSecrets.get(.grokAccessToken), looksLikeSessionToken(stored) {
            return GrokSession(token: stored, userId: readAuthObject().flatMap(userId(from:)))
        }
        guard let object = readAuthObject(), !isPlainXAIKey(object) else { return nil }
        return session(from: object)
    }

    private static func readAuthObject() -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: authURL.path),
              let data = try? Data(contentsOf: authURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }

    private static func session(from object: [String: Any]) -> GrokSession? {
        if let token = token(in: object) {
            return GrokSession(token: token, userId: userId(from: object))
        }
        return nil
    }

    private static func userId(from object: [String: Any]) -> String? {
        let keys = ["user_id", "userId", "principal_id", "principalId"]
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }
        for value in object.values {
            if let nested = value as? [String: Any], let userId = userId(from: nested) {
                return userId
            }
        }
        return nil
    }

    private static func isPlainXAIKey(_ object: [String: Any]) -> Bool {
        let values = [object["api_key"], object["apiKey"], object["key"]].compactMap { $0 as? String }
        return values.contains { $0.hasPrefix("xai-") } && token(in: object) == nil
    }

    private static func token(in object: [String: Any]) -> String? {
        let keys = ["access_token", "accessToken", "sessionToken", "token", "key"]
        for key in keys {
            if let value = object[key] as? String, looksLikeSessionToken(value) {
                return value
            }
        }
        for value in object.values {
            if let nested = value as? [String: Any], let token = token(in: nested) {
                return token
            }
        }
        return nil
    }

    private static func cent(_ value: Any?) -> Double? {
        if let number = QuotaJSON.number(value) { return number }
        if let object = value as? [String: Any] {
            return QuotaJSON.number(object["val"] ?? object["value"])
        }
        return nil
    }

    private static func date(from value: Any?) -> Date? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        if let date = ISO8601DateFormatter.grok.date(from: text) {
            return date
        }
        return ISO8601DateFormatter.grokNoFraction.date(from: text)
    }

    private static var endpoints: [URL] {
        [
            "https://cli-chat-proxy.grok.com/v1/billing?format=credits",
            "https://cli-chat-proxy.grok.com/v1/billing"
        ].compactMap(URL.init(string:))
    }
}

private struct GrokSession {
    var token: String
    var userId: String?
}

private extension ISO8601DateFormatter {
    static let grok: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let grokNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
