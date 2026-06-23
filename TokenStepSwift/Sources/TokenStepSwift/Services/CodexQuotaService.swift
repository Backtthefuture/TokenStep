import Foundation

enum CodexQuotaService {
    private static let requestID = 2

    static func read() throws -> CodexQuotaSnapshot {
        let output = try runAppServerRequest()
        let response = try parseRateLimitResponse(output)
        let snapshot = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits
        let windows = classifiedWindows(snapshot)
        return CodexQuotaSnapshot(
            fetchedAt: Date(),
            fiveHour: window(windows.fiveHour, kind: .fiveHour),
            sevenDay: window(windows.sevenDay, kind: .sevenDay)
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

    private static func classifiedWindows(_ snapshot: RateLimitSnapshotPayload) -> (fiveHour: RateLimitWindowPayload?, sevenDay: RateLimitWindowPayload?) {
        var fiveHour: RateLimitWindowPayload?
        var sevenDay: RateLimitWindowPayload?

        for payload in [snapshot.primary, snapshot.secondary].compactMap({ $0 }) {
            switch payload.windowDurationMins {
            case 300:
                if fiveHour == nil { fiveHour = payload }
            case 10_080:
                if sevenDay == nil { sevenDay = payload }
            default:
                continue
            }
        }

        if fiveHour == nil, sevenDay == nil {
            return (fiveHour: snapshot.primary, sevenDay: snapshot.secondary)
        }

        return (fiveHour: fiveHour, sevenDay: sevenDay)
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
        defer {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            try? inputPipe.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
        }

        try process.run()
        do {
            try writeRequests(to: inputPipe.fileHandleForWriting)
        } catch {
            process.terminate()
            throw error
        }

        let _ = responseSemaphore.wait(timeout: .now() + 4)
        process.terminate()

        let exitSemaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            exitSemaphore.signal()
        }

        _ = exitSemaphore.wait(timeout: .now() + 1)

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
            try write(data, to: handle)
            try write(Data("\n".utf8), to: handle)
        }
    }

    private static func write(_ data: Data, to handle: FileHandle) throws {
        do {
            try handle.write(contentsOf: data)
        } catch {
            throw TokenStepError.message(L("暂未读取到 Codex 额度"))
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
