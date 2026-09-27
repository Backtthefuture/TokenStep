import SwiftUI

/// Theme packs and their options, split out of the General pane.
struct SettingsAppearancePane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsSectionCard(
            title: L("主题皮肤包"),
            subtitle: L("经典、奥德赛与引力边界可随时切换")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ForEach(TokenStepThemePack.allCases) { pack in
                        ThemePackOptionButton(
                            pack: pack,
                            selected: appState.settings.themePack == pack,
                            classicTheme: appState.settings.classicTheme,
                            odysseyChapter: appState.settings.odysseyChapter
                        ) {
                            withAnimation(.easeOut(duration: 0.18)) {
                                appState.setThemePack(pack)
                            }
                        }
                    }
                }

                Rectangle()
                    .fill(Color.tokenDivider)
                    .frame(height: 1)

                if appState.settings.themePack == .odyssey {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("奥德赛视觉篇章"))
                                    .font(.callout.weight(.heavy))
                                    .foregroundStyle(Color.tokenInk)
                                Text(L("导演剪辑会为不同界面自动分配冷雾、火海与灰烬。"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(appState.settings.odysseyChapter.title)
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(Color.tokenGreenDark)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.tokenGreen.opacity(0.12), in: Capsule())
                                .overlay(Capsule().stroke(Color.tokenHairlineStrong))
                        }

                        HStack(spacing: 8) {
                            ForEach(TokenStepOdysseyChapter.allCases) { chapter in
                                OdysseyChapterButton(
                                    chapter: chapter,
                                    selected: appState.settings.odysseyChapter == chapter
                                ) {
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        appState.setOdysseyChapter(chapter)
                                    }
                                }
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if appState.settings.themePack == .interstellar {
                    HStack(spacing: 14) {
                        InterstellarEventHorizonEmblem()
                            .frame(width: 126, height: 58)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(L("引力边界 · 近距事件视界"))
                                .font(.callout.weight(.heavy))
                                .foregroundStyle(Color.tokenInk)
                            Text(L("巨大黑洞、象牙白吸积盘与克制电影色；低亮与减少动态时自动静止。"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        Text(L("原创动态主题"))
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Color.tokenGreenDark)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.tokenGreen.opacity(0.12), in: Capsule())
                            .overlay(Capsule().stroke(Color.tokenHairlineStrong))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("经典主题色"))
                                .font(.callout.weight(.heavy))
                                .foregroundStyle(Color.tokenInk)
                            Text(L("原版 TokenStep 的五种明亮配色"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(TokenStepTheme.classicCases) { theme in
                                Button {
                                    appState.setClassicTheme(theme)
                                } label: {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [theme.palette.accentSoft.color, theme.palette.accent.color],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 27, height: 27)
                                        .overlay(
                                            Circle().stroke(
                                                theme == appState.settings.classicTheme ? Color.tokenInk : Color.clear,
                                                lineWidth: 2
                                            )
                                        )
                                        .overlay {
                                            if theme == appState.settings.classicTheme {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .black))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .help(theme.title)
                            }
                        }
                    }
                    .padding(.vertical, 7)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}
