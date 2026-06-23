import Darwin
import Foundation

@main
enum TokenStepHelper {
    static func main() {
        _ = signal(SIGPIPE, SIG_IGN)
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            fail("Missing helper command.")
        }
        arguments.removeFirst()

        do {
            switch command {
            case "collect":
                let historyDays = arguments.first.flatMap(Int.init) ?? DataService.loadSettings().historyDays
                try DataService.runCollector(historyDays: historyDays)
            case "install":
                try UpdateInstaller(arguments: arguments).run()
            default:
                fail("Unknown helper command: \(command)")
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(1)
    }
}

private struct UpdateInstaller {
    var dmgPath = ""
    var expectedVersion = ""
    var currentPID: pid_t = 0
    var requireVerified = true
    var logPath = ""
    var helperPath = CommandLine.arguments.first ?? ""
    var destinationPath = "/Applications/TokenStep.app"
    var skipRelaunch = false
    var skipStop = false

    init(arguments: [String]) throws {
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let key = arguments[index]
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else {
                throw HelperError.message("Missing value for \(key)")
            }
            let value = arguments[valueIndex]
            switch key {
            case "--dmg":
                dmgPath = value
            case "--version":
                expectedVersion = value
            case "--current-pid":
                currentPID = pid_t(Int32(value) ?? 0)
            case "--require-verified":
                requireVerified = value == "1" || value.lowercased() == "true"
            case "--log":
                logPath = value
            case "--helper-path":
                helperPath = value
            case "--destination":
                destinationPath = value
            case "--skip-relaunch":
                skipRelaunch = value == "1" || value.lowercased() == "true"
            case "--skip-stop":
                skipStop = value == "1" || value.lowercased() == "true"
            default:
                throw HelperError.message("Unknown install argument: \(key)")
            }
            index = arguments.index(after: valueIndex)
        }

        guard !dmgPath.isEmpty, !expectedVersion.isEmpty, !logPath.isEmpty else {
            throw HelperError.message("Missing required install arguments.")
        }
    }

    func run() throws {
        var logger = try HelperLogger(path: logPath)
        var mountPoint: URL?
        var mountRoot: URL?
        var backupURL: URL?

        func cleanup() {
            if let mountPoint {
                _ = try? ProcessRunner.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force", "-quiet"])
            }
            if let mountRoot {
                try? FileManager.default.removeItem(at: mountRoot)
            }
            if !helperPath.isEmpty {
                try? FileManager.default.removeItem(atPath: helperPath)
            }
        }

        do {
            logger.write("TokenStep helper installer started at \(Date())")
            logger.write("Expected version: \(expectedVersion)")
            logger.write("DMG: \(dmgPath)")
            logger.write("Current PID: \(currentPID)")

            detachStaleTokenStepMounts(logger: &logger)
            let mounted = try attachDMG(logger: &logger)
            mountPoint = mounted.mountPoint
            mountRoot = mounted.mountRoot

            let sourceApp = try findTokenStepApp(in: mounted.mountPoint)
            logger.write("Found source app: \(sourceApp.path)")

            if requireVerified {
                logger.write("Verifying source app")
                try ProcessRunner.run("/usr/sbin/spctl", ["--assess", "--type", "execute", sourceApp.path])
                try ProcessRunner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", sourceApp.path])
            }

            let sourceVersion = bundleVersion(sourceApp)
            logger.write("Source version: \(sourceVersion)")
            guard sourceVersion == expectedVersion else {
                throw HelperError.message("Source version mismatch: expected \(expectedVersion), got \(sourceVersion)")
            }

            if skipStop {
                logger.write("Skipping old process stop by request")
            } else {
                stopOldTokenStep(logger: &logger)
            }

            let destination = URL(fileURLWithPath: destinationPath, isDirectory: true)
            backupURL = destination.deletingLastPathComponent()
                .appendingPathComponent("\(destination.lastPathComponent).previous.\(Int(Date().timeIntervalSince1970))", isDirectory: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                logger.write("Backing up existing app to \(backupURL!.path)")
                try? FileManager.default.removeItem(at: backupURL!)
                try FileManager.default.moveItem(at: destination, to: backupURL!)
            }

            logger.write("Copying new app into Applications")
            do {
                try ProcessRunner.run("/usr/bin/ditto", [sourceApp.path, destination.path])
            } catch {
                try? FileManager.default.removeItem(at: destination)
                if let backupURL, FileManager.default.fileExists(atPath: backupURL.path) {
                    try? FileManager.default.moveItem(at: backupURL, to: destination)
                }
                throw error
            }

            if let backupURL {
                try? FileManager.default.removeItem(at: backupURL)
            }

            let installedVersion = bundleVersion(destination)
            logger.write("Installed version: \(installedVersion)")
            guard installedVersion == expectedVersion else {
                throw HelperError.message("Installed version mismatch: expected \(expectedVersion), got \(installedVersion)")
            }

            _ = try? ProcessRunner.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destination.path])
            if skipRelaunch {
                logger.write("Skipping relaunch by request")
            } else {
                logger.write("Opening updated app")
                try ProcessRunner.run("/usr/bin/open", ["-n", destination.path])
                try waitForTokenStepLaunch(logger: &logger)
            }
            logger.write("TokenStep helper installer finished at \(Date())")
            cleanup()
        } catch {
            logger.write("TokenStep helper installer failed: \(error.localizedDescription)")
            if let backupURL,
               FileManager.default.fileExists(atPath: backupURL.path),
               !FileManager.default.fileExists(atPath: destinationPath) {
                try? FileManager.default.moveItem(at: backupURL, to: URL(fileURLWithPath: destinationPath, isDirectory: true))
            }
            notifyFailure()
            cleanup()
            throw error
        }
    }

    private func attachDMG(logger: inout HelperLogger) throws -> (mountPoint: URL, mountRoot: URL) {
        let mountRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenstep-update-root.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mountRoot, withIntermediateDirectories: true)
        logger.write("Mounting DMG under \(mountRoot.path)")
        let output = try ProcessRunner.run(
            "/usr/bin/hdiutil",
            ["attach", "-nobrowse", "-readonly", "-plist", "-mountroot", mountRoot.path, dmgPath]
        )
        guard let plist = try PropertyListSerialization.propertyList(from: output, options: [], format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPath = entities.compactMap({ $0["mount-point"] as? String }).first
        else {
            throw HelperError.message("Mounted volume path not found.")
        }
        logger.write("Mounted at \(mountPath)")
        return (URL(fileURLWithPath: mountPath, isDirectory: true), mountRoot)
    }

    private func findTokenStepApp(in directory: URL) throws -> URL {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw HelperError.message("Could not enumerate DMG.")
        }

        for case let url as URL in enumerator where url.lastPathComponent == "TokenStep.app" {
            return url
        }
        throw HelperError.message("TokenStep.app not found in DMG.")
    }

    private func stopOldTokenStep(logger: inout HelperLogger) {
        logger.write("Stopping old TokenStep process")
        if currentPID > 0 {
            kill(currentPID, SIGTERM)
        }
        _ = try? ProcessRunner.run("/usr/bin/pkill", ["-TERM", "-x", "TokenStepSwift"])
        for _ in 0..<60 {
            if (try? ProcessRunner.run("/usr/bin/pgrep", ["-x", "TokenStepSwift"])) == nil {
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        logger.write("Force stopping old TokenStep process")
        _ = try? ProcessRunner.run("/usr/bin/pkill", ["-9", "-x", "TokenStepSwift"])
        Thread.sleep(forTimeInterval: 0.4)
    }

    private func waitForTokenStepLaunch(logger: inout HelperLogger) throws {
        for _ in 0..<50 {
            if (try? ProcessRunner.run("/usr/bin/pgrep", ["-x", "TokenStepSwift"])) != nil {
                logger.write("Updated app relaunched")
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw HelperError.message("Updated app did not relaunch.")
    }

    private func bundleVersion(_ appURL: URL) -> String {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        let output = try? ProcessRunner.run("/usr/libexec/PlistBuddy", ["-c", "Print CFBundleShortVersionString", plist.path])
        return output.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func detachStaleTokenStepMounts(logger: inout HelperLogger) {
        guard let output = try? ProcessRunner.run("/sbin/mount", []),
              let text = String(data: output, encoding: .utf8)
        else { return }

        for line in text.split(separator: "\n").map(String.init) {
            guard line.contains(" on /Volumes/TokenStep")
                    || line.contains("tokenstep-preflight-")
                    || line.contains("tokenstep-update.")
                    || line.contains("tokenstep-update-root.")
            else { continue }

            guard let range = line.range(of: " on ") else { continue }
            let afterOn = line[range.upperBound...]
            guard let endRange = afterOn.range(of: " (") else { continue }
            let mountPoint = String(afterOn[..<endRange.lowerBound])
            logger.write("Detaching stale mount: \(mountPoint)")
            _ = try? ProcessRunner.run("/usr/bin/hdiutil", ["detach", mountPoint, "-force", "-quiet"])
        }
    }

    private func notifyFailure() {
        let script = "display notification \"请手动把 DMG 里的 TokenStep 拖到 Applications。\" with title \"TokenStep 自动更新失败\""
        _ = try? ProcessRunner.run("/usr/bin/osascript", ["-e", script])
    }
}

private enum ProcessRunner {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw HelperError.message(message?.isEmpty == false ? message! : "\(executable) failed with status \(process.terminationStatus)")
        }
        return outputData
    }
}

private struct HelperLogger {
    private let handle: FileHandle

    init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    func write(_ message: String) {
        handle.write(Data("[\(Date())] \(message)\n".utf8))
    }
}

private enum HelperError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message): return message
        }
    }
}
