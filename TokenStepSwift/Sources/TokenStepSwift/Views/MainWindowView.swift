import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case today
    case history
    case stats
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "今日"
        case .history: "历史"
        case .stats: "统计"
        case .privacy: "隐私"
        }
    }

    var sidebarTitle: String {
        switch self {
        case .today: "今日步数"
        case .history: "历史活动"
        case .stats: "用量统计"
        case .privacy: "隐私"
        }
    }

    var subtitle: String {
        switch self {
        case .today: "今天和 AI 一起走了多远"
        case .history: "长期节奏和所有历史记录"
        case .stats: "按客户端和模型拆开看"
        case .privacy: "只统计数量，不读取内容"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "figure.walk.circle.fill"
        case .history: "square.grid.3x3.fill"
        case .stats: "chart.bar.xaxis"
        case .privacy: "lock.shield.fill"
        }
    }
}

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: AppSection = .today

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(width: 1)
            content
        }
        .background(TokenStepBackdrop())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.refresh()
                } label: {
                    Label(appState.isRefreshing ? "同步中" : "刷新", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isRefreshing)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                TokenStepMark(size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text("TokenStep")
                        .font(.system(size: 25, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.tokenInk)
                    Text("每天一个亿")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(Color.tokenGreen)
                }
            }
            .padding(.top, 30)
            .padding(.horizontal, 22)
            .padding(.bottom, 28)

            VStack(spacing: 8) {
                ForEach(AppSection.allCases) { section in
                    SidebarNavButton(
                        section: section,
                        selected: selection == section
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            selection = section
                        }
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 24)

            sidebarFooter
                .padding(.horizontal, 14)
                .padding(.bottom, 22)
        }
        .frame(width: 226)
        .background(
            LinearGradient(
                colors: [
                    Color.tokenSurface.opacity(0.98),
                    Color.tokenGreen.opacity(0.045),
                    Color.tokenSurface.opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidebarSettingsButton {
                SettingsWindowPresenter.shared.show(appState: appState)
            }

            SidebarPrivacyStatus()
        }
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 26) {
                    pageHeader
                    if let error = appState.lastError {
                        ErrorBanner(message: error) {
                            appState.clearError()
                        }
                    }
                    detailView
                }
                .frame(maxWidth: 1160, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 38)
            .padding(.vertical, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(selection.title)
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.tokenInk)
                Text(selection.subtitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 9) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(appState.isRefreshing ? Color.secondary.opacity(0.7) : Color.tokenGreen)
                        .frame(width: 7, height: 7)
                    Text(appState.isRefreshing ? "同步中" : "已同步")
                        .font(.callout.weight(.bold))
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(Color.tokenSurface, in: Capsule())
                .overlay(Capsule().stroke(Color.black.opacity(0.06)))

                Text("更新 \(TokenStepFormat.generatedTime(appState.snapshot.generatedAt))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .today:
            TodayView()
        case .history:
            HistoryView()
        case .stats:
            StatsView()
        case .privacy:
            PrivacyView()
        }
    }
}

private struct SidebarNavButton: View {
    var section: AppSection
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? Color.tokenGreen : Color.tokenGreen.opacity(0.10))
                    Image(systemName: section.systemImage)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(selected ? .white : Color.tokenGreenDark)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.sidebarTitle)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(selected ? Color.tokenInk : Color.tokenInk.opacity(0.72))
                    Text(section.subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.tokenSurface)
                        .shadow(color: Color.black.opacity(0.07), radius: 14, x: 0, y: 8)
                }
            }
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.06))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarSettingsButton: View {
    @State private var isHovering = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.tokenGreen.opacity(isHovering ? 0.18 : 0.12))
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.tokenGreenDark)
                }
                .frame(width: 34, height: 34)

                Text("设置")
                    .font(.callout.weight(.heavy))
                    .foregroundStyle(Color.tokenInk.opacity(0.86))

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.secondary.opacity(isHovering ? 0.82 : 0.52))
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 12)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.tokenSurface.opacity(isHovering ? 0.98 : 0.82))
                    .shadow(color: Color.black.opacity(isHovering ? 0.075 : 0.035), radius: isHovering ? 16 : 10, x: 0, y: 7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(isHovering ? 0.08 : 0.055))
            )
            .scaleEffect(isHovering ? 1.01 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.84), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("设置")
    }
}

private struct SidebarPrivacyStatus: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.tokenGreenDark)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text("本地统计")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.tokenGreenDark)
                Text("不上传代码或对话")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.tokenGreen.opacity(0.055))
        )
    }
}
