import Foundation

enum AutostartService {
    static let label = "com.huangshu.TokenStep.login"

    static var plistURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static var canEnableForCurrentBundle: Bool {
        isInstalledApplication(Bundle.main.bundleURL)
    }

    static func setEnabled(_ enabled: Bool) throws {
        let domain = "gui/\(getuid())"
        if enabled {
            guard canEnableForCurrentBundle else {
                throw TokenStepError.message(L("请先把 TokenStep 拖到 Applications 后再开启开机启动。"))
            }

            try FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(at: AppPaths.logs, withIntermediateDirectories: true)
            let payload: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", Bundle.main.bundleURL.path],
                "RunAtLoad": true,
                "KeepAlive": false,
                "StandardOutPath": AppPaths.logs.appendingPathComponent("login.out.log").path,
                "StandardErrorPath": AppPaths.logs.appendingPathComponent("login.err.log").path
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            _ = launchctl(["bootout", domain, plistURL.path])
            _ = launchctl(["bootstrap", domain, plistURL.path])
            return
        }

        _ = launchctl(["bootout", domain, plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
    }

    private static func isInstalledApplication(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if path.hasPrefix("/Applications/") {
            return true
        }

        let userApplicationsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL
            .path
        return path.hasPrefix(userApplicationsPath + "/")
    }

    private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
