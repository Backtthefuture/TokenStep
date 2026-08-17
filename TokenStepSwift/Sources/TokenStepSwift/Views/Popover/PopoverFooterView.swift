import AppKit
import SwiftUI

struct PopoverFooterView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(L("本地统计"), systemImage: "checkmark.shield.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(appState.settings.refreshIntervalSeconds == 0 ? L("手动刷新") : LFormat("刷新 %@", TokenStepFormat.intervalLabel(appState.settings.refreshIntervalSeconds)))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    MainWindowPresenter.shared.show(appState: appState)
                } label: {
                    Label(L("打开仪表盘"), systemImage: "arrow.up.right")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 148, height: 40)
                        .background(Color.tokenGreen, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(L("打开仪表盘"))

                Spacer(minLength: 0)

                PopoverActionButton(title: L("刷新"), symbol: "arrow.clockwise") {
                    appState.refresh()
                }
                .disabled(appState.isRefreshing)

                PopoverActionButton(title: L("设置"), symbol: "gearshape") {
                    SettingsWindowPresenter.shared.show(appState: appState)
                }

                PopoverActionButton(title: L("退出"), symbol: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
}

private struct PopoverActionButton: View {
    var title: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color.tokenInk.opacity(0.78))
                .frame(width: 40, height: 40)
                .background(Color.tokenSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.black.opacity(0.055)))
                .help(title)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}
