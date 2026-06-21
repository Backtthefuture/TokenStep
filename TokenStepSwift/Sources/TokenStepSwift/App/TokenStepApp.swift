import AppKit
import SwiftUI

final class TokenStepAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard SingleInstanceGuard.claimOrTerminateDuplicate() else { return }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let url = Bundle.main.url(forResource: "TokenStepIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }
}

@main
struct TokenStepApp: App {
    @NSApplicationDelegateAdaptor(TokenStepAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverPanelView()
                .environmentObject(appState)
        } label: {
            Group {
                if appState.shouldShowTokenIsland {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityHidden(true)
                } else {
                    StatusBarLabelView(
                        tokens: appState.today.totalTokens,
                        lap: appState.todayLap,
                        refreshing: appState.isRefreshing,
                        theme: appState.settings.theme,
                        language: appState.settings.language
                    )
                }
            }
            .id(appState.appearanceID)
            .onAppear {
                TokenIslandWindowPresenter.shared.bind(appState: appState)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        .commands {
            CommandMenu("TokenStep") {
                Button(L("刷新")) {
                    appState.refresh()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button(L("打开 TokenStep")) {
                    MainWindowPresenter.shared.show(appState: appState)
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button(L("设置")) {
                    SettingsWindowPresenter.shared.show(appState: appState)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
