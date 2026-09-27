import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState
    /// Opens the History tab from the recent-weeks card; nil hides the link
    /// (screenshots).
    var openHistory: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            // Wide: ring, metrics and recent weeks in one row. Narrow: the
            // metrics drop below as a single row of four.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    TodayRingCard()
                        .frame(width: 380)
                    TodayMetricsGrid(columns: 2)
                        .frame(minWidth: 260, maxWidth: .infinity)
                    TodayRecentWeeksCard(openHistory: openHistory)
                        .frame(width: 260)
                }
                .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        TodayRingCard()
                        TodayRecentWeeksCard(openHistory: openHistory)
                            .frame(width: 260)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    TodayMetricsGrid(columns: 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            TodayHourlyStackCard()

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    TodayClientsCard()
                        .frame(minWidth: 420)
                    TodayModelRankCard()
                        .frame(minWidth: 420)
                }
                .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 16) {
                    TodayClientsCard()
                    TodayModelRankCard()
                }
            }

            if appState.settings.cursorCodeSignalEnabled {
                CursorCodeSignalCard()
            }
        }
    }
}
