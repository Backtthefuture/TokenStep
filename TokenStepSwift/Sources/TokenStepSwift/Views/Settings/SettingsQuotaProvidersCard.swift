import SwiftUI

struct SettingsQuotaProvidersPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            SettingsSectionCard(
                title: L("订阅额度提供商"),
                subtitle: L("浏览器登录自动取令牌 · 手动粘贴仍可用 · 密钥只进钥匙串")
            ) {
                VStack(spacing: 0) {
                    ForEach(QuotaProviderID.allCases) { provider in
                        SettingsQuotaProviderBlock(provider: provider)
                    }
                }
                Text(L("读取失败时显示「暂不可用」并保留上次值，绝不显示 0%。"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }

            VStack(spacing: 16) {
                SettingsSectionCard(
                    title: L("预警"),
                    subtitle: L("额度紧张时的提示强度")
                ) {
                    VStack(spacing: 0) {
                        SettingsSourceRow(
                            title: L("菜单栏预警点"),
                            detail: L("任一额度剩余低于阈值时，图标加红点"),
                            badge: L("始终启用"),
                            badgeStyle: .ok
                        )
                        SettingsSourceRow(
                            title: L("阈值"),
                            detail: L("剩余百分比"),
                            badge: "20%",
                            badgeStyle: .ok
                        )
                        SettingsSourceRow(
                            title: L("告急卡置顶"),
                            detail: L("浮窗额度栏把最紧张的排最前"),
                            badge: L("始终启用"),
                            badgeStyle: .ok
                        )
                    }
                }

            }
        }
    }
}

struct SettingsQuotaProviderBlock: View {
    @EnvironmentObject private var appState: AppState
    var provider: QuotaProviderID
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSourceRow(
                title: provider.displayName,
                detail: provider.credentialHint,
                badge: detail,
                badgeStyle: badgeStyle,
                showsToggle: true,
                isOn: Binding(
                    get: { appState.settings.enabledQuotaProviders.contains(provider) },
                    set: { appState.setQuotaProvider(provider, enabled: $0) }
                ),
                actionTitle: appState.settings.enabledQuotaProviders.contains(provider) ? L("重新检测") : nil,
                action: appState.settings.enabledQuotaProviders.contains(provider)
                    ? { appState.refreshCodexQuota(force: true) }
                    : nil
            )

            if provider == .grok {
                grokEditor
            } else if provider.needsManualCredential {
                credentialEditor
            }
        }
    }

    private var grokEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                GrokQuotaService.hasLocalSession()
                    ? L("已读取本机 grok login，不需要往这里粘贴任何代码")
                    : L("Grok Build 弹出的短码是给终端用的。贴回正在跑 grok login 的窗口，等它显示成功，再点重新检测。")
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                compactButton(L("打开终端登录")) {
                    appState.openGrokLoginInTerminal()
                }
                compactButton(L("打开 ~/.grok")) {
                    appState.revealQuotaCredentialFolder(.grok)
                }
                if appState.hasQuotaSecret(provider) {
                    compactButton(L("清除密钥")) {
                        appState.clearQuotaSecret(provider)
                    }
                }
            }

            Text(L("清除密钥只在你往钥匙串里存过内容时才出现。Grok 正常走 ~/.grok/auth.json，一般看不到这个按钮。"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.tokenTrack.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.bottom, 8)
    }

    private var credentialEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if provider == .trae || provider == .traeCN {
                browserSignInRow
            }

            if appState.hasQuotaSecret(provider) {
                Text(L("已保存在钥匙串，重新输入可覆盖"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                SecureField("", text: $draft, prompt: Text(placeholder))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                compactButton(L("保存并检测"), disabled: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    appState.saveQuotaSecret(provider, value: draft)
                    draft = ""
                }
                if appState.hasQuotaSecret(provider) {
                    compactButton(L("清除密钥")) {
                        appState.clearQuotaSecret(provider)
                    }
                }
            }

            HStack(spacing: 8) {
                if provider == .kimi {
                    compactButton(L("打开 ~/.kimi")) {
                        appState.revealQuotaCredentialFolder(.kimi)
                    }
                }
            }

            if provider == .trae || provider == .traeCN {
                tokenGuide
            }

            Text(L("密钥只保存在钥匙串，不会写入 settings.json"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.tokenTrack.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.bottom, 8)
    }

    /// 一键浏览器授权：打开官网登录页，回调拿令牌并写入钥匙串。
    private var browserSignInRow: some View {
        HStack(spacing: 8) {
            let isSigningIn = appState.signingInQuotaProvider == provider
            compactButton(
                isSigningIn ? L("等待浏览器授权…") : L("用浏览器登录"),
                disabled: appState.signingInQuotaProvider != nil
            ) {
                appState.startBrowserSignIn(provider)
            }
            Text(
                isSigningIn
                    ? L("请在浏览器完成登录，成功后自动显示额度")
                    : L("推荐：点一下登录，令牌自动写入钥匙串")
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Trae / Trae CN 的「如何获取令牌」引导。客户端把登录态加密保存在本机
    /// （实测 database.db 与 storage.json 均非明文），TokenStep 无法直接读取，
    /// 所以首选浏览器授权；手动粘贴作为兜底。浏览器内具体面板名称未逐一验证，
    /// 文案用通用表述。
    private var tokenGuide: some View {
        let site = provider == .traeCN ? "trae.cn" : "trae.ai"
        let host = provider == .traeCN ? "api.trae.cn" : "*.trae.ai"
        return VStack(alignment: .leading, spacing: 4) {
            Text(L("自动获取（推荐）：点上方「用浏览器登录」，授权页会回跳本机并自动保存令牌。"))
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.secondary)
            Text(L("手动粘贴（兜底）："))
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.secondary)
            Text(L("1. 用浏览器登录 \(site)（与客户端同一账号）"))
            Text(L("2. 打开开发者工具的 Network（网络）面板"))
            Text(L("3. 找一条发往 \(host) 的请求，复制请求头 Authorization 中 Bearer 之后的令牌"))
            Text(L("4. 粘贴到上方输入框，点「保存并检测」"))
            Text(L("令牌过期后会自动尝试刷新；刷新也失效时重新登录即可。浏览器面板的具体名称以你的浏览器为准（待确认）。"))
                .foregroundStyle(.tertiary)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func compactButton(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.heavy))
                .padding(.horizontal, 8)
                .frame(height: 26)
        }
        .buttonStyle(SettingsSecondaryButtonStyle())
        .disabled(disabled)
    }

    private var placeholder: String {
        switch provider {
        case .glm: return L("粘贴 Coding Plan API Key")
        case .kimi: return L("粘贴 Kimi access_token")
        case .grok: return L("一般不用填，短码不要贴到这里")
        case .trae: return L("粘贴 Trae 访问令牌（Bearer token）")
        case .traeCN: return L("粘贴 Trae CN 访问令牌（Bearer token）")
        default: return ""
        }
    }

    private var detail: String {
        guard appState.settings.enabledQuotaProviders.contains(provider) else {
            return L("已关闭")
        }
        if let quota = appState.quotas[provider] {
            if quota.isAvailable, let fetchedAt = quota.fetchedAt {
                return relativeTime(fetchedAt)
            }
            if let message = quota.message, !message.isEmpty {
                return message
            }
            return SourceStatusCopy.text(quota.status.rawValue)
        }
        return L("等待刷新")
    }

    private var badgeStyle: SettingsBadgeStyle {
        guard appState.settings.enabledQuotaProviders.contains(provider) else {
            return .off
        }
        if let quota = appState.quotas[provider] {
            if quota.isAvailable { return .ok }
            if quota.status == .unavailable { return .warn }
        }
        return .off
    }

    private func relativeTime(_ date: Date) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes < 1 { return L("刚刚成功") }
        if minutes < 60 { return LFormat("%d 分钟前成功", minutes) }
        return LFormat("%d 小时前成功", minutes / 60)
    }
}

struct SettingsQuotaProvidersCard: View {
    var body: some View {
        SettingsQuotaProvidersPane()
    }
}
