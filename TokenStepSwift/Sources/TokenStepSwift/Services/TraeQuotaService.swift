import Foundation

/// Trae IDE 接口的鉴权失败。分开建模是为了让设置页能区分
/// 「令牌类型不对」与「登录过期」，而不是永远一句笼统的 401。
enum TraeAuthError: LocalizedError {
    case invalidTokenFormat(length: Int)
    case rejected(apiCode: Int?, httpStatus: Int?)
    case httpFailure(status: Int)

    var errorDescription: String? {
        switch self {
        case .invalidTokenFormat(let length):
            return LFormat("保存的令牌不是 Trae IDE 版 JWT（长度 %@，应为 3 段），请点「用浏览器登录」重新获取", String(length))
        case .rejected(let apiCode, let httpStatus):
            var details: [String] = []
            // 用 %@ 传字符串：LFormat 的 %d 会按当前 locale 加千分位（1001 → "1,001"）。
            if let httpStatus { details.append(LFormat("HTTP %@", String(httpStatus))) }
            if let apiCode { details.append(LFormat("code %@", String(apiCode))) }
            let detail = details.isEmpty ? L("HTTP 401") : details.joined(separator: L("，"))
            return LFormat("Trae 鉴权失败（%@）：登录已过期或令牌无效，请点「用浏览器登录」重新授权", detail)
        case .httpFailure(let status):
            return LFormat("Trae 接口返回 HTTP %@", String(status))
        }
    }
}

/// Trae / Trae CN 凭证的解析顺序：
/// 钥匙串里的访问令牌 → 失败且是鉴权问题 → 用 refresh token 换新令牌 → 再试一次。
/// 全链路失败时抛出带处理指引的错误，不静默。
/// 依赖全部由调用方注入，便于单测覆盖「刷新成功 / 刷新失败 / 回退」三条路径。
enum TraeQuotaAuth {
    static func load(
        provider: QuotaProviderID,
        token: () -> String?,
        refreshToken: () -> String?,
        refresh: (String) throws -> TraeSignInService.Credentials,
        save: (TraeSignInService.Credentials) -> Void,
        fetch: (String) throws -> Any
    ) throws -> Any {
        let existing = token().flatMap { $0.isEmpty ? nil : $0 }
        if let existing {
            do {
                return try fetch(existing)
            } catch {
                guard isAuthFailure(error) else { throw error }
                guard let stored = refreshToken(), !stored.isEmpty else {
                    throw reauthError(provider: provider, reason: error.localizedDescription)
                }
                let renewed = try renew(
                    provider: provider, refreshToken: stored, refresh: refresh, save: save
                )
                do {
                    return try fetch(renewed.token)
                } catch {
                    throw reauthError(provider: provider, reason: error.localizedDescription)
                }
            }
        }
        guard let stored = refreshToken(), !stored.isEmpty else {
            throw TokenStepError.message(notLoggedInMessage(provider))
        }
        let renewed = try renew(
            provider: provider, refreshToken: stored, refresh: refresh, save: save
        )
        do {
            return try fetch(renewed.token)
        } catch {
            throw reauthError(provider: provider, reason: error.localizedDescription)
        }
    }

    /// HTTP 401 / code 1001 / 令牌过期都归为「该换令牌了」。
    static func isAuthFailure(_ error: Error) -> Bool {
        if let auth = error as? TraeAuthError {
            switch auth {
            case .invalidTokenFormat, .rejected:
                return true
            case .httpFailure:
                return false
            }
        }
        let text = error.localizedDescription
        return text.contains("401")
            || text.contains("未登录")
            || text.contains("令牌")
            || text.contains("1001")
    }

    private static func renew(
        provider: QuotaProviderID,
        refreshToken: String,
        refresh: (String) throws -> TraeSignInService.Credentials,
        save: (TraeSignInService.Credentials) -> Void
    ) throws -> TraeSignInService.Credentials {
        do {
            let credentials = try refresh(refreshToken)
            guard !credentials.token.isEmpty else {
                throw TokenStepError.message(L("刷新结果没有访问令牌"))
            }
            save(credentials)
            return credentials
        } catch {
            throw reauthError(provider: provider, reason: error.localizedDescription)
        }
    }

    static func notLoggedInMessage(_ provider: QuotaProviderID) -> String {
        LFormat("未登录 %@，请在设置点「用浏览器登录」，或粘贴访问令牌", provider.displayName)
    }

    private static func reauthError(provider: QuotaProviderID, reason: String) -> Error {
        TokenStepError.message(
            LFormat("%@ 登录不可用（%@）。请在设置点「用浏览器登录」重新授权", provider.displayName, reason)
        )
    }
}

/// Trae CN（trae.cn，中国版）额度。
/// 数据来源：Trae CN 客户端实际调用的官方接口（在本机 main.log 中观察到
/// `https://api.trae.cn/trae/api/v2/pay/ide_user_ent_usage`），口径为 credits。
/// 认证：IDE 同款 `Authorization: Cloud-IDE-JWT <jwt>`（Bearer 会被拒绝，
/// 已用真实账号令牌实测）。客户端本地登录态是私有加密格式（storage.json 中
/// iCubeAuthInfo），TokenStep 读不了，因此令牌来自设置页的「用浏览器登录」
/// （见 `TraeSignInService`），手动粘贴仍作为兜底。令牌只写钥匙串。
enum TraeCNQuotaService {
    static func read() throws -> ProviderQuota {
        let payload = try TraeQuotaAuth.load(
            provider: .traeCN,
            token: { TokenStepSecrets.get(.traeCNAccessToken) },
            refreshToken: { TraeSignInService.storedRefreshToken(provider: .traeCN) },
            refresh: { try TraeSignInService.refresh(provider: .traeCN, refreshToken: $0) },
            save: { TraeSignInService.save($0, provider: .traeCN) },
            fetch: { token in try fetchPayload(token: token) }
        )
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

    /// 真实账号实测：`Authorization: Bearer <jwt>` 会被拒为 HTTP 401 / code 1001，
    /// 换成 IDE 自己用的 `Cloud-IDE-JWT` 方案才返回 200 与额度包。
    static func fetchPayload(token: String) throws -> Any {
        try traeAuthorizedPayload(
            token: token,
            url: endpoint,
            body: JSONSerialization.data(withJSONObject: ["require_usage": true, "req_source": 0])
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
/// 认证与 CN 版一致：IDE 同款 `Cloud-IDE-JWT` 头 + 浏览器授权令牌 + 自动刷新。
enum TraeQuotaService {
    static func read() throws -> ProviderQuota {
        let payload = try TraeQuotaAuth.load(
            provider: .trae,
            token: { TokenStepSecrets.get(.traeAccessToken) },
            refreshToken: { TraeSignInService.storedRefreshToken(provider: .trae) },
            refresh: { try TraeSignInService.refresh(provider: .trae, refreshToken: $0) },
            save: { TraeSignInService.save($0, provider: .trae) },
            fetch: { token in try fetchPayload(token: token) }
        )
        let windows = windows(from: payload)
        guard !windows.isEmpty else {
            throw TokenStepError.message(L("Trae 额度暂不可用"))
        }
        return ProviderQuota(
            provider: .trae,
            windows: windows,
            status: .available,
            fetchedAt: Date(),
            message: nil
        )
    }

    /// 依次尝试 SG / US 两个部署，返回第一个有额度包的响应。
    static func fetchPayload(token: String) throws -> Any {
        var lastError: Error = TokenStepError.message(L("Trae 额度暂不可用"))
        for url in endpoints {
            do {
                let payload = try traeAuthorizedPayload(token: token, url: url, body: Data("{}".utf8))
                if !windows(from: payload).isEmpty {
                    return payload
                }
                lastError = TokenStepError.message(L("Trae 额度暂不可用"))
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

/// Trae IDE 接口的鉴权头是 `Authorization: Cloud-IDE-JWT <jwt>`（IDE 实现同款）。
/// 已用真实账号令牌实测：Bearer 方案返回 HTTP 401 / code 1001，换成
/// Cloud-IDE-JWT 后返回 200，`user_entitlement_pack_list` 与 `usage_summary` 正常。
/// 同时保留 HTTP 状态与业务 code，便于把「令牌类型不对」「登录过期」区分出来。
private func traeAuthorizedPayload(token: String, url: URL, body: Data) throws -> Any {
    guard traeLooksLikeJWT(token) else {
        throw TraeAuthError.invalidTokenFormat(length: token.count)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 8
    request.setValue("Cloud-IDE-JWT \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = body
    let (data, response) = try HTTPJSONClient.transport(request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 200
    let payload = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    let apiCode = (payload as? [String: Any])
        .flatMap { QuotaJSON.number($0["code"]) }
        .map { Int($0) }
    if !(200..<300).contains(status) {
        if status == 401 || apiCode == 1001 {
            throw TraeAuthError.rejected(apiCode: apiCode, httpStatus: status)
        }
        throw TraeAuthError.httpFailure(status: status)
    }
    if apiCode == 1001 {
        throw TraeAuthError.rejected(apiCode: 1001, httpStatus: nil)
    }
    return payload
}

/// 浏览器登录与 ExchangeToken 拿到的都是 JWT（`header.payload.signature`）。
/// 手动粘贴里混入 API key 之类的非 JWT 值时提前给出明确提示。
private func traeLooksLikeJWT(_ token: String) -> Bool {
    let segments = token.split(separator: ".", omittingEmptySubsequences: false)
    return segments.count == 3
        && segments[0].hasPrefix("eyJ")
        && !segments[1].isEmpty
        && !segments[2].isEmpty
}

/// end_time / expire_time 可能是秒或毫秒级 Unix 时间戳（数字或字符串）。
private func epochDate(_ value: Any?) -> Date? {
    guard var seconds = QuotaJSON.number(value), seconds > 0 else { return nil }
    if seconds > 1_000_000_000_000 { seconds /= 1000 }
    return Date(timeIntervalSince1970: seconds)
}
