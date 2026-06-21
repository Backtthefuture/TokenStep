import Foundation

enum TokenRankService {
    static let defaultBoard = "total"
    static let defaultRange = "today"
    static let cacheTTL: TimeInterval = 120
    static let leaderboardPageURL = URL(string: "https://scys.com/tokenrank/")!

    private static let leaderboardAPIURL = URL(string: "https://scys.com/tokenrank/api/subapp/leaderboard")!

    static func userPageURL(userID: String) -> URL? {
        let cleanedID = TokenStepSettings.cleanedTokenRankUserID(userID)
        guard !cleanedID.isEmpty else { return nil }
        return URL(string: "https://scys.com/tokenrank/u/")?.appendingPathComponent(cleanedID)
    }

    static func fetchLeaderboard(
        board: String = defaultBoard,
        range: String = defaultRange
    ) async throws -> TokenRankLeaderboard {
        var components = URLComponents(url: leaderboardAPIURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "board", value: board),
            URLQueryItem(name: "range", value: range)
        ]

        guard let url = components?.url else {
            throw TokenRankServiceError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw TokenRankServiceError.unavailable
        }

        let decoded = try JSONDecoder().decode(TokenRankLeaderboardResponse.self, from: data)
        guard decoded.status ?? 0 == 0 else {
            throw TokenRankServiceError.unavailable
        }

        return TokenRankLeaderboard(
            fetchedAt: Date(),
            board: decoded.board,
            range: decoded.range,
            entries: decoded.entries
        )
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
