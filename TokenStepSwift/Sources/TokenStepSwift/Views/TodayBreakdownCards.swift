import SwiftUI

struct TodayBreakdownRow: Identifiable {
    var id: String { name }
    var name: String
    var tokens: Int
    var percent: Double
    var color: Color?
}
