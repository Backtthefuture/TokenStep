import AppKit
import SwiftUI

@MainActor
final class UpdateWindowPresenter {
    static let shared = UpdateWindowPresenter()

    private var window: NSWindow?

    func show(appState: AppState, update: AvailableUpdate) {
        window?.close()
        let window = makeWindow(appState: appState, update: update)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        closeTransientPanels(except: window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func close() {
        window?.close()
        window = nil
    }

    private func makeWindow(appState: AppState, update: AvailableUpdate) -> NSWindow {
        let rootView = UpdateWindowView(update: update)
            .environmentObject(appState)

        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: controller)
        window.title = L("TokenStep 更新")
        window.identifier = NSUserInterfaceItemIdentifier("update")
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.setContentSize(NSSize(width: 560, height: 500))
        window.minSize = NSSize(width: 520, height: 460)
        window.center()
        return window
    }

    private func closeTransientPanels(except updateWindow: NSWindow) {
        for candidate in NSApp.windows where candidate !== updateWindow && candidate.title.isEmpty {
            candidate.close()
        }
    }
}
