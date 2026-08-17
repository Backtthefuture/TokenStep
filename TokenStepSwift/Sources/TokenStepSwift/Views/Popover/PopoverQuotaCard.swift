import SwiftUI

struct PopoverQuotaCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(L("订阅额度"))
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.tokenInk)
                Spacer()
                if appState.isRefreshingCodexQuota {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                } else if let fetchedAt = latestFetchedAt {
                    Text(quotaFetchedText(fetchedAt))
                        .font(.caption2.weight(.bold))
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
                VStack(spacing: 8) {
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
        VStack(alignment: .leading, spacing: 6) {
            Text(quota.provider.displayName)
                .font(.caption2.weight(.heavy))
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
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tokenSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.black.opacity(0.05)))
    }

    private func quotaRow(_ window: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.kind.shortTitle)
                    .font(.system(size: 10.5, weight: .heavy))
                    .foregroundStyle(Color.tokenInk.opacity(0.62))
                Spacer()
                Text(LFormat("剩余 %@", TokenStepFormat.percent(window.remainingPercent)))
                    .font(.system(size: 10.5, weight: .heavy))
                    .foregroundStyle(window.isLow ? Color.orange : Color.tokenInk.opacity(0.82))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.tokenGreen.opacity(0.10))
                    Capsule()
                        .fill(window.isLow ? Color.orange : Color.tokenGreen)
                        .frame(width: max(5, proxy.size.width * window.remainingPercent / 100))
                }
            }
            .frame(height: 5)
        }
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
