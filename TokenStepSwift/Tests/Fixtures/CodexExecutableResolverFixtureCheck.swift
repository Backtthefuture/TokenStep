import Foundation

@main
struct CodexExecutableResolverFixtureCheck {
    static func main() throws {
        try checkResolvesUserLocalCodexWhenAppPathOmitsIt()
        try checkPathCodexTakesPriorityOverFallbacks()
        try checkStandaloneCodexFallback()
        print("Codex executable resolver fixture checks passed")
    }

    private static func checkResolvesUserLocalCodexWhenAppPathOmitsIt() throws {
        try withTemporaryHome { home in
            let codex = try makeExecutable(at: home.appendingPathComponent(".local/bin/codex"))
            let resolved = CodexExecutableResolver.resolveExecutable(
                environment: [
                    "HOME": home.path,
                    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
                ]
            )
            assertEqual(resolved, codex, "expected ~/.local/bin/codex fallback")
        }
    }

    private static func checkPathCodexTakesPriorityOverFallbacks() throws {
        try withTemporaryHome { home in
            let pathCodex = try makeExecutable(at: home.appendingPathComponent("toolchain/bin/codex"))
            _ = try makeExecutable(at: home.appendingPathComponent(".local/bin/codex"))
            let resolved = CodexExecutableResolver.resolveExecutable(
                environment: [
                    "HOME": home.path,
                    "PATH": pathCodex.deletingLastPathComponent().path
                ]
            )
            assertEqual(resolved, pathCodex, "expected PATH codex to take priority")
        }
    }

    private static func checkStandaloneCodexFallback() throws {
        try withTemporaryHome { home in
            let codex = try makeExecutable(at: home.appendingPathComponent(".codex/packages/standalone/current/bin/codex"))
            let resolved = CodexExecutableResolver.resolveExecutable(
                environment: [
                    "HOME": home.path,
                    "PATH": "/usr/bin:/bin"
                ]
            )
            assertEqual(resolved, codex, "expected standalone Codex fallback")
        }
    }

    private static func withTemporaryHome(_ body: (URL) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStepCodexResolverFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: home)
        }
        try body(home)
    }

    private static func makeExecutable(at url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.standardizedFileURL
    }

    private static func assertEqual(_ actual: URL?, _ expected: URL, _ message: String) {
        guard actual?.standardizedFileURL == expected.standardizedFileURL else {
            fputs("Assertion failed: \(message). got \(actual?.path ?? "nil"), expected \(expected.path)\n", stderr)
            exit(1)
        }
    }
}
