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
            .foregroundStyle(selected ? Color.white : Color.tokenInk.opacity(0.72))
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(selected ? Color.tokenGreen : Color.tokenTrack.opacity(0.42), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(selected ? Color.clear : Color.black.opacity(0.04)))
        }
        .buttonStyle(.plain)
    }
}

struct SettingsCard<Content: View>: View {
    var title: String
    var symbol: String
    var content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
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
        .padding(.top, 20)
        .padding(.bottom, 22)
        .frame(height: 238)
        .frame(maxWidth: .infinity)
        .background(Color.tokenSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.black.opacity(0.06)))
        .shadow(color: Color.black.opacity(0.055), radius: 22, x: 0, y: 14)
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
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.black.opacity(0.05)))
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

                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.white)
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
            .frame(height: 88)
            .background(selected ? theme.palette.accentSoft.color.opacity(0.22) : Color.tokenTrack.opacity(0.24), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? theme.palette.accent.color.opacity(0.46) : Color.black.opacity(0.045), lineWidth: selected ? 1.4 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(LFormat("切换到%@主题", theme.title))
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
            .frame(height: 43)
            .padding(.horizontal, 10)
            .background(selected ? Color.tokenMint.opacity(0.24) : Color.tokenTrack.opacity(0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? Color.tokenGreen.opacity(0.32) : Color.black.opacity(0.04)))
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
                .foregroundStyle(selected ? Color.white : Color.tokenInk.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .frame(height: 33)
                .background(selected ? Color.tokenGreen : Color.tokenTrack.opacity(0.45), in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : Color.black.opacity(0.045)))
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
            .foregroundStyle(selected ? Color.white : Color.tokenInk.opacity(0.7))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(selected ? Color.tokenGreen : Color.tokenTrack.opacity(0.42), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? Color.clear : Color.black.opacity(0.035)))
        }
        .buttonStyle(.plain)
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
                .toggleStyle(.switch)
                .controlSize(.small)
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
                .foregroundStyle(Color.tokenGreen)
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
            .foregroundStyle(.white)
            .background(Color.tokenGreen, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct SettingsSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.tokenInk.opacity(0.72))
            .background(Color.tokenTrack.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.black.opacity(0.045)))
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}
