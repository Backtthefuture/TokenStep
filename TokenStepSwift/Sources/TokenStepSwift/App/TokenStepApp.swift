import AppKit
import SwiftUI

final class TokenStepAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
            StatusBarLabelView(
                tokens: appState.today.totalTokens,
                lap: appState.todayLap,
                refreshing: appState.isRefreshing
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        .commands {
            CommandMenu("TokenStep") {
                Button("刷新") {
                    appState.refresh()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("打开 TokenStep") {
                    MainWindowPresenter.shared.show(appState: appState)
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("设置") {
                    SettingsWindowPresenter.shared.show(appState: appState)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
