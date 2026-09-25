import Foundation
import SwiftUI

enum TokenStepFormat {
    static func tokens(_ value: Int, compact: Bool = false, language explicitLanguage: TokenStepLanguage? = nil) -> String {
        let language = explicitLanguage?.resolved ?? TokenStepLocalization.language
        if language == .en {
            if value >= 1_000_000_000 {
                return "\(trim(Double(value) / 1_000_000_000, digits: 2))B"
            }
            if value >= 1_000_000 {
                let digits = compact || value >= 10_000_000 ? 0 : 1
                return "\(trim(Double(value) / 1_000_000, digits: digits))M"
            }
            if value >= 1_000 {
                let digits = compact || value >= 10_000 ? 0 : 1
                return "\(trim(Double(value) / 1_000, digits: digits))K"
            }
            return "\(value)"
        }
        let hundredMillionUnit = language == .zhHant ? "億" : "亿"
        let tenThousandUnit = language == .zhHant ? "萬" : "万"
        if value >= 100_000_000 {
            return "\(trim(Double(value) / 100_000_000, digits: 2))\(hundredMillionUnit)"
        }
        if value >= 10_000 {
            let digits = compact || value >= 10_000_000 ? 0 : 1
            return "\(trim(Double(value) / 10_000, digits: digits))\(tenThousandUnit)"
        }
        return "\(value)"
    }

    static func money(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    static func percent(_ value: Double) -> String {
        if value >= 100 { return "\(Int(value.rounded()))%" }
        if value >= 10 { return String(format: "%.1f%%", value) }
        return "\(Int(value.rounded()))%"
    }

    static func generatedTime(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return L("等待同步") }
        guard let date = isoDate(value) else {
            return value.replacingOccurrences(of: "T", with: " ").prefix(16).description
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TokenStepClock.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func intervalLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0: return L("手动")
        case 60: return L("1 分钟")
        default: return LFormat("%d 分钟", seconds / 60)
        }
    }

    private static func trim(_ value: Double, digits: Int) -> String {
        let text = String(format: "%.\(digits)f", value)
        return text.replacingOccurrences(of: #"(\.0+|(?<=\.\d)0+)$"#, with: "", options: .regularExpression)
    }

    private static func isoDate(_ value: String) -> Date? {
        if let date = isoFormatterWithFractional.date(from: value) {
            return date
        }
        return isoFormatter.date(from: value)
    }

    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

extension DateFormatter {
    static let tokenStepDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TokenStepClock.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension Color {
    static var tokenInk: Color { TokenStepThemeRuntime.theme.inkColor }
    static var tokenCanvas: Color { TokenStepThemeRuntime.palette.canvas.color }
    static var tokenSurface: Color { TokenStepThemeRuntime.palette.surface.color }
    static var tokenGreen: Color { TokenStepThemeRuntime.palette.accent.color }
    static var tokenGreenDark: Color { TokenStepThemeRuntime.palette.accentDark.color }
    static var tokenToggleTint: Color {
        TokenStepThemeRuntime.isCinematic ? tokenGreenDark : tokenGreen
    }
    static var tokenMint: Color { TokenStepThemeRuntime.palette.accentSoft.color }
    static var tokenTrack: Color { TokenStepThemeRuntime.palette.track.color }
    static var tokenLowActivity: Color { TokenStepThemeRuntime.palette.lowActivity.color }
    static var tokenDivider: Color { TokenStepThemeRuntime.theme.dividerColor }
    static var tokenHairline: Color {
        TokenStepThemeRuntime.isCinematic
            ? TokenStepThemeRuntime.palette.accentDark.color.opacity(0.22)
            : Color.black.opacity(0.055)
    }
    static var tokenHairlineStrong: Color {
        TokenStepThemeRuntime.isCinematic
            ? TokenStepThemeRuntime.palette.accent.color.opacity(0.48)
            : Color.black.opacity(0.09)
    }
    static var tokenInnerHighlight: Color {
        TokenStepThemeRuntime.isCinematic
            ? Color(red: 240 / 255, green: 209 / 255, blue: 156 / 255).opacity(0.08)
            : Color.white.opacity(0.42)
    }
    static var tokenShadow: Color {
        TokenStepThemeRuntime.isCinematic
            ? Color.black.opacity(0.34)
            : Color.black.opacity(0.055)
    }
    static var tokenActionText: Color {
        TokenStepThemeRuntime.isCinematic
            ? Color(red: 22 / 255, green: 18 / 255, blue: 14 / 255)
            : Color.white
    }
    static var tokenMutedFill: Color {
        TokenStepThemeRuntime.isCinematic
            ? TokenStepThemeRuntime.palette.track.color.opacity(0.52)
            : TokenStepThemeRuntime.palette.track.color.opacity(0.42)
    }
    static var tokenWarning: Color {
        TokenStepThemeRuntime.isCinematic
            ? Color(red: 218 / 255, green: 139 / 255, blue: 67 / 255)
            : Color.orange
    }
    static let tokenSuccess = Color(red: 79 / 255, green: 167 / 255, blue: 123 / 255)
}

extension ToolUsage {
    var displayColor: Color {
        AgentSourceRegistry.color(for: tool)
    }
}

extension ModelUsage {
    var displayColor: Color {
        AgentSourceRegistry.color(for: tool ?? model)
    }
}
