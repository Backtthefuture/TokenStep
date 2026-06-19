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

    var lapTitle: String {
        "第 \(currentLap) 圈"
    }

    var lapPercentText: String {
        TokenStepFormat.percent(currentLapPercent)
    }

    var lapStatusText: String {
        "\(lapTitle) · \(lapPercentText)"
    }

    var completedLapsText: String {
        "已完成 \(completedLaps) 圈"
    }

    var completedTokensText: String {
        "已完成 \(TokenStepFormat.tokens(completedLaps * safeGoal, compact: true))"
    }

    var perLapGoalText: String {
        "每圈目标 \(TokenStepFormat.tokens(safeGoal, compact: true))"
    }

    static func color(for lap: Int) -> Color {
        let rgb = rgb(for: lap)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    static func rgb(for lap: Int) -> (red: Double, green: Double, blue: Double) {
        switch max(lap, 1) {
        case 1: return (64 / 255, 196 / 255, 99 / 255)
        case 2: return (48 / 255, 161 / 255, 78 / 255)
        case 3: return (33 / 255, 110 / 255, 57 / 255)
        default: return (14 / 255, 68 / 255, 41 / 255)
        }
    }
}
