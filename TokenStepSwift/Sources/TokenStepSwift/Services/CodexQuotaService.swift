import Foundation

enum CodexQuotaService {
    private static let requestID = 2

    static func read() throws -> CodexQuotaSnapshot {
        let output = try runAppServerRequest()
        let response = try parseRateLimitResponse(output)
        let snapshot = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits
        return CodexQuotaSnapshot(
            fetchedAt: Date(),
            fiveHour: window(snapshot.primary, kind: .fiveHour),
            sevenDay: window(snapshot.secondary, kind: .sevenDay)
        )
    }

    private static func window(_ payload: RateLimitWindowPayload?, kind: CodexQuotaWindow.Kind) -> CodexQuotaWindow? {
        guard let payload else { return nil }
        return CodexQuotaWindow(
            kind: kind,
            usedPercent: payload.usedPercent,
            resetsAt: payload.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    private static func runAppServerRequest() throws -> String {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputLock = NSLock()
        let errorLock = NSLock()
        let responseSemaphore = DispatchSemaphore(value: 0)
        var output = Data()
        var errorOutput = Data()
        var didReceiveQuotaResponse = false

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "app-server", "--listen", "stdio://"]
        process.environment = appServerEnvironment()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputLock.lock()
            output.append(data)
            if !didReceiveQuotaResponse,
               let text = String(data: output, encoding: .utf8),
               text.contains("\"id\":\(requestID)") {
                didReceiveQuotaResponse = true
                responseSemaphore.signal()
            }
            outputLock.unlock()
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            errorLock.lock()
            errorOutput.append(data)
            errorLock.unlock()
        }

        try process.run()
        try writeRequests(to: inputPipe.fileHandleForWriting)

        let _ = responseSemaphore.wait(timeout: .now() + 4)
        process.terminate()

        let exitSemaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            exitSemaphore.signal()
        }

        _ = exitSemaphore.wait(timeout: .now() + 1)

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        outputLock.lock()
        let outputData = output
        outputLock.unlock()
        errorLock.lock()
        let stderrData = errorOutput
        errorLock.unlock()

        let outputText = String(data: outputData, encoding: .utf8) ?? ""
        if outputText.contains("\"id\":\(requestID)") {
            return outputText
        }

        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
        if !stderrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TokenStepError.message(stderrText)
        }
        throw TokenStepError.message(L("暂未读取到 Codex 额度"))
    }

    private static func writeRequests(to handle: FileHandle) throws {
        let initialize: [String: Any] = [
            "method": "initialize",
            "id": 1,
            "params": [
                "clientInfo": [
                    "name": "tokenstep",
                    "title": "TokenStep",
                    "version": UpdateService.currentVersion
                ],
                "capabilities": NSNull()
            ]
        ]
        let quota: [String: Any] = [
            "method": "account/rateLimits/read",
            "id": requestID
        ]

        for request in [initialize, quota] {
            let data = try JSONSerialization.data(withJSONObject: request)
            handle.write(data)
            handle.write(Data("\n".utf8))
        }
    }

    private static func parseRateLimitResponse(_ text: String) throws -> GetAccountRateLimitsPayload {
        for line in text.split(whereSeparator: \.isNewline) {
            guard
                let data = String(line).data(using: .utf8),
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                object["id"] as? Int == requestID
            else { continue }

            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw TokenStepError.message(message)
            }

            guard let result = object["result"] else {
                throw TokenStepError.message(L("暂未读取到 Codex 额度"))
            }
            let resultData = try JSONSerialization.data(withJSONObject: result)
            return try JSONDecoder().decode(GetAccountRateLimitsPayload.self, from: resultData)
        }

        throw TokenStepError.message(L("暂未读取到 Codex 额度"))
    }

    private static func appServerEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let existing = environment["PATH"], !existing.isEmpty {
            environment["PATH"] = "\(defaultPath):\(existing)"
        } else {
            environment["PATH"] = defaultPath
        }
        return environment
    }
}

private struct GetAccountRateLimitsPayload: Decodable {
    var rateLimits: RateLimitSnapshotPayload
    var rateLimitsByLimitId: [String: RateLimitSnapshotPayload]?

    enum CodingKeys: String, CodingKey {
        case rateLimits
        case rateLimitsByLimitId
    }
}

private struct RateLimitSnapshotPayload: Decodable {
    var primary: RateLimitWindowPayload?
    var secondary: RateLimitWindowPayload?
}

private struct RateLimitWindowPayload: Decodable {
    var usedPercent: Double
    var windowDurationMins: Int?
    var resetsAt: Int?
}
