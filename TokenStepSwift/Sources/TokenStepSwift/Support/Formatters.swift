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
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
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
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension Color {
    static let tokenInk = Color(red: 31 / 255, green: 41 / 255, blue: 55 / 255)
    static var tokenCanvas: Color { TokenStepThemeRuntime.palette.canvas.color }
    static var tokenSurface: Color { TokenStepThemeRuntime.palette.surface.color }
    static var tokenGreen: Color { TokenStepThemeRuntime.palette.accent.color }
    static var tokenGreenDark: Color { TokenStepThemeRuntime.palette.accentDark.color }
    static var tokenMint: Color { TokenStepThemeRuntime.palette.accentSoft.color }
    static var tokenTrack: Color { TokenStepThemeRuntime.palette.track.color }
    static var tokenLowActivity: Color { TokenStepThemeRuntime.palette.lowActivity.color }
}

extension ToolUsage {
    var displayColor: Color {
        tool == "Claude Code" ? .tokenGreenDark : .tokenGreen
    }
}

extension ModelUsage {
    var displayColor: Color {
        tool == "Claude Code" ? .tokenGreenDark : .tokenGreen
    }
}
