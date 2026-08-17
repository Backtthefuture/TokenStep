import SwiftUI

struct PopoverAgentWorkTable: View {
    @EnvironmentObject private var appState: AppState

    private var work: DailyAgentWork {
        appState.todayAgentWork
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Agent 用量"))
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.tokenInk)
                Spacer()
                Text(LFormat("%d 个来源", rows.count))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            if rows.isEmpty {
                Text(L("今日还没有 Agent 记录"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(spacing: 0) {
                    header
                    ForEach(rows) { row in
                        rowView(row)
                    }
                }
                Text(L("Cursor 官方用量，计入圆环"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            MainWindowPresenter.shared.show(appState: appState, section: .today)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(L("来源")).frame(maxWidth: .infinity, alignment: .leading)
            Text(L("Token")).frame(width: 72, alignment: .trailing)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.bottom, 6)
    }

    private func rowView(_ row: AgentWorkSource) -> some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .center, spacing: 6) {
                Circle()
                    .fill(tokenToolColor(row.source))
                    .frame(width: 7, height: 7)
                Text(row.source)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(TokenStepFormat.tokens(row.tokens, compact: true))
                .frame(width: 72, alignment: .trailing)
                .monospacedDigit()
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.tokenInk.opacity(0.82))
        .padding(.vertical, 7)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.black.opacity(0.05)).frame(height: 1)
        }
    }

    private var rows: [AgentWorkSource] {
        work.sources
            .filter { $0.tokens > 0 }
            .sorted { $0.tokens > $1.tokens }
    }
}
