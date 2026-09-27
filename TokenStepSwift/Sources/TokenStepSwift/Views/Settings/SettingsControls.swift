import SwiftUI

struct RefreshOption: Identifiable {
    var id: Int { seconds }
    var seconds: Int
    var title: String
}

struct DisplayPlacementButton: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                }
                Text(title)
                    .font(.caption.weight(.heavy))
            }
            .foregroundStyle(selected ? Color.tokenActionText : Color.tokenInk.opacity(0.72))
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(selected ? Color.tokenGreen : Color.tokenTrack.opacity(0.42), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(selected ? Color.tokenHairlineStrong : Color.tokenHairline))
        }
        .buttonStyle(.plain)
    }
}

enum SettingsBadgeStyle {
    case ok, warn, off, l1, l2, l3

    var foreground: Color {
        if TokenStepThemeRuntime.isCinematic {
            switch self {
            case .ok, .l1: return Color.tokenSuccess
            case .warn: return Color.tokenWarning
            case .off: return Color.secondary
            case .l2: return Color.tokenGreen
            case .l3: return Color.tokenGreenDark
            }
        }
        switch self {
        case .ok, .l1: return Color(red: 0.11, green: 0.36, blue: 0.23)
        case .warn: return Color(red: 0.56, green: 0.29, blue: 0.09)
        case .off: return Color.secondary
        case .l2: return Color(red: 0.24, green: 0.30, blue: 0.56)
        case .l3: return Color(red: 0.36, green: 0.25, blue: 0.59)
        }
    }

    var background: Color {
        if TokenStepThemeRuntime.isCinematic {
            switch self {
            case .ok, .l1: return Color.tokenSuccess.opacity(0.12)
            case .warn: return Color.tokenWarning.opacity(0.12)
            case .off: return Color.tokenMutedFill
            case .l2: return Color.tokenGreen.opacity(0.12)
            case .l3: return Color.tokenGreenDark.opacity(0.12)
            }
        }
        switch self {
        case .ok, .l1: return Color(red: 0.90, green: 0.95, blue: 0.89)
        case .warn: return Color(red: 0.97, green: 0.93, blue: 0.87)
        case .off: return Color.tokenTrack.opacity(0.45)
        case .l2: return Color(red: 0.91, green: 0.93, blue: 0.97)
        case .l3: return Color(red: 0.94, green: 0.92, blue: 0.98)
        }
    }

    var border: Color {
        if TokenStepThemeRuntime.isCinematic {
            switch self {
            case .ok, .l1: return Color.tokenSuccess.opacity(0.30)
            case .warn: return Color.tokenWarning.opacity(0.34)
            case .off: return Color.tokenHairline
            case .l2: return Color.tokenGreen.opacity(0.34)
            case .l3: return Color.tokenGreenDark.opacity(0.38)
            }
        }
        switch self {
        case .ok, .l1: return Color(red: 0.76, green: 0.86, blue: 0.78)
        case .warn: return Color(red: 0.90, green: 0.80, blue: 0.71)
        case .off: return Color.black.opacity(0.08)
        case .l2: return Color(red: 0.78, green: 0.80, blue: 0.90)
        case .l3: return Color(red: 0.84, green: 0.80, blue: 0.91)
        }
    }
}

struct SettingsBadge: View {
    var text: String
    var style: SettingsBadgeStyle

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(style.foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(style.background, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(style.border)
            )
    }
}

struct SettingsSectionCard<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    var badge: String? = nil
    var badgeStyle: SettingsBadgeStyle = .off
    var tint: SettingsBadgeStyle? = nil
    var content: Content

    init(
        title: String,
        subtitle: String? = nil,
        badge: String? = nil,
        badgeStyle: SettingsBadgeStyle = .off,
        tint: SettingsBadgeStyle? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.badgeStyle = badgeStyle
        self.tint = tint
        self.content = content()
    }

    /// A grouped section as in System Settings: the title and note sit above
    /// a plain rounded group that holds the rows.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.tokenInk.opacity(0.78))
                    if let badge {
                        SettingsBadge(text: badge, style: badgeStyle)
                    }
                    Spacer(minLength: 0)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 4)

            // One stack so a multi-part body stays in one group.
            VStack(alignment: .leading, spacing: 10) {
                content
            }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.tokenSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.tokenHairline)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsPickerChip: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.tokenGreenDark : Color.tokenInk.opacity(0.72))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    selected ? Color.tokenGreen.opacity(0.14) : Color.tokenSurface,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(selected ? Color.tokenGreen.opacity(0.7) : Color.tokenHairline)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct SettingsCard<Content: View>: View {
    var title: String
    var symbol: String
    var height: CGFloat
    var content: Content

    init(title: String, symbol: String, height: CGFloat = 260, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.height = height
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.tokenGreenDark)
                    .frame(width: 30, height: 30)
                    .background(Color.tokenMint.opacity(0.22), in: Circle())
                Text(title)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.tokenInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer()
            }
            .frame(height: 32, alignment: .center)

            content
                .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 22)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.tokenSurface)
                if TokenStepThemeRuntime.isCinematic {
                    LinearGradient(
                        colors: [Color.tokenGreen.opacity(0.05), Color.clear, Color.tokenGreenDark.opacity(0.025)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
        }
        .overlay {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.tokenHairline)
                if TokenStepThemeRuntime.isVoyage {
                    VoyageCardOrnament(cornerRadius: 24)
                } else if TokenStepThemeRuntime.isInterstellar {
                    InterstellarCardOrnament(cornerRadius: 24)
                }
            }
        }
        .shadow(color: Color.tokenShadow, radius: 22, x: 0, y: 14)
    }
}

struct GoalStepButton: View {
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color.tokenInk.opacity(0.78))
                .frame(width: 34, height: 30)
                .background(Color.tokenTrack.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.tokenHairline))
        }
        .buttonStyle(.plain)
    }
}

struct ThemeSwatchButton: View {
    var theme: TokenStepTheme
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    if theme == .voyage || theme == .eventHorizon {
                        TokenStepMark(size: 38)
                            .shadow(color: theme.palette.accentDark.color.opacity(selected ? 0.24 : 0.12), radius: 8, x: 0, y: 4)
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        theme.palette.accentSoft.color,
                                        theme.palette.accent.color,
                                        theme.palette.accentDark.color
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 38, height: 38)
                            .shadow(color: theme.palette.accentDark.color.opacity(selected ? 0.22 : 0.10), radius: 8, x: 0, y: 4)
                    }

                    if selected && theme != .voyage {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(theme == .voyage || theme == .eventHorizon ? Color.tokenActionText : Color.white)
                    }
                }

                VStack(spacing: 1) {
                    Text(theme.title)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(selected ? Color.tokenInk : Color.tokenInk.opacity(0.74))
                    Text(theme.subtitle)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .background(selected ? theme.palette.accentSoft.color.opacity(0.22) : Color.tokenTrack.opacity(0.24), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? theme.palette.accent.color.opacity(0.46) : Color.tokenHairline, lineWidth: selected ? 1.4 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(LFormat("切换到%@主题", theme.title))
    }
}

struct ThemePackOptionButton: View {
    var pack: TokenStepThemePack
    var selected: Bool
    var classicTheme: TokenStepTheme
    var odysseyChapter: TokenStepOdysseyChapter
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                preview
                    .frame(width: 58, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(pack.title)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.tokenInk)
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(Color.tokenGreen)
                        }
                    }
                    Text(pack.subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(
                selected ? Color.tokenGreen.opacity(0.11) : Color.tokenTrack.opacity(0.22),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(selected ? Color.tokenGreen.opacity(0.68) : Color.tokenHairline, lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(LFormat("切换到%@主题包", pack.title))
    }

    @ViewBuilder
    private var preview: some View {
        switch pack {
        case .classic:
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(classicTheme.palette.surface.color)
                .overlay {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(Array([0.42, 0.62, 0.82, 1.0].enumerated()), id: \.offset) { index, scale in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(classicTheme.palette.activityColor(for: index + 1))
                                .frame(width: 6, height: 24 * scale)
                        }
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.black.opacity(0.08)))
        case .odyssey:
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [odysseyChapter.palette.surface.color, odysseyChapter.palette.canvas.color],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    ZStack {
                        Image(systemName: odysseyChapter.symbol)
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(odysseyChapter.palette.accent.color.opacity(0.88))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(odysseyChapter.palette.accentDark.color)
                            .offset(x: 16, y: -13)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(odysseyChapter.palette.accent.color.opacity(0.46)))
        case .interstellar:
            InterstellarThemePreview()
        }
    }
}

struct OdysseyChapterButton: View {
    var chapter: TokenStepOdysseyChapter
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(chapter.palette.accentSoft.color.opacity(0.58))
                        Image(systemName: chapter.symbol)
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(chapter.palette.accentDark.color)
                    }
                    .frame(width: 34, height: 30)

                    Spacer(minLength: 4)

                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(chapter.palette.accentDark.color)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.title)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                        .lineLimit(1)
                    Text(chapter.subtitle)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 82)
            .background(
                LinearGradient(
                    colors: [
                        chapter.palette.surface.color.opacity(selected ? 0.96 : 0.55),
                        chapter.palette.canvas.color.opacity(selected ? 0.88 : 0.46)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        selected ? chapter.palette.accent.color.opacity(0.78) : Color.tokenHairline,
                        lineWidth: selected ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(LFormat("切换到%@篇章", chapter.title))
    }
}

struct LanguageOptionButton: View {
    var language: TokenStepLanguage
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(selected ? Color.tokenGreen : Color.secondary.opacity(0.58))

                VStack(alignment: .leading, spacing: 1) {
                    Text(language.title)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(Color.tokenInk.opacity(selected ? 0.92 : 0.74))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(language.subtitle)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .padding(.horizontal, 10)
            .background(selected ? Color.tokenMint.opacity(0.24) : Color.tokenTrack.opacity(0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? Color.tokenGreen.opacity(0.32) : Color.tokenHairline))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct PresetChip: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.heavy))
                .foregroundStyle(selected ? Color.tokenActionText : Color.tokenInk.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .frame(height: 33)
                .background(selected ? Color.tokenGreen : Color.tokenTrack.opacity(0.45), in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.tokenHairlineStrong : Color.tokenHairline))
        }
        .buttonStyle(.plain)
    }
}

struct RefreshOptionButton: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                }
                Text(title)
                    .font(.callout.weight(.heavy))
            }
            .foregroundStyle(selected ? Color.tokenActionText : Color.tokenInk.opacity(0.7))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(selected ? Color.tokenGreen : Color.tokenTrack.opacity(0.42), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? Color.tokenHairlineStrong : Color.tokenHairline))
        }
        .buttonStyle(.plain)
    }
}

struct TokenStepSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(
                        configuration.isOn
                            ? Color.tokenToggleTint
                            : Color.tokenTrack.opacity(TokenStepThemeRuntime.isCinematic ? 0.82 : 0.72)
                    )
                Circle()
                    .fill(Color.white)
                    .padding(2)
                    .shadow(color: Color.black.opacity(0.24), radius: 2, x: 0, y: 1)
            }
            .frame(width: 36, height: 20)
            .overlay(
                Capsule()
                    .stroke(configuration.isOn ? Color.tokenGreenDark.opacity(0.74) : Color.tokenHairline)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? L("已开启") : L("已关闭"))
    }
}

struct SettingsToggleRow: View {
    var title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(isOn ? Color.tokenGreen : Color.secondary.opacity(0.65))
            Text(title)
                .font(.callout.weight(.bold))
                .foregroundStyle(Color.tokenInk.opacity(0.78))
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(TokenStepSwitchToggleStyle())
        }
    }
}

struct StatusLine: View {
    var symbol: String
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(title)
                .font(.callout.weight(.heavy))
                .foregroundStyle(Color.tokenInk)
            Spacer()
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Color.tokenTrack.opacity(0.3), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SettingsInfoRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.tokenInk.opacity(0.78))
                .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(Color.tokenTrack.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct PrivacyCheckRow: View {
    var title: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color.tokenSuccess)
            Text(title)
                .font(.callout.weight(.bold))
                .foregroundStyle(Color.tokenInk.opacity(0.78))
            Spacer(minLength: 0)
        }
    }
}

struct PrivacyMetaChip: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.heavy))
            .foregroundStyle(Color.tokenInk.opacity(0.66))
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.tokenTrack.opacity(0.35), in: Capsule())
    }
}

struct SettingsPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.tokenActionText)
            .background(Color.tokenGreen, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct SettingsSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.tokenInk.opacity(0.72))
            .background(Color.tokenTrack.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.tokenHairline))
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}
