import Foundation

enum CodexExecutableResolver {
    static func resolveExecutable(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        for candidate in executableCandidates(environment: environment) {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate).standardizedFileURL
            }
        }
        return nil
    }

    static func augmentedPATH(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let existingDirectories = pathDirectories(environment: environment)
        return unique(existingDirectories + fallbackDirectories(environment: environment))
            .joined(separator: ":")
    }

    private static func executableCandidates(environment: [String: String]) -> [String] {
        unique(pathDirectories(environment: environment) + fallbackDirectories(environment: environment))
            .map { URL(fileURLWithPath: $0).appendingPathComponent("codex").path }
    }

    private static func pathDirectories(environment: [String: String]) -> [String] {
        (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func fallbackDirectories(environment: [String: String]) -> [String] {
        let home = homeDirectory(environment: environment)
        return [
            "\(home)/.local/bin",
            "\(home)/.codex/packages/standalone/current/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.bun/bin",
            "\(home)/.cargo/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
    }

    private static func homeDirectory(environment: [String: String]) -> String {
        if let home = environment["HOME"], !home.isEmpty {
            return home
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
