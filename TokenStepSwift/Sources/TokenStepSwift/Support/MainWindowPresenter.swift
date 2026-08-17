import AppKit
import SwiftUI

final class MainWindowNavigation: ObservableObject {
    @Published private(set) var section: AppSection

    init(section: AppSection = .today) {
        self.section = section
    }

    func select(_ section: AppSection) {
        self.section = section
    }
}

@MainActor
final class MainWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = MainWindowPresenter()

    private var window: NSWindow?
    private weak var appState: AppState?
    private let navigation = MainWindowNavigation()

    func show(appState: AppState, section: AppSection? = nil) {
        self.appState = appState
        if let section {
            navigation.select(section)
        }
        let window = self.window ?? makeWindow(appState: appState)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        closeTransientPanels(except: window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        appState.setForegroundRefreshSurface("main-window", visible: true)
    }

    private func makeWindow(appState: AppState) -> NSWindow {
        let rootView = MainWindowView(navigation: navigation)
            .environmentObject(appState)
            .frame(minWidth: 1000, minHeight: 700)

        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: controller)
        window.title = "TokenStep"
        window.identifier = NSUserInterfaceItemIdentifier("main")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 1000, height: 700)
        window.maxSize = NSSize(width: 1440, height: 980)
        window.setContentSize(NSSize(width: 1000, height: 740))
        window.center()
        window.setFrameAutosaveName("TokenStepMainWindow.v3")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        appState?.setForegroundRefreshSurface("main-window", visible: false)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        appState?.setForegroundRefreshSurface("main-window", visible: false)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        appState?.setForegroundRefreshSurface("main-window", visible: true)
    }

    private func closeTransientPanels(except mainWindow: NSWindow) {
        for window in NSApp.windows where window !== mainWindow && window.title.isEmpty {
            window.close()
        }
    }
}
