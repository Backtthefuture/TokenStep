import Foundation

enum ClaudeQuotaService {
    private static let keychainServices = ["Claude Code-credentials"]
    private static let cacheTTL: TimeInterval = 10 * 60
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func read() throws -> CodexQuotaSnapshot {
        if let cached = readFreshCache() {
            return cached
        }

        let token = try readAccessToken()
        let response = try fetchUsage(accessToken: token)
        let snapshot = CodexQuotaSnapshot(
            fetchedAt: Date(),
            fiveHour: window(response.fiveHour, kind: .fiveHour),
            sevenDay: window(response.sevenDay, kind: .sevenDay)
        )
        if snapshot.isAvailable {
            writeCache(snapshot)
        }
        return snapshot
    }

    private static func window(_ payload: ClaudeUsageWindowPayload?, kind: CodexQuotaWindow.Kind) -> CodexQuotaWindow? {
        guard let payload,
              let usedPercent = normalizedPercent(payload.utilization)
        else { return nil }
        return CodexQuotaWindow(
            kind: kind,
            usedPercent: usedPercent,
            resetsAt: date(from: payload.resetsAt)
        )
    }

    private static func normalizedPercent(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        if value <= 0 { return 0 }
        if value <= 1 { return min(value * 100, 100) }
        return min(value, 100)
    }

    private static func readAccessToken() throws -> String {
        for service in keychainServices {
            guard let raw = readKeychainPassword(service: service),
                  let data = raw.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let oauth = object["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String,
                  !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            return token
        }
        throw TokenStepError.message(L("暂未读取到 Claude Code 额度"))
    }

    private static func readKeychainPassword(service: String) -> String? {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fetchUsage(accessToken: String) throws -> ClaudeUsageResponsePayload {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 6
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error>?
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                result = .failure(TokenStepError.message("Claude API \(http.statusCode)"))
            } else {
                result = .success(data ?? Data())
            }
            semaphore.signal()
        }
        task.resume()

        if semaphore.wait(timeout: .now() + 7) == .timedOut {
            task.cancel()
            throw TokenStepError.message(L("暂未读取到 Claude Code 额度"))
        }

        let data = try result?.get() ?? Data()
        return try JSONDecoder().decode(ClaudeUsageResponsePayload.self, from: data)
    }

    private static func readFreshCache(now: Date = Date()) -> CodexQuotaSnapshot? {
        guard let data = try? Data(contentsOf: AppPaths.claudeQuotaCacheJSON),
              let cache = try? JSONDecoder().decode(ClaudeQuotaCache.self, from: data),
              now.timeIntervalSince(cache.fetchedAt) <= cacheTTL
        else { return nil }

        let snapshot = CodexQuotaSnapshot(
            fetchedAt: cache.fetchedAt,
            fiveHour: usable(cache.fiveHour, now: now),
            sevenDay: usable(cache.sevenDay, now: now)
        )
        return snapshot.isAvailable ? snapshot : nil
    }

    private static func writeCache(_ snapshot: CodexQuotaSnapshot) {
        let cache = ClaudeQuotaCache(
            fetchedAt: snapshot.fetchedAt ?? Date(),
            fiveHour: snapshot.fiveHour,
            sevenDay: snapshot.sevenDay
        )
        do {
            let directory = AppPaths.claudeQuotaCacheJSON.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(cache)
            try data.write(to: AppPaths.claudeQuotaCacheJSON, options: [.atomic])
        } catch {
            // Cache is best-effort; live quota display should not fail because cache write failed.
        }
    }

    private static func usable(_ window: CodexQuotaWindow?, now: Date) -> CodexQuotaWindow? {
        guard let window else { return nil }
        if let resetsAt = window.resetsAt, resetsAt <= now {
            return nil
        }
        return window
    }

    private static func date(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = ISO8601DateFormatter.tokenStep.date(from: value) {
            return date
        }
        return ISO8601DateFormatter.tokenStepNoFraction.date(from: value)
    }
}

private struct ClaudeUsageResponsePayload: Decodable {
    var fiveHour: ClaudeUsageWindowPayload?
    var sevenDay: ClaudeUsageWindowPayload?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct ClaudeUsageWindowPayload: Decodable {
    var utilization: Double?
    var resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

private struct ClaudeQuotaCache: Codable {
    var fetchedAt: Date
    var fiveHour: CodexQuotaWindow?
    var sevenDay: CodexQuotaWindow?
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
