import Foundation

enum TokenStepSecrets {
    static let service = "TokenStep-credentials"

    enum Account: String {
        case glmAPIKey = "glm-api-key"
        case kimiAccessToken = "kimi-access-token"
        case grokAccessToken = "grok-access-token"
    }

    static func has(_ account: Account) -> Bool {
        get(account) != nil
    }

    static func get(_ account: Account) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-a", account.rawValue, "-w"]
        process.standardOutput = output
        process.standardError = Pipe()
        // waitUntilExit() runs the main run loop and can reenter SwiftUI observers,
        // which has crashed the app. Drain output and poll exit state instead.
        let errPipe = Pipe()
        process.standardError = errPipe
        var stdoutData = Data()
        var stderrData = Data()
        guard (try? process.run()) != nil else { return nil }
        while process.isRunning {
            stdoutData.append(output.fileHandleForReading.availableData)
            stderrData.append(errPipe.fileHandleForReading.availableData)
            if !process.isRunning { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        stdoutData.append(output.fileHandleForReading.readDataToEndOfFile())
        guard process.terminationStatus == 0 else { return nil }
        let text = String(data: stdoutData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }

    static func set(_ account: Account, value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            delete(account)
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "add-generic-password",
            "-U",
            "-s", service,
            "-a", account.rawValue,
            "-w", trimmed
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        // See get(): poll exit state instead of run-loop pumping waitUntilExit().
        _ = try? process.run()
        while process.isRunning {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    static func delete(_ account: Account) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["delete-generic-password", "-s", service, "-a", account.rawValue]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        // See get(): poll exit state instead of run-loop pumping waitUntilExit().
        _ = try? process.run()
        while process.isRunning {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
}

extension QuotaProviderID {
    var secretAccount: TokenStepSecrets.Account? {
        switch self {
        case .glm: return .glmAPIKey
        case .kimi: return .kimiAccessToken
        case .grok: return .grokAccessToken
        default: return nil
        }
    }

    var needsManualCredential: Bool {
        secretAccount != nil
    }
}
