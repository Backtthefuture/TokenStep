import SwiftUI

/// G-V1：统一新鲜度徽章（浮层 / 主窗口 / 额度卡共用一套术语与配色）。
struct FreshnessBadge: View {
    var freshness: UsageFreshness
    /// 是否附带"最后成功 …"信息（头部胶囊与额度行开启，紧凑场景可关）。
    var showsLastSucceeded = true

    private var accent: Color {
        switch freshness.kind {
        case .fresh: return .tokenGreen
        case .aging, .partial: return .orange
        case .stale: return .red
        case .neverSucceeded, .disabled: return .secondary
        }
    }

    private var symbol: String {
        switch freshness.kind {
        case .fresh: return "checkmark.circle.fill"
        case .aging: return "clock.fill"
        case .stale: return "exclamationmark.triangle.fill"
        case .partial: return "exclamationmark.arrow.triangle.2.circlepath"
        case .neverSucceeded: return "circle.dashed"
        case .disabled: return "pause.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(accent)
            Text(freshness.statusLabel)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Color.tokenInk.opacity(0.78))
            if showsLastSucceeded, let lastSucceeded = freshness.lastSucceededLabel() {
                Text("· \(lastSucceeded)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.tokenSurface, in: Capsule())
        .overlay(Capsule().stroke(accent.opacity(0.32)))
        .help(helpText)
    }

    private var helpText: String {
        var lines = [freshness.statusLabel]
        if let keeps = freshness.keepsLastValueLabel {
            lines.append(keeps)
        }
        if let lastSucceeded = freshness.lastSucceededLabel() {
            lines.append(lastSucceeded)
        }
        if let errorKind = freshness.errorKind {
            lines.append(errorKind.localizedSummary)
        }
        if let failed = freshness.failedSources, !failed.isEmpty {
            lines.append(LFormat("失败来源：%@", failed.joined(separator: ", ")))
        }
        return lines.joined(separator: "\n")
    }
}

struct TokenCard<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(24)
            .background(Color.tokenSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.black.opacity(0.06)))
            .shadow(color: Color.black.opacity(0.055), radius: 24, x: 0, y: 14)
    }
}
