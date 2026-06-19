import AppKit
import SwiftUI

@MainActor
final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()

    private var window: NSWindow?

    func show(appState: AppState) {
        let window = self.window ?? makeWindow(appState: appState)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        closeTransientPanels(except: window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func close() {
        window?.close()
    }

    private func makeWindow(appState: AppState) -> NSWindow {
        let rootView = SettingsView()
            .environmentObject(appState)

        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: controller)
        window.title = "设置"
        window.identifier = NSUserInterfaceItemIdentifier("settings")
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 920, height: 700)
        window.setContentSize(NSSize(width: 920, height: 700))
        window.center()
        window.setFrameAutosaveName("TokenStepSettingsWindow")
        return window
    }

    private func closeTransientPanels(except settingsWindow: NSWindow) {
        for window in NSApp.windows where window !== settingsWindow && window.title.isEmpty {
            window.close()
        }
    }
}
