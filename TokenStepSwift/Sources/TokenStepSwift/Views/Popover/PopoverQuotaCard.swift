import SwiftUI

struct PopoverQuotaCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let voyage = TokenStepThemeRuntime.isCinematic
        return VStack(alignment: .leading, spacing: voyage ? 12 : 10) {
            HStack(spacing: 8) {
                Text(L("订阅额度"))
                    .font((voyage ? Font.callout : Font.caption).weight(.heavy))
                    .foregroundStyle(Color.tokenInk)
                Spacer()
                if appState.isRefreshingCodexQuota {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                } else if let fetchedAt = latestFetchedAt {
                    Text(quotaFetchedText(fetchedAt))
                        .font((voyage ? Font.caption : Font.caption2).weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            if visible.isEmpty {
                Text(L("暂未读取到额度"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if usesGrid {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(visible) { quota in
                        quotaChip(quota)
                    }
                }
            } else {
                VStack(spacing: voyage ? 6 : 8) {
                    ForEach(visible) { quota in
                        quotaChip(quota)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var visible: [ProviderQuota] {
        appState.visibleQuotas.filter(\.isAvailable)
    }

    private var usesGrid: Bool {
        visible.count >= 4
    }

    private var latestFetchedAt: Date? {
        visible.compactMap(\.fetchedAt).max()
    }

    private func quotaChip(_ quota: ProviderQuota) -> some View {
        let voyage = TokenStepThemeRuntime.isCinematic
        return VStack(alignment: .leading, spacing: voyage ? 4 : 6) {
            Text(quota.provider.displayName)
                .font((voyage ? Font.system(size: 11.5) : Font.caption2).weight(.heavy))
                .foregroundStyle(Color.tokenInk.opacity(0.76))
            if quota.isAvailable {
                ForEach(quota.windows.prefix(2)) { window in
                    quotaRow(window)
                }
            } else {
                Text(statusText(quota))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(voyage ? 6 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tokenSurface.opacity(voyage ? 0.84 : 1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.tokenHairline))
    }

    private func quotaRow(_ window: QuotaWindow) -> some View {
        let voyage = TokenStepThemeRuntime.isCinematic
        return VStack(alignment: .leading, spacing: voyage ? 3 : 4) {
            HStack {
                Text(window.kind.shortTitle)
                    .font(.system(size: voyage ? 10.5 : 10.5, weight: .heavy))
                    .foregroundStyle(Color.tokenInk.opacity(0.62))
                Spacer()
                Text(LFormat("剩余 %@", TokenStepFormat.percent(window.remainingPercent)))
                    .font(.system(size: voyage ? 10.5 : 10.5, weight: .heavy))
                    .foregroundStyle(window.isLow ? Color.tokenWarning : Color.tokenInk.opacity(0.82))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.tokenTrack.opacity(0.82))
                    Capsule()
                        .fill(window.isLow ? Color.tokenWarning : Color.tokenGreen)
                        .frame(width: max(5, proxy.size.width * window.remainingPercent / 100))
                }
            }
            .frame(height: voyage ? 4 : 5)
            if let resetsAt = window.resetsAt {
                Text(LFormat("重置于 %@", Self.resetTimeText(resetsAt)))
                    .font(.system(size: voyage ? 9.5 : 9.5, weight: .semibold))
                    .foregroundStyle(Color.tokenInk.opacity(0.55))
                }
        }
    }

    private static func resetTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }

    private func statusText(_ quota: ProviderQuota) -> String {
        switch quota.status {
        case .notLoggedIn:
            return quota.provider == .cursor ? L("未登录 Cursor") : L("未登录")
        case .wrongKeyType:
            return L("当前 key 非订阅计划")
        case .needsLogin:
            return L("需要 grok login")
        case .unavailable, .available:
            return quota.message ?? L("暂不可用")
        }
    }

    private func quotaFetchedText(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date).rounded()))
        if seconds < 60 { return L("刚刚") }
        return LFormat("%d 分钟前", max(1, seconds / 60))
    }
}
