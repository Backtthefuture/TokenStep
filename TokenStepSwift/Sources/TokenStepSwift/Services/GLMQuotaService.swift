import Foundation

enum GLMQuotaService {
    static func read() throws -> ProviderQuota {
        guard let key = apiKey() else {
            throw TokenStepError.message(L("未配置 GLM API Key"))
        }
        if looksLikePayAsYouGo(key) {
            throw TokenStepError.message(L("当前 key 非订阅计划"))
        }

        var lastError: Error = TokenStepError.message(L("GLM 额度暂不可用"))
        for url in endpoints {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 6
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let object = try HTTPJSONClient.jsonObject(for: request)
                let windows = windows(from: object)
                if !windows.isEmpty {
                    return ProviderQuota(
                        provider: .glm,
                        windows: windows,
                        status: .available,
                        fetchedAt: Date(),
                        message: nil
                    )
                }
            } catch {
                lastError = classified(error)
            }
        }
        throw lastError
    }

    private static func apiKey() -> String? {
        let names = ["ZAI_API_KEY", "ZHIPUAI_API_KEY", "GLM_API_KEY"]
        for name in names {
            if let value = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return TokenStepSecrets.get(.glmAPIKey)
    }

    private static func looksLikePayAsYouGo(_ key: String) -> Bool {
        key.lowercased().contains("payg") || key.lowercased().hasPrefix("sk-pay")
    }

    private static var endpoints: [URL] {
        [
            "https://open.bigmodel.cn/api/paas/v4/usage",
            "https://open.bigmodel.cn/api/biz/v1/subscription/usage",
            "https://api.z.ai/api/coding/usage"
        ].compactMap(URL.init(string:))
    }

    static func windows(from payload: Any) -> [QuotaWindow] {
        let object = unwrap(payload)
        var windows: [QuotaWindow] = []
        let candidates: [(Any?, QuotaWindowKind)] = [
            (object["token_window"] ?? object["tokenWindow"], .tokenWindow),
            (object["daily"] ?? object["day"], .fiveHour),
            (object["monthly"] ?? object["month"] ?? object["subscription"], .monthlyCredits)
        ]
        for (value, kind) in candidates {
            if let nested = value as? [String: Any], let window = window(from: nested, kind: kind) {
                windows.append(window)
            }
        }
        if windows.isEmpty, let window = window(from: object, kind: .monthlyCredits) {
            windows.append(window)
        }
        return windows
    }

    private static func unwrap(_ payload: Any) -> [String: Any] {
        if let object = payload as? [String: Any] {
            if let data = object["data"] as? [String: Any] {
                return data
            }
            return object
        }
        return [:]
    }

    private static func window(from object: [String: Any], kind: QuotaWindowKind) -> QuotaWindow? {
        let used = QuotaJSON.number(object["used"] ?? object["used_percent"] ?? object["utilization"])
        let remaining = QuotaJSON.number(object["remaining"] ?? object["remain"] ?? object["left"])
        let total = QuotaJSON.number(object["total"] ?? object["limit"] ?? object["quota"])
        guard let usedPercent = QuotaJSON.percent(used: used, remaining: remaining, total: total) else {
            return nil
        }
        return QuotaWindow(kind: kind, usedPercent: usedPercent, remaining: remaining, total: total, resetsAt: nil)
    }

    private static func classified(_ error: Error) -> Error {
        let text = error.localizedDescription
        if text.contains("401") || text.contains("403") {
            return TokenStepError.message(L("当前 key 非订阅计划"))
        }
        return error
    }
}
