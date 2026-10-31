import AppKit
import Darwin
import Foundation

/// Trae / Trae CN 的浏览器授权登录。
///
/// 走的是客户端 IDE 自己的登录流程：打开 `www.trae.cn/authorization`
/// （国际版为 `www.trae.ai`），页面把 Cloud-IDE-JWT 与 refresh token
/// 回跳到本机 `127.0.0.1` 的回调地址。整个过程不要求用户输入密码，
/// 也不读取浏览器的 cookie 文件；令牌只写钥匙串。
///
/// 流程参数与令牌交换契约参考公开社区实现
/// `@magpie-community/opencode-trae-auth`（自述为逆向 IDE 所得）。
/// 已验证：授权页 `GET` 返回 200；`ExchangeToken` 端点存在且对无效
/// refresh token 返回 401 / `refresh token is invalid`。
/// 未验证：完整登录回跳（需要真实账号在浏览器完成授权）。
enum TraeSignInService {
    struct Credentials: Equatable {
        var token: String
        var refreshToken: String?
    }

    enum CallbackResult: Equatable {
        case granted(Credentials)
        case failure(String)
    }

    // MARK: - 纯函数（可单测）

    static func authorizationBase(provider: QuotaProviderID) -> URL? {
        switch provider {
        case .traeCN: return URL(string: "https://www.trae.cn/authorization")
        case .trae: return URL(string: "https://www.trae.ai/authorization")
        default: return nil
        }
    }

    static func exchangePath(provider: QuotaProviderID) -> String {
        provider == .traeCN
            ? "https://api.trae.cn/cloudide/api/v3/trae/oauth/ExchangeToken"
            : "https://growsg-normal.trae.ai/cloudide/api/v3/trae/oauth/ExchangeToken"
    }

    static func clientID(provider: QuotaProviderID) -> String {
        "ono9krqynydwx5"
    }

    /// 拼授权页地址。参数名沿用 IDE 登录页实际读取的那一组。
    static func authorizationURL(
        provider: QuotaProviderID,
        callbackURL: String,
        machineID: String,
        deviceID: String,
        traceID: String
    ) -> URL? {
        guard let base = authorizationBase(provider: provider),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        let pluginVersion = provider == .traeCN ? "2.3.24254" : "2.3.62834"
        let appVersion = provider == .traeCN ? "3.3.65" : "3.5.51"
        components.queryItems = [
            URLQueryItem(name: "login_version", value: "1"),
            URLQueryItem(name: "auth_from", value: "solo"),
            URLQueryItem(name: "login_channel", value: "native_ide"),
            URLQueryItem(name: "plugin_version", value: pluginVersion),
            URLQueryItem(name: "auth_type", value: "local"),
            URLQueryItem(name: "client_id", value: clientID(provider: provider)),
            URLQueryItem(name: "redirect", value: "0"),
            URLQueryItem(name: "login_trace_id", value: traceID),
            URLQueryItem(name: "auth_callback_url", value: callbackURL),
            URLQueryItem(name: "machine_id", value: machineID),
            URLQueryItem(name: "device_id", value: deviceID),
            URLQueryItem(name: "x_device_id", value: deviceID),
            URLQueryItem(name: "x_machine_id", value: machineID),
            URLQueryItem(name: "x_device_type", value: "mac"),
            URLQueryItem(name: "x_os_version", value: ProcessInfo.processInfo.operatingSystemVersionString),
            URLQueryItem(name: "x_env", value: ""),
            URLQueryItem(name: "x_app_version", value: appVersion),
            URLQueryItem(name: "x_app_type", value: "stable"),
            URLQueryItem(name: "hide_saas_login", value: "false")
        ]
        return components.url
    }

    /// 解析回调的查询串：`userJwt`（URL 编码的 JSON）以及可选的
    /// `refreshToken` / `error` / `error_description`。
    static func parseCallback(query: [String: String]) -> CallbackResult {
        if let error = query["error"], !error.isEmpty {
            let detail = query["error_description"] ?? error
            return .failure(detail)
        }
        if let rawJWT = query["userJwt"], !rawJWT.isEmpty {
            if let parsed = parseUserJWT(rawJWT) { return .granted(parsed) }
            return .failure(L("登录页返回的令牌无法解析"))
        }
        if let refresh = query["refreshToken"], !refresh.isEmpty {
            return .granted(Credentials(token: "", refreshToken: refresh))
        }
        return .failure(L("登录页没有返回令牌"))
    }

    /// `userJwt` 是一个 JSON 串，字段名大小写不一，逐个兼容。
    static func parseUserJWT(_ raw: String) -> Credentials? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let token = stringValue(object["Token"]) ?? stringValue(object["token"]) ?? ""
        let refresh = stringValue(object["RefreshToken"]) ?? stringValue(object["refreshToken"])
        guard !token.isEmpty || refresh != nil else { return nil }
        return Credentials(token: token, refreshToken: refresh)
    }

    /// `ExchangeToken` 的响应：`{"Result": {"Token": "...", "RefreshToken": "..."}}`。
    static func parseExchangeResponse(_ data: Data) -> Credentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let result = (root["Result"] as? [String: Any]) ?? (root["result"] as? [String: Any]) ?? root
        let token = stringValue(result["Token"]) ?? stringValue(result["token"]) ?? ""
        guard !token.isEmpty else { return nil }
        let refresh = stringValue(result["RefreshToken"]) ?? stringValue(result["refreshToken"])
        return Credentials(token: token, refreshToken: refresh)
    }

    static func exchangeBody(provider: QuotaProviderID, refreshToken: String) -> Data? {
        try? JSONSerialization.data(withJSONObject: [
            "ClientID": clientID(provider: provider),
            "RefreshToken": refreshToken,
            "ClientSecret": "-",
            "UserID": ""
        ])
    }

    // MARK: - 登录与刷新

    /// 阻塞式登录：开本机回环端口 → 打开浏览器 → 等回调。调用方需在后台线程。
    static func signIn(provider: QuotaProviderID, timeout: TimeInterval = 240) throws -> Credentials {
        guard authorizationBase(provider: provider) != nil else {
            throw TokenStepError.message(L("Trae 暂不支持浏览器登录"))
        }
        let listener = try LoopbackListener()
        let traceID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        guard let url = authorizationURL(
            provider: provider,
            callbackURL: "http://127.0.0.1:\(listener.port)/authorize",
            machineID: deviceIdentifier(kind: "machine"),
            deviceID: deviceIdentifier(kind: "device"),
            traceID: traceID
        ) else {
            throw TokenStepError.message(L("无法构造登录地址"))
        }
        if Thread.isMainThread {
            NSWorkspace.shared.open(url)
        } else {
            _ = DispatchQueue.main.sync { NSWorkspace.shared.open(url) }
        }
        let target = try listener.waitForRequest(timeout: timeout)
        let query = queryItems(fromRequestTarget: target)
        switch parseCallback(query: query) {
        case .granted(let credentials):
            guard let refresh = credentials.refreshToken, !refresh.isEmpty else {
                throw TokenStepError.message(L("登录页没有返回 refresh token"))
            }
            return credentials
        case .failure(let message):
            throw TokenStepError.message(message)
        }
    }

    /// 用 refresh token 换新 JWT。Trae 每次刷新都会换发新的 refresh token。
    /// 失败时把服务端的 HTTP 状态与 `ResponseMetadata.Error` 文案带出来，
    /// 便于区分「refresh token 已失效」与网络错误。
    static func refresh(provider: QuotaProviderID, refreshToken: String) throws -> Credentials {
        guard let body = exchangeBody(provider: provider, refreshToken: refreshToken) else {
            throw TokenStepError.message(L("无法构造刷新请求"))
        }
        var request = URLRequest(url: URL(string: exchangePath(provider: provider))!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try HTTPJSONClient.transport(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else {
            let detail = exchangeErrorMessage(data).map { LFormat("：%@", $0) } ?? ""
            throw TokenStepError.message(LFormat("刷新令牌失败（HTTP %d%@）", status, detail))
        }
        guard let credentials = parseExchangeResponse(data) else {
            throw TokenStepError.message(L("刷新响应里没有访问令牌，请重新用浏览器登录"))
        }
        return credentials
    }

    /// `{"ResponseMetadata":{"Error":{"Code":"20101","Data":{"__Message.error":"refresh token is invalid"}}}`
    static func exchangeErrorMessage(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = root["ResponseMetadata"] as? [String: Any],
              let error = metadata["Error"] as? [String: Any]
        else { return nil }
        if let message = (error["Data"] as? [String: Any])?["__Message.error"] as? String, !message.isEmpty {
            return message
        }
        if let message = error["Message"] as? String, !message.isEmpty {
            return message
        }
        if let code = error["Code"].map(String.init(describing:)) {
            return LFormat("code %@", code)
        }
        return nil
    }

    static func save(_ credentials: Credentials, provider: QuotaProviderID) {
        guard let tokenAccount = provider.secretAccount else { return }
        if !credentials.token.isEmpty {
            TokenStepSecrets.set(tokenAccount, value: credentials.token)
        }
        if let refresh = credentials.refreshToken, !refresh.isEmpty {
            TokenStepSecrets.set(refreshAccount(provider: provider), value: refresh)
        }
    }

    static func refreshAccount(provider: QuotaProviderID) -> TokenStepSecrets.Account {
        provider == .traeCN ? .traeCNRefreshToken : .traeRefreshToken
    }

    static func storedRefreshToken(provider: QuotaProviderID) -> String? {
        TokenStepSecrets.get(refreshAccount(provider: provider))
    }

    // MARK: - 辅助

    static func queryItems(fromRequestTarget target: String) -> [String: String] {
        guard let components = URLComponents(string: "http://127.0.0.1" + target) else { return [:] }
        var result: [String: String] = [:]
        for item in components.queryItems ?? [] {
            if let value = item.value { result[item.name] = value }
        }
        return result
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty { return text }
        return nil
    }

    /// 设备标识：沿用客户端字段含义，只做一次生成并复用，不是密钥。
    private static func deviceIdentifier(kind: String) -> String {
        let key = "trae-sign-in-device-\(kind)"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let generated = kind == "machine"
            ? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            : String((0 ..< 16).map { _ in Character(String(Int.random(in: 0 ... 9))) })
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }
}

/// 只监听 127.0.0.1 的一次性 HTTP 接收器，用于拿登录回调。
final class LoopbackListener {
    private let descriptor: Int32
    let port: UInt16

    init() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw TokenStepError.message(L("无法创建本地端口"))
        }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, 4)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            close(fd)
            throw TokenStepError.message(L("本地端口被占用"))
        }
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        let resolvedPort = UInt16(bigEndian: actual.sin_port)
        guard listen(fd, 1) == 0 else {
            close(fd)
            throw TokenStepError.message(L("无法监听本地端口"))
        }
        descriptor = fd
        port = resolvedPort
    }

    deinit {
        close(descriptor)
    }

    /// 等一次请求，返回请求行里的路径（含查询串）。
    func waitForRequest(timeout: TimeInterval) throws -> String {
        var event = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        let ready = poll(&event, 1, Int32(timeout * 1000))
        guard ready > 0 else {
            throw TokenStepError.message(L("等待浏览器授权超时，请重试"))
        }
        let client = accept(descriptor, nil, nil)
        guard client >= 0 else {
            throw TokenStepError.message(L("接收登录回调失败"))
        }
        defer { close(client) }
        var buffer = [UInt8](repeating: 0, count: 8192)
        let read = recv(client, &buffer, buffer.count, 0)
        guard read > 0 else {
            throw TokenStepError.message(L("登录回调内容为空"))
        }
        let request = String(decoding: buffer[0 ..< read], as: UTF8.self)
        let target = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        let body = "<html><body style=\"font:15px -apple-system;padding:24px\">登录完成，可以关闭此页面，回到 TokenStep。</body></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        _ = response.withCString { send(client, $0, strlen($0), 0) }
        return target
    }
}
