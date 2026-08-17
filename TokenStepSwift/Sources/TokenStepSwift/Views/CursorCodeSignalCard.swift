import SwiftUI

struct CursorCodeSignalCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TokenCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Text(L("Cursor 代码产出"))
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                    SettingsBadge(text: L("L3 · 不计入圆环"), style: .l3)
                    Spacer()
                    SettingsBadge(text: L("纯本地 · ai-code-tracking.db"), style: .off)
                }

                Text(L("Cursor 本地没有 token 数，只有产出量。这里回答「AI 帮我写了多少」，不参与 Token 总量。"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = appState.cursorCodeSignalError, appState.cursorCodeSignal == nil {
                    Text(error)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if let signal = appState.cursorCodeSignal, !signal.isEmpty {
                    HStack(spacing: 18) {
                        TodaySignalStat(label: L("AI 代码块"), value: "\(signal.blockCount)")
                    }

                    if !signal.models.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(signal.models.prefix(3).enumerated()), id: \.element.name) { index, model in
                                TodayKVRowPublic(
                                    label: model.name,
                                    value: LFormat("%d 块", model.blocks),
                                    dot: modelDot(index)
                                )
                            }
                        }
                    }
                } else {
                    Text(L("今日暂无"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(red: 0.42, green: 0.36, blue: 0.82).opacity(0.18))
        )
    }

    private func modelDot(_ index: Int) -> Color {
        let colors = [
            Color(red: 0.42, green: 0.36, blue: 0.82),
            Color(red: 0.56, green: 0.50, blue: 0.88),
            Color(red: 0.70, green: 0.66, blue: 0.92)
        ]
        return colors[min(index, colors.count - 1)]
    }
}

private struct TodaySignalStat: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.tokenInk)
                .monospacedDigit()
        }
    }
}

struct TodayKVRowPublic: View {
    var label: String
    var value: String
    var dot: Color?

    var body: some View {
        HStack(spacing: 8) {
            if let dot {
                Circle()
                    .fill(dot)
                    .frame(width: 8, height: 8)
            }
            Text(label)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.tokenInk)
                .lineLimit(1)
            Spacer()
            Text(value)
                .font(.callout.weight(.heavy))
                .foregroundStyle(Color.tokenInk)
                .monospacedDigit()
        }
        .padding(.vertical, 7)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 1)
        }
    }
}
