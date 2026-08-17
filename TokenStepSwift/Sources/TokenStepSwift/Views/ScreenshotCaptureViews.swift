import SwiftUI

struct DashboardScreenshotView: View {
    @EnvironmentObject private var appState: AppState
    var section: AppSection

    var body: some View {
        ZStack {
            TokenStepBackdrop()

            VStack(alignment: .leading, spacing: 16) {
                captureHeader
                detailView
            }
            .padding(20)
        }
        .frame(width: 1000)
        .fixedSize(horizontal: false, vertical: true)
        .id(appState.appearanceID)
    }

    private var captureHeader: some View {
        HStack(spacing: 12) {
            TokenStepMark(size: 22)
            Text("TokenStep")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.tokenInk)
            Spacer()
            HStack(spacing: 3) {
                ForEach(AppSection.allCases) { item in
                    Text(item.title)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(item == section ? Color.tokenInk : Color.tokenInk.opacity(0.45))
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(
                            item == section ? Color.tokenSurface : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
            }
            .padding(3)
            .background(Color.tokenTrack.opacity(0.55), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Spacer()
            Text("\(L("更新")) \(TokenStepFormat.generatedTime(appState.snapshot.generatedAt))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch section {
        case .today:
            TodayView()
        case .history:
            HistoryView(historyLimit: 30)
        case .privacy:
            PrivacyView()
        }
    }
}
