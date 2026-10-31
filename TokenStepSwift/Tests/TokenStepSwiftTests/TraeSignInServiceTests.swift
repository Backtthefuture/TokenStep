import Darwin
import Foundation
import XCTest
@testable import TokenStepSwift

final class TraeSignInServiceTests: XCTestCase {
    override func tearDown() {
        HTTPJSONClient.resetTransport()
        super.tearDown()
    }

    // MARK: - 授权地址

    func testAuthorizationURLUsesNativeIDEQuery() throws {
        let url = try XCTUnwrap(
            TraeSignInService.authorizationURL(
                provider: .traeCN,
                callbackURL: "http://127.0.0.1:51234/authorize",
                machineID: "machine-1",
                deviceID: "device-1",
                traceID: "trace-1"
            )
        )
        XCTAssertEqual(url.host, "www.trae.cn")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(value("login_version"), "1")
        XCTAssertEqual(value("client_id"), "ono9krqynydwx5")
        XCTAssertEqual(value("auth_type"), "local")
        XCTAssertEqual(value("login_channel"), "native_ide")
        XCTAssertEqual(value("auth_callback_url"), "http://127.0.0.1:51234/authorize")
        XCTAssertEqual(value("machine_id"), "machine-1")
        XCTAssertEqual(value("x_device_id"), "device-1")
        XCTAssertEqual(value("x_app_type"), "stable")
        XCTAssertEqual(value("login_trace_id"), "trace-1")
    }

    func testAuthorizationBaseDiffersByProvider() {
        XCTAssertEqual(TraeSignInService.authorizationBase(provider: .traeCN)?.host, "www.trae.cn")
        XCTAssertEqual(TraeSignInService.authorizationBase(provider: .trae)?.host, "www.trae.ai")
        XCTAssertNil(TraeSignInService.authorizationBase(provider: .glm))
    }

    func testExchangePathDiffersByProvider() {
        XCTAssertEqual(
            TraeSignInService.exchangePath(provider: .traeCN),
            "https://api.trae.cn/cloudide/api/v3/trae/oauth/ExchangeToken"
        )
        XCTAssertEqual(
            TraeSignInService.exchangePath(provider: .trae),
            "https://growsg-normal.trae.ai/cloudide/api/v3/trae/oauth/ExchangeToken"
        )
    }

    func testExchangeBodyMatchesIDEContract() throws {
        let data = try XCTUnwrap(TraeSignInService.exchangeBody(provider: .traeCN, refreshToken: "refresh"))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["ClientID"] as? String, "ono9krqynydwx5")
        XCTAssertEqual(object["RefreshToken"] as? String, "refresh")
        XCTAssertEqual(object["ClientSecret"] as? String, "-")
        XCTAssertEqual(object["UserID"] as? String, "")
    }

    // MARK: - 回调解析

    func testParseCallbackReadsUserJWT() {
        let jwt = "{\"Token\":\"jwt-token\",\"RefreshToken\":\"refresh-token\"}"
        XCTAssertEqual(
            TraeSignInService.parseCallback(query: ["userJwt": jwt]),
            .granted(.init(token: "jwt-token", refreshToken: "refresh-token"))
        )
    }

    func testParseCallbackSurfacesAuthorizationError() {
        XCTAssertEqual(
            TraeSignInService.parseCallback(query: ["error": "access_denied"]),
            .failure("access_denied")
        )
        XCTAssertEqual(
            TraeSignInService.parseCallback(query: ["error": "access_denied", "error_description": "用户取消授权"]),
            .failure("用户取消授权")
        )
    }

    func testParseCallbackAcceptsRefreshTokenOnly() {
        XCTAssertEqual(
            TraeSignInService.parseCallback(query: ["refreshToken": "refresh-only"]),
            .granted(.init(token: "", refreshToken: "refresh-only"))
        )
    }

    func testParseCallbackFailsWithoutAnyToken() {
        XCTAssertEqual(TraeSignInService.parseCallback(query: [:]), .failure("登录页没有返回令牌"))
        XCTAssertEqual(TraeSignInService.parseCallback(query: ["userJwt": "not-json"]), .failure("登录页返回的令牌无法解析"))
    }

    func testParseUserJWTAcceptsLowercaseKeys() {
        let jwt = "{\"token\":\"lower-token\",\"refreshToken\":\"lower-refresh\"}"
        XCTAssertEqual(
            TraeSignInService.parseUserJWT(jwt),
            .init(token: "lower-token", refreshToken: "lower-refresh")
        )
        XCTAssertNil(TraeSignInService.parseUserJWT("{}"))
    }

    func testParseExchangeResponseHandlesResultCasing() throws {
        let upper = #"{"Result":{"Token":"upper-token","RefreshToken":"upper-refresh"}}"#
        XCTAssertEqual(
            TraeSignInService.parseExchangeResponse(Data(upper.utf8)),
            .init(token: "upper-token", refreshToken: "upper-refresh")
        )
        let lower = #"{"result":{"token":"lower-token","refreshToken":"lower-refresh"}}"#
        XCTAssertEqual(
            TraeSignInService.parseExchangeResponse(Data(lower.utf8)),
            .init(token: "lower-token", refreshToken: "lower-refresh")
        )
        XCTAssertNil(TraeSignInService.parseExchangeResponse(Data("{}".utf8)))
    }

    func testQueryItemsDecodePercentEncodedTarget() throws {
        let jwt = "{\"Token\":\"a\",\"RefreshToken\":\"b\"}"
        let encoded = jwt.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let target = "/authorize?userJwt=\(encoded)&refreshToken=r"
        let items = TraeSignInService.queryItems(fromRequestTarget: target)
        XCTAssertEqual(items["refreshToken"], "r")
        XCTAssertEqual(items["userJwt"], jwt)
    }

    // MARK: - 刷新（mock transport）

    func testRefreshParsesExchangeToken() throws {
        HTTPJSONClient.transport = { request in
            let body = #"{"Result":{"Token":"new-jwt","RefreshToken":"new-refresh"}}"#
            let response = try XCTUnwrap(
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            return (Data(body.utf8), response)
        }
        let credentials = try TraeSignInService.refresh(provider: .traeCN, refreshToken: "old")
        XCTAssertEqual(credentials.token, "new-jwt")
        XCTAssertEqual(credentials.refreshToken, "new-refresh")
    }

    func testRefreshReportsInvalidToken() {
        HTTPJSONClient.transport = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"ResponseMetadata":{"Error":{"Code":"20101"}}}"#.utf8), response)
        }
        XCTAssertThrowsError(try TraeSignInService.refresh(provider: .traeCN, refreshToken: "bad")) { error in
            let text = error.localizedDescription
            XCTAssertTrue(text.contains("刷新令牌失败"))
            XCTAssertTrue(text.contains("HTTP 401"))
        }
    }

    // 真实端点在无效 refresh token 上返回的 `__Message.error` 会被带进提示
    func testRefreshSurfacesServerErrorMessage() {
        HTTPJSONClient.transport = { request in
            let body = #"{"ResponseMetadata":{"Error":{"Code":"20101","Data":{"__Message.error":"refresh token is invalid"}}}}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
        XCTAssertThrowsError(try TraeSignInService.refresh(provider: .traeCN, refreshToken: "bad")) { error in
            XCTAssertTrue(error.localizedDescription.contains("refresh token is invalid"))
        }
    }

    // MARK: - 凭证加载：直接使用 / 自动刷新 / 回退

    func testLoadUsesExistingTokenWithoutRefresh() throws {
        let payload = ["code": 0]
        var refreshCalls = 0
        var saved: [TraeSignInService.Credentials] = []
        let result = try TraeQuotaAuth.load(
            provider: .traeCN,
            token: { "existing" },
            refreshToken: { "stored-refresh" },
            refresh: { _ in refreshCalls += 1; return .init(token: "unused", refreshToken: nil) },
            save: { saved.append($0) },
            fetch: { token in
                XCTAssertEqual(token, "existing")
                return payload
            }
        )
        XCTAssertEqual(result as? NSDictionary, payload as NSDictionary)
        XCTAssertEqual(refreshCalls, 0)
        XCTAssertTrue(saved.isEmpty)
    }

    func testLoadWithoutAnyCredentialExplainsHowToLogin() {
        XCTAssertThrowsError(
            try TraeQuotaAuth.load(
                provider: .traeCN,
                token: { nil },
                refreshToken: { nil },
                refresh: { _ in XCTFail("不应刷新"); return .init(token: "", refreshToken: nil) },
                save: { _ in },
                fetch: { _ in XCTFail("不应发请求"); return [:] }
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("未登录 Trae CN"))
            XCTAssertTrue(error.localizedDescription.contains("用浏览器登录"))
        }
    }

    func testLoadRefreshesWhenAccessTokenMissing() throws {
        var refreshedFrom: String?
        var saved: TraeSignInService.Credentials?
        let result = try TraeQuotaAuth.load(
            provider: .trae,
            token: { nil },
            refreshToken: { "stored-refresh" },
            refresh: { token in
                refreshedFrom = token
                return .init(token: "fresh-token", refreshToken: "fresh-refresh")
            },
            save: { saved = $0 },
            fetch: { token in
                XCTAssertEqual(token, "fresh-token")
                return ["code": 0]
            }
        )
        XCTAssertEqual(result as? NSDictionary, ["code": 0] as NSDictionary)
        XCTAssertEqual(refreshedFrom, "stored-refresh")
        XCTAssertEqual(saved, .init(token: "fresh-token", refreshToken: "fresh-refresh"))
    }

    func testLoadRetriesAfterAuthFailure() throws {
        var seenTokens: [String] = []
        let result = try TraeQuotaAuth.load(
            provider: .traeCN,
            token: { "expired" },
            refreshToken: { "stored-refresh" },
            refresh: { _ in .init(token: "fresh-token", refreshToken: "fresh-refresh") },
            save: { _ in },
            fetch: { token in
                seenTokens.append(token)
                if token == "expired" {
                    throw TokenStepError.message("HTTP 401")
                }
                return ["code": 0]
            }
        )
        XCTAssertEqual(result as? NSDictionary, ["code": 0] as NSDictionary)
        XCTAssertEqual(seenTokens, ["expired", "fresh-token"])
    }

    func testLoadStopsOnNetworkErrorWithoutRefreshing() {
        XCTAssertThrowsError(
            try TraeQuotaAuth.load(
                provider: .traeCN,
                token: { "existing" },
                refreshToken: { "stored-refresh" },
                refresh: { _ in XCTFail("网络错误不应触发刷新"); return .init(token: "", refreshToken: nil) },
                save: { _ in },
                fetch: { _ in throw TokenStepError.message("请求超时") }
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, "请求超时")
        }
    }

    func testExpiredTokenWithoutRefreshTokenPointsToBrowserLogin() {
        XCTAssertThrowsError(
            try TraeQuotaAuth.load(
                provider: .traeCN,
                token: { "expired" },
                refreshToken: { nil },
                refresh: { _ in XCTFail("没有 refresh token 不应刷新"); return .init(token: "", refreshToken: nil) },
                save: { _ in },
                fetch: { _ in throw TokenStepError.message("HTTP 401") }
            )
        ) { error in
            let text = error.localizedDescription
            XCTAssertTrue(text.contains("登录不可用"))
            XCTAssertTrue(text.contains("用浏览器登录"))
        }
    }

    func testLoadFailsClearlyWhenRefreshFails() {
        XCTAssertThrowsError(
            try TraeQuotaAuth.load(
                provider: .trae,
                token: { nil },
                refreshToken: { "stored-refresh" },
                refresh: { _ in throw TokenStepError.message("refresh token is invalid") },
                save: { _ in },
                fetch: { _ in XCTFail("刷新失败不应再发请求"); return [:] }
            )
        ) { error in
            let text = error.localizedDescription
            XCTAssertTrue(text.contains("登录不可用"))
            XCTAssertTrue(text.contains("refresh token is invalid"))
            XCTAssertTrue(text.contains("用浏览器登录"))
        }
    }

    // MARK: - 本机回调端口（实际跑一次 socket）

    func testLoopbackListenerReceivesCallback() throws {
        let listener = try LoopbackListener()
        let clientDone = expectation(description: "client sent")
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 0.05)
            Self.sendGet(port: listener.port, path: "/authorize?refreshToken=abc&error=")
            clientDone.fulfill()
        }
        let target = try listener.waitForRequest(timeout: 5)
        wait(for: [clientDone], timeout: 5)
        let items = TraeSignInService.queryItems(fromRequestTarget: target)
        XCTAssertEqual(items["refreshToken"], "abc")
    }

    private static func sendGet(port: UInt16, path: String) {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return }
        let request = "GET \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
        _ = request.withCString { send(descriptor, $0, strlen($0), 0) }
        var buffer = [UInt8](repeating: 0, count: 512)
        _ = recv(descriptor, &buffer, buffer.count, 0)
    }
}
