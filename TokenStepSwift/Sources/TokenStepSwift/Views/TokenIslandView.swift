import AppKit
import SwiftUI

enum TokenIslandMetrics {
    static let expandedCardSize = NSSize(width: 356, height: 238)
    static let expandedCornerRadius: CGFloat = 28
    static let expandedShadowMargin: CGFloat = 26

    static var expandedWindowSize: NSSize {
        NSSize(
            width: expandedCardSize.width + expandedShadowMargin * 2,
            height: expandedCardSize.height + expandedShadowMargin * 2
        )
    }
}

struct TokenIslandWindowView: View {
    @EnvironmentObject private var appState: AppState

    var onHoverChanged: (Bool) -> Void
    var onTap: () -> Void

    var body: some View {
        TokenIslandRingView(
            tokens: appState.today.totalTokens,
            lap: appState.todayLap,
            refreshing: appState.isRefreshing,
            theme: appState.settings.theme,
            language: appState.settings.language
        )
        .onHover { hovering in
            onHoverChanged(hovering)
        }
        .onTapGesture {
            onTap()
        }
        .id(appState.appearanceID)
    }
}

struct TokenIslandPopoverWindowView: View {
    @EnvironmentObject private var appState: AppState

    var onHoverChanged: (Bool) -> Void

    var body: some View {
        TokenIslandExpandedSurface {
            TokenIslandExpandedView()
                .environmentObject(appState)
        }
            .padding(TokenIslandMetrics.expandedShadowMargin)
            .frame(
                width: TokenIslandMetrics.expandedWindowSize.width,
                height: TokenIslandMetrics.expandedWindowSize.height
            )
            .onHover { hovering in
                onHoverChanged(hovering)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topLeading)))
            .id(appState.appearanceID)
            .animation(.spring(response: 0.26, dampingFraction: 0.88), value: appState.appearanceID)
    }
}

struct TokenIslandRingView: View {
    var tokens: Int
    var lap: TokenStepLapProgress
    var refreshing: Bool
    var theme: TokenStepTheme
    var language: TokenStepLanguage

    var body: some View {
        HStack(spacing: 5) {
            Image(nsImage: StatusBarIconRenderer.progressRing(
                progress: lap.currentLapProgress,
                lap: lap.currentLap,
                refreshing: refreshing,
                size: 16,
                radius: 6.2,
                lineWidth: 2.15,
                showsCenterDot: false
            ))
                .resizable()
                .interpolation(.high)
                .frame(width: 15, height: 15)
                .accessibilityLabel("\(lap.lapTitle) \(lap.lapPercentText)")
                .id("\(theme.id)-\(language.resolved.id)")

            Text(TokenStepFormat.tokens(tokens, compact: true, language: language))
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .padding(.leading, 7)
        .padding(.trailing, 8)
        .frame(width: TokenIslandWindowPresenter.collapsedSize.width, height: TokenIslandWindowPresenter.collapsedSize.height)
        .background(Color.black)
        .clipShape(Capsule())
        .id("\(theme.id)-\(language.resolved.id)")
    }
}

private struct TokenIslandExpandedView: View {
    @EnvironmentObject private var appState: AppState

    private var lap: TokenStepLapProgress { appState.todayLap }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header

            HStack(alignment: .center, spacing: 16) {
                ring
                VStack(alignment: .leading, spacing: 7) {
                    Text(lap.lapStatusText)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(lap.color)
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(TokenStepFormat.tokens(appState.today.totalTokens))
                        .font(.system(size: 27, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.tokenInk)
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(lap.perLapGoalText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.tokenInk.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            TokenIslandToolSplitView(tools: appState.today.tools, total: appState.today.totalTokens)

            if appState.settings.showCodexQuota, appState.hasAnyQuota {
                TokenIslandQuotaMiniView(codexQuota: appState.codexQuota, claudeQuota: appState.claudeQuota)
            }

            HStack(spacing: 8) {
                TokenIslandActionButton(title: L("打开仪表盘"), symbol: "arrow.up.right") {
                    MainWindowPresenter.shared.show(appState: appState)
                }
                TokenIslandActionButton(title: L("刷新"), symbol: "arrow.clockwise") {
                    appState.refresh()
                }
                .disabled(appState.isRefreshing)
                TokenIslandActionButton(title: L("设置"), symbol: "gearshape") {
                    SettingsWindowPresenter.shared.show(appState: appState)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var header: some View {
        HStack(spacing: 8) {
            TokenStepMark(size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("TokenStep")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.tokenInk.opacity(0.92))
                Text(L("每日 Token 消耗追踪"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.tokenInk.opacity(0.48))
            }
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(appState.isRefreshing ? Color.secondary.opacity(0.66) : Color.tokenGreen)
                    .frame(width: 6, height: 6)
                Text(appState.isRefreshing ? L("同步中") : L("已同步"))
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color.tokenInk.opacity(0.70))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.tokenSurface, in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.055)))
        }
    }

    private var ring: some View {
        ZStack {
            ProgressRingView(progress: lap.currentLapProgress, lineWidth: 9, color: lap.color)
            VStack(spacing: 2) {
                Text(TokenStepFormat.tokens(appState.today.totalTokens, compact: true))
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.tokenInk)
                    .minimumScaleFactor(0.62)
                    .lineLimit(1)
                Text(lap.lapTitle)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.tokenInk.opacity(0.48))
            }
            .frame(width: 66)
        }
        .frame(width: 86, height: 86)
    }
}

private struct TokenIslandExpandedSurface<Content: View>: View {
    var content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: TokenIslandMetrics.expandedCornerRadius, style: .continuous)
    }

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(
                width: TokenIslandMetrics.expandedCardSize.width,
                height: TokenIslandMetrics.expandedCardSize.height
            )
            .background(TokenIslandExpandedBackground().clipShape(shape))
            .clipShape(shape)
            .overlay(shape.stroke(Color.black.opacity(0.065)))
            .contentShape(shape)
            .shadow(color: Color.black.opacity(0.18), radius: 22, x: 0, y: 12)
    }
}

private struct TokenIslandExpandedBackground: View {
    var body: some View {
        ZStack {
            Color.tokenSurface
            LinearGradient(
                colors: [
                    Color.tokenGreen.opacity(0.11),
                    Color.tokenCanvas.opacity(0.35),
                    Color.tokenGreenDark.opacity(0.045)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct TokenIslandToolSplitView: View {
    var tools: [String: Int]
    var total: Int

    var body: some View {
        VStack(spacing: 7) {
            TokenIslandSplitRow(name: "Codex", tokens: tools["Codex"] ?? 0, total: total)
            TokenIslandSplitRow(name: "Claude Code", tokens: tools["Claude Code"] ?? 0, total: total)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.tokenTrack.opacity(0.42), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct TokenIslandSplitRow: View {
    var name: String
    var tokens: Int
    var total: Int

    private var percent: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(tokens) / Double(total), 0), 1)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Color.tokenInk.opacity(0.70))
                .frame(width: 70, alignment: .leading)
                .lineLimit(1)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.08))
                    Capsule()
                        .fill(Color.tokenGreen)
                        .frame(width: max(tokens > 0 ? 4 : 0, proxy.size.width * percent))
                }
            }
            .frame(height: 5)

            Text(TokenStepFormat.tokens(tokens, compact: true))
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Color.tokenInk.opacity(0.78))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
    }
}

private struct TokenIslandQuotaMiniView: View {
    var codexQuota: CodexQuotaSnapshot
    var claudeQuota: CodexQuotaSnapshot

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.tokenGreen)
            if codexQuota.isAvailable {
                quotaBlock(title: "Codex", quota: codexQuota)
            }
            if codexQuota.isAvailable, claudeQuota.isAvailable {
                Divider().frame(height: 15).overlay(Color.black.opacity(0.10))
            }
            if claudeQuota.isAvailable {
                quotaBlock(title: "Claude", quota: claudeQuota)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.tokenTrack.opacity(0.38), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func quotaBlock(title: String, quota: CodexQuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.tokenInk.opacity(0.48))
                .lineLimit(1)
            HStack(spacing: 6) {
                quotaText(quota.fiveHour, fallback: L("5 小时"))
                quotaText(quota.sevenDay, fallback: L("7 天"))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }

    private func quotaText(_ window: CodexQuotaWindow?, fallback: String) -> some View {
        HStack(spacing: 3) {
            Text((window?.title ?? fallback).replacingOccurrences(of: " ", with: ""))
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.tokenInk.opacity(0.50))
            Text(window.map { TokenStepFormat.percent($0.remainingPercent) } ?? "—")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.tokenGreen)
                .monospacedDigit()
        }
    }
}

private struct TokenIslandActionButton: View {
    var title: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.heavy))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(Color.tokenInk.opacity(0.82))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(Color.tokenSurface, in: Capsule())
                .overlay(Capsule().stroke(Color.black.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}
