import AppKit
import Darwin
import Foundation

struct AvailableUpdate: Identifiable, Equatable {
    var id: String { version }
    var version: String
    var tagName: String
    var title: String
    var notes: String
    var pageURL: URL
    var assetURL: URL
    var assetName: String
    var assetSize: Int

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(assetSize), countStyle: .file)
    }

    var noteLines: [String] {
        let cleaned = notes
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                guard !trimmed.hasPrefix("#") else { return nil }
                guard !trimmed.lowercased().hasPrefix("sha256") else { return nil }
                let cleaned = trimmed
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-•* ").union(.whitespacesAndNewlines))
                    .replacingOccurrences(of: "`", with: "")
                    .replacingOccurrences(of: "**", with: "")
                return cleaned.isEmpty ? nil : cleaned
            }
        return Array(cleaned.prefix(upTo: min(4, cleaned.count))).map { String($0) }
    }
}

enum UpdateCheckResult: Equatable {
    case upToDate
    case available(AvailableUpdate)
}

enum UpdateCheckPhase: Equatable {
    case idle
    case checking
    case upToDate(checkedAt: Date)
    case available(AvailableUpdate, checkedAt: Date)
    case failed(checkedAt: Date, message: String)
}

enum UpdateCheckTrigger: String, Equatable {
    case startup
    case timer
    case foreground
    case settingsEnabled
    case manual

    var isManual: Bool { self == .manual }
}

enum UpdateCheckPolicy {
    static let automaticInterval: TimeInterval = 6 * 60 * 60
    static let timerTolerance: TimeInterval = 15 * 60

    static func shouldStart(
        trigger: UpdateCheckTrigger,
        autoUpdateEnabled: Bool,
        lastAttemptAt: Date?,
        now: Date,
        startupCheckPending: Bool = false,
        minimumInterval: TimeInterval = automaticInterval
    ) -> Bool {
        if trigger.isManual {
            return true
        }
        guard autoUpdateEnabled else { return false }
        if startupCheckPending, trigger == .foreground || trigger == .timer {
            return false
        }
        guard trigger != .settingsEnabled else { return true }
        guard let lastAttemptAt else { return true }
        return now.timeIntervalSince(lastAttemptAt) >= minimumInterval
    }

    static func visibleUpdate(
        from result: UpdateCheckResult,
        skippedVersion: String?,
        trigger: UpdateCheckTrigger
    ) -> AvailableUpdate? {
        guard case let .available(update) = result else { return nil }
        if !trigger.isManual, skippedVersion == update.version {
            return nil
        }
        return update
    }
}

enum UpdatePresentationPolicy {
    static func shouldPresentWindow(
        trigger: UpdateCheckTrigger,
        update: AvailableUpdate?
    ) -> Bool {
        trigger.isManual && update != nil
    }
}

struct UpdateCheckGate {
    private(set) var isChecking = false
    private(set) var lastAttemptAt: Date?

    mutating func begin(
        trigger: UpdateCheckTrigger,
        autoUpdateEnabled: Bool,
        now: Date,
        startupCheckPending: Bool = false
    ) -> Bool {
        guard !isChecking else { return false }
        guard UpdateCheckPolicy.shouldStart(
            trigger: trigger,
            autoUpdateEnabled: autoUpdateEnabled,
            lastAttemptAt: lastAttemptAt,
            now: now,
            startupCheckPending: startupCheckPending
        ) else {
            return false
        }
        isChecking = true
        lastAttemptAt = now
        return true
    }

    mutating func finish() {
        isChecking = false
    }
}

enum UpdateService {
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/Backtthefuture/TokenStep/releases/latest")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static func checkForUpdates(
        currentVersion: String = Self.currentVersion,
        session: URLSession = .shared,
        releaseURL: URL? = nil
    ) async throws -> UpdateCheckResult {
        var request = URLRequest(url: releaseURL ?? latestReleaseURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TokenStep/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.checkFailed
        }

        return try evaluateReleaseResponse(
            data: data,
            statusCode: http.statusCode,
            currentVersion: currentVersion
        )
    }

    static func evaluateReleaseResponse(
        data: Data,
        statusCode: Int,
        currentVersion: String
    ) throws -> UpdateCheckResult {
        guard (200..<300).contains(statusCode) else {
            throw UpdateError.checkFailed
        }

        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw UpdateError.checkFailed
        }
        guard !release.draft, !release.prerelease else { return .upToDate }
        let version = release.tagName.strippingVersionPrefix
        guard let releaseVersion = Version(version),
              let installedVersion = Version(currentVersion)
        else {
            throw UpdateError.checkFailed
        }
        guard releaseVersion > installedVersion else { return .upToDate }
        guard let asset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }),
              let pageURL = URL(string: release.htmlURL),
              let assetURL = URL(string: asset.downloadURL)
        else {
            throw UpdateError.missingDMG
        }

        return .available(
            AvailableUpdate(
                version: version,
                tagName: release.tagName,
                title: release.name ?? "TokenStep \(version)",
                notes: release.body ?? "",
                pageURL: pageURL,
                assetURL: assetURL,
                assetName: asset.name,
                assetSize: asset.size
            )
        )
    }

    static func downloadAndInstall(
        _ update: AvailableUpdate,
        requireVerified: Bool,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> URL {
        let downloader = UpdateDownloader(progress: progress)
        let temporaryURL = try await downloader.download(from: update.assetURL)
        try FileManager.default.createDirectory(at: AppPaths.updates, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: AppPaths.logs, withIntermediateDirectories: true)

        let destination = AppPaths.updates.appendingPathComponent(update.assetName)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        try preflightDMG(destination, requireVerified: requireVerified)
        try launchInstaller(for: destination, version: update.version, requireVerified: requireVerified)
        return destination
    }

    private static func preflightDMG(_ dmgURL: URL, requireVerified: Bool) throws {
        detachStaleTokenStepMounts()
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenstep-preflight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        defer {
            _ = try? runProcess("/usr/bin/hdiutil", arguments: ["detach", mountPoint.path, "-force", "-quiet"])
            try? FileManager.default.removeItem(at: mountPoint)
        }

        try runProcess("/usr/bin/hdiutil", arguments: ["attach", "-nobrowse", "-quiet", "-mountpoint", mountPoint.path, dmgURL.path])
        let appURL = try findTokenStepApp(in: mountPoint)
        guard !requireVerified || isVerifiedApp(appURL) else {
            throw UpdateError.verificationFailed
        }
    }

    private static func findTokenStepApp(in directory: URL) throws -> URL {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw UpdateError.installFailed
        }

        for case let url as URL in enumerator where url.lastPathComponent == "TokenStep.app" {
            return url
        }
        throw UpdateError.installFailed
    }

    private static func isVerifiedApp(_ appURL: URL) -> Bool {
        (try? runProcess("/usr/sbin/spctl", arguments: ["--assess", "--type", "execute", appURL.path])) != nil
            && (try? runProcess("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", appURL.path])) != nil
    }

    private static func launchInstaller(for dmgURL: URL, version: String, requireVerified: Bool) throws {
        let helperURL = try prepareTemporaryHelper()
        let logURL = AppPaths.logs.appendingPathComponent("update-install-\(Int(Date().timeIntervalSince1970)).log")
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let launchLog = """
        TokenStep update launcher prepared at \(Date())
        Expected version: \(version)
        DMG: \(dmgURL.path)
        Helper: \(helperURL.path)

        """
        try launchLog.write(to: logURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = helperURL
        process.arguments = [
            "install",
            "--dmg", dmgURL.path,
            "--version", version,
            "--current-pid", "\(currentPID)",
            "--require-verified", requireVerified ? "1" : "0",
            "--log", logURL.path,
            "--helper-path", helperURL.path
        ]
        process.standardOutput = nil
        process.standardError = nil
        do {
            try process.run()
            exitCurrentAppAfterLaunchingInstaller()
        } catch {
            throw UpdateError.installFailed
        }
    }

    private static func prepareTemporaryHelper() throws -> URL {
        guard let helperURL = DataService.bundledHelperURL() else {
            throw UpdateError.installFailed
        }

        try FileManager.default.createDirectory(at: AppPaths.updates, withIntermediateDirectories: true)
        let destination = AppPaths.updates
            .appendingPathComponent("TokenStepHelper-\(UUID().uuidString)")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: helperURL, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination
    }

    private static func exitCurrentAppAfterLaunchingInstaller() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NSApp.terminate(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            Darwin.exit(0)
        }
    }

    private static func installerScript(
        dmgPath: String,
        version: String,
        currentPID: Int32,
        logPath: String,
        requireVerified: Bool,
        scriptPath: String
    ) -> String {
        let failureTitle = L("TokenStep 自动更新失败")
        let failureBody = L("请手动把 DMG 里的 TokenStep 拖到 Applications。")
        return """
        #!/bin/bash
        set -euo pipefail

        DMG=\(shellQuote(dmgPath))
        DEST="/Applications/TokenStep.app"
        APP_NAME="TokenStep.app"
        EXECUTABLE_NAME="TokenStepSwift"
        EXPECTED_VERSION=\(shellQuote(version))
        CURRENT_PID="\(currentPID)"
        LOG=\(shellQuote(logPath))
        REQUIRE_VERIFIED="\(requireVerified ? "1" : "0")"
        SCRIPT_PATH=\(shellQuote(scriptPath))
        FAILURE_TITLE=\(shellQuote(failureTitle))
        FAILURE_BODY=\(shellQuote(failureBody))
        MOUNT_POINT=""
        MOUNT_ROOT=""
        BACKUP=""

        mkdir -p "$(dirname "$LOG")"
        exec >>"$LOG" 2>&1
        echo "TokenStep update installer started at $(date)"
        echo "Expected version: $EXPECTED_VERSION"
        echo "DMG: $DMG"
        echo "Destination: $DEST"

        cleanup() {
          if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
            /usr/bin/hdiutil detach "$MOUNT_POINT" -force -quiet || true
          fi
          if [ -n "$MOUNT_ROOT" ] && [ -d "$MOUNT_ROOT" ]; then
            /bin/rm -rf "$MOUNT_ROOT" 2>/dev/null || true
          fi
          /bin/rm -f "$SCRIPT_PATH" 2>/dev/null || true
        }
        finish() {
          STATUS=$?
          if [ "$STATUS" -ne 0 ]; then
            echo "TokenStep update installer failed with status $STATUS"
            if [ -n "$BACKUP" ] && [ -d "$BACKUP" ] && [ ! -d "$DEST" ]; then
              /bin/mv "$BACKUP" "$DEST" || true
            fi
            /usr/bin/osascript -e "display notification \\"$FAILURE_BODY\\" with title \\"$FAILURE_TITLE\\"" || true
          fi
          cleanup
          exit "$STATUS"
        }
        trap finish EXIT

        detach_tokenstep_mounts() {
          /sbin/mount | while IFS= read -r line; do
            if [[ "$line" == *" on /Volumes/TokenStep"* || "$line" == *tokenstep-preflight-* || "$line" == *tokenstep-update.* || "$line" == *tokenstep-update-root.* ]]; then
              MP="${line#* on }"
              MP="${MP%% (*}"
              echo "Detaching stale mount: $MP"
              /usr/bin/hdiutil detach "$MP" -force -quiet || true
            fi
          done
        }

        detach_tokenstep_mounts

        MOUNT_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/tokenstep-update-root.XXXXXX")"
        echo "Mounting DMG under $MOUNT_ROOT"
        ATTACH_OUTPUT="$(/usr/bin/hdiutil attach -nobrowse -readonly -mountroot "$MOUNT_ROOT" "$DMG" 2>&1)" || {
          echo "hdiutil attach failed"
          echo "$ATTACH_OUTPUT"
          exit 1
        }
        echo "$ATTACH_OUTPUT"
        MOUNT_POINT="$(printf '%s\n' "$ATTACH_OUTPUT" | /usr/bin/awk '/\\// { mount=$NF } END { print mount }')"
        if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
          echo "Mounted volume path not found"
          exit 1
        }
        echo "Mounted at $MOUNT_POINT"

        SRC="$(/usr/bin/find "$MOUNT_POINT" -name "$APP_NAME" -type d -print -quit)"
        if [ -z "$SRC" ]; then
          echo "TokenStep.app not found in DMG"
          exit 1
        fi
        echo "Found source app: $SRC"

        if [ "$REQUIRE_VERIFIED" = "1" ]; then
          echo "Verifying source app"
          /usr/sbin/spctl --assess --type execute "$SRC"
          /usr/bin/codesign --verify --deep --strict "$SRC"
        fi

        SRC_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$SRC/Contents/Info.plist" 2>/dev/null || true)"
        echo "Source version: $SRC_VERSION"
        if [ "$SRC_VERSION" != "$EXPECTED_VERSION" ]; then
          echo "Source version mismatch: expected $EXPECTED_VERSION, got $SRC_VERSION"
          exit 1
        fi

        echo "Stopping old TokenStep process"
        /bin/kill -TERM "$CURRENT_PID" 2>/dev/null || true
        /usr/bin/pkill -x "$EXECUTABLE_NAME" 2>/dev/null || true
        for _ in {1..50}; do
          if ! /usr/bin/pgrep -x "$EXECUTABLE_NAME" >/dev/null 2>&1; then
            break
          fi
          /bin/sleep 0.2
        done
        if /usr/bin/pgrep -x "$EXECUTABLE_NAME" >/dev/null 2>&1; then
          echo "Force stopping old TokenStep process"
          /usr/bin/pkill -9 -x "$EXECUTABLE_NAME" 2>/dev/null || true
          /bin/sleep 0.4
        fi

        BACKUP="/Applications/TokenStep.app.previous.$(/bin/date +%s)"
        if [ -d "$DEST" ]; then
          echo "Backing up existing app to $BACKUP"
          /bin/mv "$DEST" "$BACKUP"
        fi

        echo "Copying new app into Applications"
        if ! /usr/bin/ditto "$SRC" "$DEST"; then
          /bin/rm -rf "$DEST"
          if [ -d "$BACKUP" ]; then
            /bin/mv "$BACKUP" "$DEST"
          fi
          echo "Failed to copy TokenStep.app into /Applications"
          exit 1
        fi

        if [ -d "$BACKUP" ]; then
          /bin/rm -rf "$BACKUP"
        fi

        INSTALLED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$DEST/Contents/Info.plist" 2>/dev/null || true)"
        echo "Installed version: $INSTALLED_VERSION"
        if [ "$INSTALLED_VERSION" != "$EXPECTED_VERSION" ]; then
          echo "Installed version mismatch: expected $EXPECTED_VERSION, got $INSTALLED_VERSION"
          exit 1
        fi

        /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
        echo "Opening updated app"
        /usr/bin/open -n "$DEST"
        for _ in {1..25}; do
          if /usr/bin/pgrep -x "$EXECUTABLE_NAME" >/dev/null 2>&1; then
            echo "Updated app relaunched"
            break
          fi
          /bin/sleep 0.2
        done
        echo "TokenStep update installer finished at $(date)"
        """
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    @discardableResult
    private static func runProcess(_ executable: String, arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.installFailed
        }
        return output.fileHandleForReading.readDataToEndOfFile()
    }

    private static func detachStaleTokenStepMounts() {
        guard let output = try? runProcess("/sbin/mount", arguments: []),
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
            _ = try? runProcess("/usr/bin/hdiutil", arguments: ["detach", mountPoint, "-force", "-quiet"])
        }
    }
}

enum UpdateError: LocalizedError, Equatable {
    case checkFailed
    case missingDMG
    case downloadFailed
    case verificationFailed
    case installFailed

    var errorDescription: String? {
        switch self {
        case .checkFailed:
            return L("检查更新失败，请稍后再试。")
        case .missingDMG:
            return L("新版本没有可下载的 DMG。")
        case .downloadFailed:
            return L("下载更新失败，请稍后再试。")
        case .verificationFailed:
            return L("新版本未通过签名或公证验证，已停止安装。")
        case .installFailed:
            return L("自动安装失败，请稍后重试，或手动把 TokenStep 拖到 Applications。")
        }
    }
}

private final class UpdateDownloader: NSObject, URLSessionDownloadDelegate {
    private let progress: @MainActor (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    init(progress: @escaping @MainActor (Double) -> Void) {
        self.progress = progress
    }

    func download(from url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let value = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            progress(min(max(value, 0), 1))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("dmg")
        do {
            try FileManager.default.moveItem(at: location, to: temporaryURL)
            continuation?.resume(returning: temporaryURL)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
        session.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        continuation?.resume(throwing: error)
        continuation = nil
        session.invalidateAndCancel()
    }
}

private struct GitHubRelease: Decodable {
    var tagName: String
    var name: String?
    var body: String?
    var draft: Bool
    var prerelease: Bool
    var htmlURL: String
    var assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case draft
        case prerelease
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    var name: String
    var downloadURL: String
    var size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
        case size
    }
}

private struct Version: Comparable {
    var parts: [Int]

    init?(_ value: String) {
        let components = value.strippingVersionPrefix.split(separator: ".")
        guard !components.isEmpty else { return nil }
        var parsed: [Int] = []
        for component in components {
            let digits = component.prefix { $0.isNumber }
            guard !digits.isEmpty, let number = Int(digits) else { return nil }
            parsed.append(number)
        }
        parts = parsed
    }

    static func < (lhs: Version, rhs: Version) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for index in 0..<count {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

private extension String {
    var strippingVersionPrefix: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[vV]"#, with: "", options: .regularExpression)
    }
}
