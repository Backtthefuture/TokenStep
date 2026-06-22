import AppKit
import Darwin
import Foundation

enum SingleInstanceGuard {
    private static var lockFileDescriptor: Int32 = -1

    static func claimOrTerminateDuplicate() -> Bool {
        guard terminateOlderInstancesIfNeeded() else { return false }
        return acquireLockWithRetry()
    }

    private static func terminateOlderInstancesIfNeeded() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let currentPID = NSRunningApplication.current.processIdentifier
        let currentVersion = AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        let currentInstalled = isInstalledApp(Bundle.main.bundleURL)

        let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }

        guard !candidates.isEmpty else { return true }

        for app in candidates {
            let existingVersion = AppVersion(bundleVersion(for: app))
            let existingInstalled = app.bundleURL.map(isInstalledApp) ?? false

            if shouldKeepExisting(
                existingVersion: existingVersion,
                existingInstalled: existingInstalled,
                currentVersion: currentVersion,
                currentInstalled: currentInstalled
            ) {
                LifecycleLogger.log(
                    "Duplicate launch exiting; keeping existing pid=\(app.processIdentifier), existingVersion=\(existingVersion.description), currentVersion=\(currentVersion.description)."
                )
                TokenStepReopenRequest.post(reason: "duplicate_launch")
                activateExistingInstance(app)
                NSApp.terminate(nil)
                return false
            }

            LifecycleLogger.log(
                "Terminating older instance pid=\(app.processIdentifier), existingVersion=\(existingVersion.description), currentVersion=\(currentVersion.description)."
            )
            app.terminate()
        }

        return true
    }

    private static func shouldKeepExisting(
        existingVersion: AppVersion,
        existingInstalled: Bool,
        currentVersion: AppVersion,
        currentInstalled: Bool
    ) -> Bool {
        if existingVersion > currentVersion { return true }
        if existingVersion < currentVersion { return false }
        if existingInstalled && !currentInstalled { return true }
        if currentInstalled && !existingInstalled { return false }
        return true
    }

    private static func acquireLockWithRetry() -> Bool {
        for _ in 0..<25 {
            if acquireLock() { return true }
            usleep(80_000)
        }
        LifecycleLogger.log("Duplicate launch exiting; single-instance lock stayed busy.")
        TokenStepReopenRequest.post(reason: "lock_busy")
        NSApp.terminate(nil)
        return false
    }

    private static func acquireLock() -> Bool {
        if lockFileDescriptor >= 0 { return true }

        let runtimeDirectory = AppPaths.appSupportRoot.appendingPathComponent("runtime", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        } catch {
            return true
        }

        let lockURL = runtimeDirectory.appendingPathComponent("TokenStep.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return true }

        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            lockFileDescriptor = descriptor
            let pid = "\(getpid())\n"
            ftruncate(descriptor, 0)
            _ = pid.withCString { write(descriptor, $0, strlen($0)) }
            return true
        }

        close(descriptor)
        return false
    }

    private static func isInstalledApp(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix("/Applications/")
    }

    private static func bundleVersion(for app: NSRunningApplication) -> String? {
        guard let infoURL = app.bundleURL?.appendingPathComponent("Contents/Info.plist"),
              let info = NSDictionary(contentsOf: infoURL) as? [String: Any] else {
            return nil
        }
        return info["CFBundleShortVersionString"] as? String
    }

    private static func activateExistingInstance(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }
}

private struct AppVersion: Comparable {
    private let parts: [Int]

    init(_ value: String?) {
        parts = (value ?? "0")
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for index in 0..<count {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

extension AppVersion: CustomStringConvertible {
    var description: String {
        parts.map(String.init).joined(separator: ".")
    }
}
