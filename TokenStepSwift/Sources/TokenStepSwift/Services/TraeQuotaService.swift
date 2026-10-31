import Foundation

/// Trae CN（trae.cn，中国版）额度。
/// 数据来源：Trae CN 客户端实际调用的官方接口（在本机 main.log 中观察到
/// `https://api.trae.cn/trae/api/v2/pay/ide_user_ent_usage`），口径为 credits。
/// 认证：Bearer access token。TokenStep 无法解密客户端本地加密存储的登录态
/// （storage.json 中 iCubeAuthInfo 为客户端私有加密），需要用户在设置里粘贴
/// 登录 trae.cn 后的访问令牌，令牌只写入钥匙串。
enum TraeCNQuotaService {
    static func read() throws -> ProviderQuota {
        guard let token = TokenStepSecrets.get(.traeCNAccessToken), !token.isEmpty else {
            throw TokenStepError.message(L("未登录 Trae CN，请在设置中粘贴访问令牌"))
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["require_usage": true, "req_source": 0])
        let payload = try HTTPJSONClient.jsonObject(for: request)
        try throwIfAuthFailed(payload)
        let windows = windows(from: payload)
        guard !windows.isEmpty else {
            throw TokenStepError.message(L("Trae CN 额度暂不可用"))
        }
        return ProviderQuota(
            provider: .traeCN,
            windows: windows,
            status: .available,
            fetchedAt: Date(),
            message: nil
        )
    }

    /// 汇总所有额度包：credits_limit（-1 表示不限量）与已用 credits_amount。
    static func windows(from payload: Any) -> [QuotaWindow] {
        let object = (payload as? [String: Any]) ?? [:]
        let packs = (object["user_entitlement_pack_list"] as? [Any]) ?? []
        var limit = 0.0
        var used = 0.0
        var unlimited = false
        var soonest: Date?
        for pack in packObjects(packs) {
            let base = (pack["entitlement_base_info"] as? [String: Any]) ?? [:]
            let quota = (base["quota"] as? [String: Any]) ?? [:]
            guard let creditsLimit = QuotaJSON.number(quota["credits_limit"]) else { continue }
            let creditsUsed = QuotaJSON.number((pack["usage"] as? [String: Any])?["credits_amount"]) ?? 0
            if creditsLimit == -1 {
                unlimited = true
            } else if creditsLimit >= 0 {
                limit += creditsLimit
                used += max(creditsUsed, 0)
            }
            if let end = epochDate(base["end_time"] ?? base["expire_time"] ?? pack["end_time"]),
               soonest == nil || end < soonest! {
                soonest = end
            }
        }
        // 不限量没有百分比口径，按客户端面板处理方式不显示额度窗。
        guard !unlimited, limit > 0 else { return [] }
        let usedPercent = min(max(used / limit * 100, 0), 100)
        return [
            QuotaWindow(
                kind: .monthlyCredits,
                usedPercent: usedPercent,
                remaining: max(limit - used, 0),
                total: limit,
                resetsAt: soonest
            )
        ]
    }

    private static var endpoint: URL {
        URL(string: "https://api.trae.cn/trae/api/v2/pay/ide_user_ent_usage")!
    }
}

/// Trae（trae.ai，国际版）额度。
/// 数据来源：与 Trae CN 同族的官方 pay 接口，国际版走美元用量口径
/// `user_current_entitlement_list`（SG 部署 api-sg-central.trae.ai，
/// US 部署 api-us-east.trae.ai）。接口路径与字段口径参考公开社区实现
/// （opencode-trae-auth），端点存在性已用未认证请求验证（返回 code 1001）。
/// 认证同样需要用户在设置里粘贴登录态访问令牌，只进钥匙串。
enum TraeQuotaService {
    static func read() throws -> ProviderQuota {
        guard let token = TokenStepSecrets.get(.traeAccessToken), !token.isEmpty else {
            throw TokenStepError.message(L("未登录 Trae，请在设置中粘贴访问令牌"))
        }
        var lastError: Error = TokenStepError.message(L("Trae 额度暂不可用"))
        for url in endpoints {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 8
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.httpBody = Data("{}".utf8)
                let payload = try HTTPJSONClient.jsonObject(for: request)
                try throwIfAuthFailed(payload)
                let windows = windows(from: payload)
                if !windows.isEmpty {
                    return ProviderQuota(
                        provider: .trae,
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

    /// 美元口径：basic_usage_limit + bonus_usage_limit 为周期总量，
    /// basic_usage_amount + bonus_usage_amount 为已用量。
    static func windows(from payload: Any) -> [QuotaWindow] {
        let object = (payload as? [String: Any]) ?? [:]
        let packs = packObjects((object["user_entitlement_pack_list"] as? [Any]) ?? [])
        guard let pack = packs.first(where: {
            $0["usage"] != nil || ($0["entitlement_base_info"] as? [String: Any])?["quota"] != nil
        }) else { return [] }
        let base = (pack["entitlement_base_info"] as? [String: Any]) ?? [:]
        let quota = (base["quota"] as? [String: Any]) ?? [:]
        let total = (QuotaJSON.number(quota["basic_usage_limit"]) ?? 0)
            + (QuotaJSON.number(quota["bonus_usage_limit"]) ?? 0)
        let usage = (pack["usage"] as? [String: Any]) ?? [:]
        let used = (QuotaJSON.number(usage["basic_usage_amount"]) ?? 0)
            + (QuotaJSON.number(usage["bonus_usage_amount"]) ?? 0)
        guard total > 0 else { return [] }
        let usedPercent = min(max(used / total * 100, 0), 100)
        return [
            QuotaWindow(
                kind: .spend,
                usedPercent: usedPercent,
                remaining: max(total - used, 0),
                total: total,
                resetsAt: epochDate(base["end_time"])
            )
        ]
    }

    private static var endpoints: [URL] {
        [
            "https://api-sg-central.trae.ai/trae/api/v1/pay/user_current_entitlement_list",
            "https://api-us-east.trae.ai/trae/api/v1/pay/user_current_entitlement_list"
        ].compactMap(URL.init(string:))
    }
}

private func packObjects(_ packs: [Any]) -> [[String: Any]] {
    packs.compactMap { $0 as? [String: Any] }
}

/// 未认证时 Trae 接口返回 code 1001（已用未认证请求验证）。
private func throwIfAuthFailed(_ payload: Any) throws {
    guard let object = payload as? [String: Any],
          let code = QuotaJSON.number(object["code"]), code == 1001
    else { return }
    throw TokenStepError.message(L("未登录或令牌已过期"))
}

/// end_time / expire_time 可能是秒或毫秒级 Unix 时间戳（数字或字符串）。
private func epochDate(_ value: Any?) -> Date? {
    guard var seconds = QuotaJSON.number(value), seconds > 0 else { return nil }
    if seconds > 1_000_000_000_000 { seconds /= 1000 }
    return Date(timeIntervalSince1970: seconds)
}
