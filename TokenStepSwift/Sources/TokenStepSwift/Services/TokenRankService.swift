import Foundation

enum AgentWorkRankService {
    static let defaultClient = "all"
    static let defaultRange = "today"
    static let defaultUsageMode = "all"
    static let cacheTTL: TimeInterval = 30 * 60
    static let leaderboardPageURL = URL(string: "https://www.zhenganhuo.com/token-rank")!
    static let myPageURL = URL(string: "https://www.zhenganhuo.com/token-rank/me")!

    // Opt-in privacy test hooks (E0-T03): tests inject counters here to assert that
    // hidden/disabled visibility performs zero identity reads and zero requests.
    static var localIdentityLoaderOverride: ((URL) -> AgentWorkRankIdentity)?
    static var leaderboardClientOverride: ((String, String, String) async throws -> TokenRankLeaderboard)?

    private static let leaderboardAPIURL = URL(
        string: "https://www.zhenganhuo.com/api/token-rank/leaderboard.php"
    )!

    static func fetchLeaderboard(
        client: String = defaultClient,
        range: String = defaultRange,
        usageMode: String = defaultUsageMode
    ) async throws -> TokenRankLeaderboard {
        if let leaderboardClientOverride {
            return try await leaderboardClientOverride(client, range, usageMode)
        }
        var components = URLComponents(url: leaderboardAPIURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client", value: client),
            URLQueryItem(name: "range", value: range),
            URLQueryItem(name: "usage_mode", value: usageMode)
        ]

        guard let url = components?.url else {
            throw TokenRankServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw TokenRankServiceError.unavailable
        }
        return try decodeLeaderboard(data: data)
    }

    static func decodeLeaderboard(
        data: Data,
        fetchedAt: Date = Date()
    ) throws -> TokenRankLeaderboard {
        let decoded = try JSONDecoder().decode(TokenRankLeaderboardResponse.self, from: data)
        guard decoded.success else {
            throw TokenRankServiceError.unavailable
        }
        let payload = decoded.data
        return TokenRankLeaderboard(
            fetchedAt: fetchedAt,
            range: payload.range,
            client: payload.client,
            usageMode: payload.usageMode,
            totalTokens: payload.totalTokens,
            totalRankedUsers: payload.totalRankedUsers,
            topLimit: payload.topLimit,
            entries: payload.rows
        )
    }

    static func loadLocalIdentity(
        clientStateURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".token-rank/client-state.json")
    ) -> AgentWorkRankIdentity? {
        if let localIdentityLoaderOverride {
            return localIdentityLoaderOverride(clientStateURL)
        }
        guard let data = try? Data(contentsOf: clientStateURL),
              let state = try? JSONDecoder().decode(LocalClientState.self, from: data),
              let user = state.user,
              user.id > 0
        else {
            return nil
        }
        return AgentWorkRankIdentity(
            id: user.id,
            name: user.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? L("匿名用户")
                : user.name,
            avatarURL: user.avatarURL,
            lastSyncedAt: state.lastSuccessfulSyncAt.flatMap(parseDate)
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }
}

private struct LocalClientState: Decodable {
    var user: LocalClientUser?
    var lastSuccessfulSyncAt: String?

    enum CodingKeys: String, CodingKey {
        case user
        case lastSuccessfulSyncAt = "last_successful_sync_at"
    }
}

private struct LocalClientUser: Decodable {
    var id: Int
    var name: String
    var avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case avatarURL = "avatar_url"
    }
}

enum TokenRankServiceError: LocalizedError {
    case invalidURL
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return L("榜单地址不可用")
        case .unavailable:
            return L("暂时无法读取榜单")
        }
    }
}
