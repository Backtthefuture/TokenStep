import AppKit
import SwiftUI

enum TokenIslandMetrics {
    /// The expanded card shows the same content as the menu bar popover, so it
    /// shares its width; the height follows the content.
    static let expandedCardWidth = CompactPopoverStyle.width
    static let expandedCornerRadius: CGFloat = 16
    static let expandedShadowMargin: CGFloat = 26
    /// Used before the card reports its measured height.
    static let initialCardHeight: CGFloat = 420

    /// The window has no margin above the card: the card hangs just below the
    /// island, and a top margin would cover the island's lower edge. The
    /// shadow's alpha there then takes the hover, the island reads it as the
    /// mouse leaving, the card closes, the island gets the hover back, and the
    /// card flickers open and shut.
    static func expandedWindowSize(cardHeight: CGFloat) -> NSSize {
        NSSize(
            width: expandedCardWidth + expandedShadowMargin * 2,
            height: cardHeight + expandedShadowMargin
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
        .environment(\.colorScheme, appState.settings.theme.colorScheme)
        .id(appState.appearanceID)
    }
}

/// The card that opens from the island. It hosts the menu bar popover so both
/// entry points show the same compact column.
struct TokenIslandPopoverWindowView: View {
    @EnvironmentObject private var appState: AppState

    var onHoverChanged: (Bool) -> Void
    var onHeightChanged: (CGFloat) -> Void = { _ in }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: TokenIslandMetrics.expandedCornerRadius, style: .continuous)
    }

    var body: some View {
        PopoverPanelView()
            .environmentObject(appState)
            .fixedSize(horizontal: false, vertical: true)
            .clipShape(shape)
            .overlay(shape.stroke(Color.tokenHairlineStrong))
            .contentShape(shape)
            .shadow(color: Color.tokenShadow, radius: 22, x: 0, y: 12)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { onHeightChanged(proxy.size.height) }
                        .onChange(of: proxy.size.height) { _, height in
                            onHeightChanged(height)
                        }
                }
            }
            .onHover { hovering in
                onHoverChanged(hovering)
            }
            .padding([.horizontal, .bottom], TokenIslandMetrics.expandedShadowMargin)
            .frame(maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, appState.settings.theme.colorScheme)
            .id(appState.appearanceID)
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
                .foregroundStyle(TokenStepThemeRuntime.isCinematic ? Color.tokenInk : Color.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .padding(.leading, 7)
        .padding(.trailing, 8)
        .frame(width: TokenIslandWindowPresenter.collapsedSize.width, height: TokenIslandWindowPresenter.collapsedSize.height)
        .background {
            ZStack {
                Color.black
                if TokenStepThemeRuntime.isCinematic {
                    LinearGradient(
                        colors: [Color.tokenCanvas, Color.tokenGreen.opacity(0.16), Color.tokenCanvas],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                if TokenStepThemeRuntime.isInterstellar {
                    InterstellarEventHorizonEmblem()
                        .padding(.horizontal, 5)
                        .opacity(0.42)
                }
            }
        }
        .clipShape(Capsule())
        .overlay(Capsule().stroke(TokenStepThemeRuntime.isCinematic ? Color.tokenHairlineStrong : Color.clear))
        .shadow(color: TokenStepThemeRuntime.isCinematic ? Color.tokenGreen.opacity(0.16) : .clear, radius: 8)
        .id("\(theme.id)-\(language.resolved.id)")
    }
}
