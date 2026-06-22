import AppKit
import Foundation

enum LifecycleLogger {
    private static let maxLogBytes: UInt64 = 512_000

    static func log(_ message: String) {
        do {
            try FileManager.default.createDirectory(at: AppPaths.logs, withIntermediateDirectories: true)
            let logURL = AppPaths.logs.appendingPathComponent("lifecycle.log")
            rotateIfNeeded(logURL)
            let line = "\(timestamp()) \(message)\n"
            let data = Data(line.utf8)

            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: logURL, options: .atomic)
            }
        } catch {
            // Lifecycle logging should never affect app launch or update flow.
        }
    }

    private static func rotateIfNeeded(_ logURL: URL) {
        guard let values = try? logURL.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize,
              UInt64(size) > maxLogBytes
        else {
            return
        }
        try? FileManager.default.removeItem(at: logURL)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

enum TokenStepReopenRequest {
    static let notificationName = Notification.Name("com.huangshu.TokenStep.reopenRequested")

    static func post(reason: String) {
        DistributedNotificationCenter.default().postNotificationName(
            notificationName,
            object: Bundle.main.bundleIdentifier,
            userInfo: [
                "reason": reason,
                "pid": "\(ProcessInfo.processInfo.processIdentifier)"
            ],
            deliverImmediately: true
        )
    }
}

@MainActor
final class TokenStepReopenObserver {
    static let shared = TokenStepReopenObserver()

    private var observer: NSObjectProtocol?
    private weak var appState: AppState?

    func bind(appState: AppState) {
        self.appState = appState
        guard observer == nil else { return }

        observer = DistributedNotificationCenter.default().addObserver(
            forName: TokenStepReopenRequest.notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let appState = self?.appState else { return }
                let reason = notification.userInfo?["reason"] as? String ?? "unknown"
                LifecycleLogger.log("Received reopen request reason=\(reason); showing main window.")
                MainWindowPresenter.shared.show(appState: appState)
            }
        }
    }
}
