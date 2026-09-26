import AppKit
import SwiftUI

// MARK: - Provider icon

/// The provider's installed app icon when one is found, then a bundled mark
/// (see `ProviderMark`), otherwise a monogram tile in the provider's color.
struct QuotaProviderIcon: View {
    var provider: QuotaProviderID
    var size: CGFloat = 20

    var body: some View {
        if let image = Self.appIcon(for: provider) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else if provider == .claude {
            // Cream tile like Claude's app icon, so the mark sits at the same
            // visual weight as the other providers' app icons.
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(Color(red: 244 / 255, green: 243 / 255, blue: 238 / 255))
                .frame(width: size, height: size)
                .overlay {
                    SVGPathShape(pathData: ProviderMark.claudePath)
                        .fill(ProviderMark.claudeColor)
                        .padding(size * 0.12)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                }
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(AgentSourceRegistry.color(for: provider.rawValue))
                .frame(width: size, height: size)
                .overlay {
                    Text(Self.monogram(for: provider))
                        .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                }
                .accessibilityHidden(true)
        }
    }

    static func monogram(for provider: QuotaProviderID) -> String {
        switch provider {
        case .codex: return "Cx"
        case .claude: return "Cl"
        case .cursor: return "Cu"
        case .glm: return "GL"
        case .kimi: return "Km"
        case .grok: return "Gk"
        }
    }

    /// Bundle identifiers of each provider's desktop app, most specific first.
    private static let bundleIdentifiers: [QuotaProviderID: [String]] = [
        .codex: ["com.openai.codex", "com.openai.chat"],
        .claude: ["com.anthropic.claudefordesktop"],
        .cursor: ["com.todesktop.230313mzl4w4u92"]
    ]

    private static var iconCache: [QuotaProviderID: NSImage?] = [:]

    static func appIcon(for provider: QuotaProviderID) -> NSImage? {
        if let cached = iconCache[provider] {
            return cached
        }
        let icon = (bundleIdentifiers[provider] ?? [])
            .lazy
            .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .first
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        iconCache[provider] = .some(icon)
        return icon
    }
}

// MARK: - Shared styling

enum CompactPopoverStyle {
    static let width: CGFloat = 340
    static let horizontalPadding: CGFloat = 16

    static func color(for level: CompactPopoverModel.QuotaLevel) -> Color {
        switch level {
        case .normal: return Color.tokenGreen
        case .warning: return Color.tokenWarning
        case .critical: return Color(red: 201 / 255, green: 60 / 255, blue: 55 / 255)
        }
    }

    static func textColor(for level: CompactPopoverModel.QuotaLevel) -> Color {
        level == .normal ? Color.tokenInk : color(for: level)
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func minutes(_ value: Int) -> String {
        if value < 60 {
            return LFormat("%d 分钟", value)
        }
        let hours = value / 60
        let rest = value % 60
        return rest == 0 ? LFormat("%d 小时", hours) : LFormat("%d 小时 %d 分", hours, rest)
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 {
            return L("刚刚")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = TokenStepLocalization.locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func resetText(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let calendar = TokenStepClock.calendar
        let minutes = Int(date.timeIntervalSince(now) / 60)
        if minutes < 1 {
            return L("即将重置")
        }
        if minutes < 60 {
            return LFormat("%d 分钟后", minutes)
        }
        let time = DateFormatter()
        time.locale = TokenStepLocalization.locale
        time.timeZone = TokenStepClock.timeZone
        time.setLocalizedDateFormatFromTemplate("HHmm")
        if calendar.isDate(date, inSameDayAs: now) {
            return LFormat("今天 %@", time.string(from: date))
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            // "Tomorrow 17:01" does not fit the column in English; a weekday does.
            if TokenStepLocalization.language == .en {
                time.setLocalizedDateFormatFromTemplate("EEEHHmm")
                return time.string(from: date)
            }
            return LFormat("明天 %@", time.string(from: date))
        }
        let day = DateFormatter()
        day.locale = TokenStepLocalization.locale
        day.timeZone = TokenStepClock.timeZone
        day.setLocalizedDateFormatFromTemplate("MMMd")
        return day.string(from: date)
    }
}

private struct CompactSectionHeader: View {
    var title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.tokenInk.opacity(0.62))
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CompactBar: View {
    var fraction: Double
    var color: Color
    var height: CGFloat = 6
    var marker: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.tokenTrack)
                Capsule()
                    .fill(color)
                    .frame(width: max(proxy.size.width * min(max(fraction, 0), 1), fraction > 0 ? height : 0))
                if let marker {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.tokenInk.opacity(0.55))
                        .frame(width: 2, height: height + 6)
                        .offset(x: proxy.size.width * min(max(marker, 0), 1) - 1)
                }
            }
            .frame(height: proxy.size.height)
        }
        .frame(height: height)
    }
}

// MARK: - Quota section

struct CompactQuotaSection: View {
    var section: CompactPopoverModel.QuotaSection
    var updatedAt: Date?
    @State private var showsFolded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CompactSectionHeader(
                title: L("额度"),
                trailing: updatedAt.map { LFormat("已用 · %@", CompactPopoverStyle.relative($0)) } ?? L("已用")
            )
            ForEach(section.expanded) { provider in
                providerBlock(provider)
            }
            if showsFolded {
                ForEach(section.folded) { provider in
                    providerBlock(provider)
                }
            }
            if !section.folded.isEmpty {
                Button {
                    showsFolded.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Text(showsFolded ? L("收起") : foldedSummary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        Image(systemName: showsFolded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color.tokenInk.opacity(0.74))
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(Color.tokenTrack.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsFolded ? L("收起") : foldedSummary)
            }
        }
    }

    private var foldedSummary: String {
        LFormat(
            "另有 %d 项正常：%@",
            section.folded.count,
            section.folded.map(\.provider.displayName)
                .joined(separator: TokenStepLocalization.language == .en ? ", " : "、")
        )
    }

    /// Names the window that runs out early, so a warning next to a window
    /// about to reset is not read as being about that one.
    private func runsOutEarlyBadge(_ provider: CompactPopoverModel.QuotaProviderRow) -> String {
        let titles = provider.windows.filter(\.runsOutEarly).map(\.title)
        guard !titles.isEmpty else { return L("照此速度会提前用完") }
        let separator = TokenStepLocalization.language == .en ? ", " : "、"
        return LFormat("%@额度会提前用完", titles.joined(separator: separator))
    }

    /// Explains the bar's tick: how much of the window's time has passed.
    private func paceHelp(_ window: CompactPopoverModel.QuotaWindowRow) -> String {
        guard let elapsed = window.elapsedFraction else {
            return LFormat("已用 %@", CompactPopoverStyle.percent(window.usedPercent))
        }
        let text = LFormat(
            "竖线是时间进度：已过 %@，已用 %@",
            CompactPopoverStyle.percent(elapsed * 100),
            CompactPopoverStyle.percent(window.usedPercent)
        )
        return window.runsOutEarly ? text + L("。用得比时间快，照此速度会在重置前用完") : text
    }

    private func providerBlock(_ provider: CompactPopoverModel.QuotaProviderRow) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                QuotaProviderIcon(provider: provider.provider)
                Text(provider.provider.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.tokenInk)
                Spacer(minLength: 4)
                if provider.runsOutEarly {
                    Text(runsOutEarlyBadge(provider))
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(CompactPopoverStyle.color(for: .warning))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(CompactPopoverStyle.color(for: .warning).opacity(0.14), in: Capsule())
                }
            }
            ForEach(provider.windows) { window in
                HStack(spacing: 8) {
                    Text(window.title)
                        .font(.system(size: 11, weight: window.runsOutEarly ? .semibold : .regular))
                        .foregroundStyle(window.runsOutEarly ? CompactPopoverStyle.color(for: .warning) : Color.secondary)
                        .frame(width: 58, alignment: .leading)
                        .lineLimit(1)
                    CompactBar(
                        fraction: window.usedPercent / 100,
                        color: CompactPopoverStyle.color(for: window.level),
                        marker: window.elapsedFraction
                    )
                    Text(CompactPopoverStyle.percent(window.usedPercent))
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(CompactPopoverStyle.textColor(for: window.level))
                        .frame(width: 38, alignment: .trailing)
                    Text(CompactPopoverStyle.resetText(window.resetsAt) ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 72, alignment: .trailing)
                }
                .contentShape(Rectangle())
                .help(paceHelp(window))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Token section

struct CompactTokenSection: View {
    var usage: DailyUsage
    var lap: TokenStepLapProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color.tokenTrack, lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: lap.currentLapProgress)
                        .stroke(lap.ringColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("今日 Token"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(TokenStepFormat.tokens(usage.totalTokens, compact: true))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.tokenInk)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(lap.lapStatusText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.tokenGreenDark)
                    Text(lap.perLapGoalText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(CompactPopoverModel.topModels(usage)) { model in
                HStack(spacing: 10) {
                    Text(model.name)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.tokenInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 112, alignment: .leading)
                    CompactBar(fraction: model.share, color: Color.tokenGreen.opacity(0.85), height: 5)
                    Text(TokenStepFormat.tokens(model.tokens, compact: true))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.tokenInk)
                        .frame(width: 56, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Rank section

struct CompactRankSection: View {
    var section: CompactPopoverModel.RankSection
    var fetchedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CompactSectionHeader(title: L("今日排名"), trailing: LFormat("榜单 %@", CompactPopoverStyle.relative(fetchedAt)))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let rank = section.myRank {
                    Text("#\(rank)")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.tokenInk)
                } else {
                    Text(L("未上榜"))
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.tokenInk)
                }
                Text(rankCaption)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let board = section.myBoardTokens {
                    Text(LFormat("榜上 %@", TokenStepFormat.tokens(board, compact: true)))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(section.podium) { entry in
                HStack(spacing: 8) {
                    Text("\(entry.rank)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.78))
                        .frame(width: 20, height: 20)
                        .background(medal(entry.rank), in: Circle())
                    Text(entry.isMe ? LFormat("%@（你）", entry.name) : entry.name)
                        .font(.system(size: 12, weight: entry.isMe ? .bold : .regular))
                        .foregroundStyle(Color.tokenInk)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(TokenStepFormat.tokens(entry.tokens, compact: true))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.tokenInk)
                    Text(entry.leadOverMe.map { LFormat("差 %@", TokenStepFormat.tokens($0, compact: true)) } ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
            if let chase = section.chase {
                chaseCard(chase)
            }
        }
    }

    private var rankCaption: String {
        if section.myRank == nil {
            // A full board may hide ranks past the limit; a short one lists
            // everyone, so being absent means nothing uploaded today.
            return section.chase != nil
                ? LFormat("未进入前 %d 名", section.listedLimit)
                : L("今日还没有你的上传")
        }
        return LFormat("/ %d 人", section.rankedUsers)
    }

    private func medal(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 242 / 255, green: 209 / 255, blue: 107 / 255)
        case 2: return Color(red: 213 / 255, green: 219 / 255, blue: 225 / 255)
        default: return Color(red: 230 / 255, green: 185 / 255, blue: 143 / 255)
        }
    }

    @ViewBuilder
    private func chaseCard(_ chase: CompactPopoverModel.Chase) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch chase {
            case let .next(rank, name, gap, progress):
                chaseHeadline(gap: gap, target: LFormat("超过 #%d %@", rank, name))
                CompactBar(fraction: progress, color: Color.tokenGreen, height: 5)
                paceLine
            case let .enterBoard(rank, tokens, gap):
                if let gap {
                    chaseHeadline(gap: gap, target: LFormat("进入前 %d 名", rank))
                    paceLine
                } else {
                    Text(LFormat("第 %d 名今日 %@", rank, TokenStepFormat.tokens(tokens, compact: true)))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.tokenGreenDark)
                }
            case let .leading(lead):
                Text(L("你是今日第一"))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.tokenGreenDark)
                Text(LFormat("领先第二名 %@", TokenStepFormat.tokens(lead, compact: true)))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.tokenGreenDark.opacity(0.85))
            }
            if let unsynced = section.unsyncedTokens {
                Text(section.projectedRank.map {
                    LFormat("本地比榜单多 %@，同步后预计升到 #%d", TokenStepFormat.tokens(unsynced, compact: true), $0)
                } ?? LFormat("本地比榜单多 %@，等待同步", TokenStepFormat.tokens(unsynced, compact: true)))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.tokenGreenDark.opacity(0.85))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tokenGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.tokenGreen.opacity(0.28))
        }
    }

    private func chaseHeadline(gap: Int, target: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(L("再跑"))
                .font(.system(size: 12, weight: .medium))
            Text(TokenStepFormat.tokens(gap, compact: true))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(target)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(Color.tokenGreenDark)
    }

    @ViewBuilder
    private var paceLine: some View {
        if let eta = section.etaMinutes {
            Text(LFormat(
                "按最近 1 小时的速度（约 %@/时），约 %@",
                TokenStepFormat.tokens(section.tokensPerHour, compact: true),
                CompactPopoverStyle.minutes(eta)
            ))
            .font(.system(size: 11))
            .foregroundStyle(Color.tokenGreenDark.opacity(0.85))
        } else {
            Text(L("最近 1 小时没有用量"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
