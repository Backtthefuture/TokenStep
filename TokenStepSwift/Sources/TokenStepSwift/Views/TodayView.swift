import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 13) {
                TodayHeroCard()
                TodayAgentIntensityCard()
            }

            HStack(alignment: .top, spacing: 13) {
                TodayHourlyCard()
                TodaySourcesCard()
            }

            TodayModelUsageCard()

            if appState.settings.cursorCodeSignalEnabled {
                CursorCodeSignalCard()
            }
        }
    }
}
