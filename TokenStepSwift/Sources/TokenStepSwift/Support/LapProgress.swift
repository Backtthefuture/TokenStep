import SwiftUI

struct TokenStepLapProgress {
    var tokens: Int
    var goal: Int

    var safeGoal: Int { max(goal, 1) }
    var rawProgress: Double { Double(tokens) / Double(safeGoal) }
    var completedLaps: Int { tokens / safeGoal }

    var currentLap: Int {
        guard tokens > 0 else { return 1 }
        let remainder = tokens % safeGoal
        return max(1, completedLaps + (remainder > 0 ? 1 : 0))
    }

    var currentLapProgress: Double {
        guard tokens > 0 else { return 0 }
        let remainder = tokens % safeGoal
        if remainder == 0 { return 1 }
        return Double(remainder) / Double(safeGoal)
    }

    var currentLapPercent: Double {
        currentLapProgress * 100
    }

    var color: Color {
        Self.color(for: currentLap)
    }

    var ringColor: Color {
        TokenStepThemeRuntime.palette.accent.color
    }

    var lapTitle: String {
        LFormat("第 %d 圈", currentLap)
    }

    var lapPercentText: String {
        TokenStepFormat.percent(currentLapPercent)
    }

    var lapStatusText: String {
        LFormat("第 %d 圈 · %@", currentLap, lapPercentText)
    }

    var completedLapsText: String {
        LFormat("已完成 %d 圈", completedLaps)
    }

    var completedTokensText: String {
        LFormat("已完成 %@", TokenStepFormat.tokens(completedLaps * safeGoal, compact: true))
    }

    var perLapGoalText: String {
        LFormat("每圈目标 %@", TokenStepFormat.tokens(safeGoal, compact: true))
    }

    static func color(for lap: Int) -> Color {
        let rgb = rgb(for: lap)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    static func rgb(for lap: Int) -> (red: Double, green: Double, blue: Double) {
        let rgb = TokenStepThemeRuntime.palette.ringRGB(for: lap)
        return (rgb.red, rgb.green, rgb.blue)
    }
}
