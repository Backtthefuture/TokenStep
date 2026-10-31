import Foundation

enum QuotaProviderID: String, Codable, CaseIterable, Identifiable, Hashable {
    case codex
    case claude
    case cursor
    case glm
    case kimi
    case grok
    case trae
    case traeCN = "traecn"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .cursor: return "Cursor"
        case .glm: return "GLM"
        case .kimi: return "Kimi"
        case .grok: return "Grok"
        case .trae: return "Trae"
        case .traeCN: return "Trae CN"
        }
    }

    var credentialHint: String {
        switch self {
        case .codex: return L("读取本机 Codex 登录态")
        case .claude: return L("读取 Keychain 中的 Claude OAuth")
        case .cursor: return L("两档额度 + 官方用量事件计入圆环")
        case .glm: return L("填写 Coding Plan API Key，只进钥匙串")
        case .kimi: return L("粘贴 ~/.kimi 的 access_token，不要用开放平台 key")
        case .grok: return L("读取 ~/.grok/auth.json，短码不要贴到 TokenStep")
        case .trae: return L("浏览器登录自动取令牌，也可手动粘贴")
        case .traeCN: return L("浏览器登录自动取令牌，也可手动粘贴")
        }
    }
}

enum QuotaWindowKind: String, Codable, Equatable {
    case fiveHour
    case sevenDay
    case session
    case weekly
    case monthlyCredits
    case tokenWindow
    case spend
    case cursorModels
    case otherModels

    var title: String {
        switch self {
        case .fiveHour: return L("5 小时")
        case .sevenDay: return L("7 天")
        case .session: return L("会话")
        case .weekly: return L("本周")
        case .monthlyCredits: return L("本月额度")
        case .tokenWindow: return L("Token 窗")
        case .spend: return L("花费")
        case .cursorModels: return L("自带")
        case .otherModels: return L("其他模型")
        }
    }

    var shortTitle: String {
        switch self {
        case .fiveHour: return L("5小时")
        case .sevenDay: return L("7天")
        case .session: return L("会话")
        case .weekly: return L("本周")
        case .monthlyCredits: return L("本月")
        case .tokenWindow: return L("Token")
        case .spend: return L("花费")
        case .cursorModels: return L("自带")
        case .otherModels: return L("其他")
        }
    }
}

enum QuotaStatus: String, Codable, Equatable {
    case available
    case unavailable
    case notLoggedIn
    case wrongKeyType
    case needsLogin
}

/// How a window's `remaining` / `total` numbers are meant to be read.
/// Optional on `QuotaWindow` so cached readings written before this field
/// existed still decode; a missing unit keeps the historic percent reading.
enum QuotaUnit: String, Codable, Equatable {
    case percent
    case credits
    case usd
    case count
}

struct QuotaWindow: Equatable, Identifiable, Codable {
    var kind: QuotaWindowKind
    var usedPercent: Double
    var remaining: Double?
    var total: Double?
    var resetsAt: Date?
    var unit: QuotaUnit?

    var id: String { kind.rawValue }

    var resolvedUnit: QuotaUnit { unit ?? .percent }

    /// Whole credits used and granted; nil for every non-credits window.
    var creditAmounts: (used: Int, total: Int)? {
        guard resolvedUnit == .credits, let total, total > 0 else { return nil }
        let totalCredits = Int(total.rounded())
        let remainingCredits = Int(max(remaining ?? 0, 0).rounded())
        return (max(totalCredits - remainingCredits, 0), max(totalCredits, 1))
    }

    var remainingPercent: Double {
        if let remaining, let total, total > 0 {
            return min(max(remaining / total * 100, 0), 100)
        }
        return min(max(100 - usedPercent, 0), 100)
    }

    /// Trae CN reports credits rather than a share of a plan, so its row is
    /// labelled by unit instead of by the shared `.monthlyCredits` kind.
    var title: String {
        switch resolvedUnit {
        case .credits: return L("积分额度")
        case .usd: return kind == .spend ? kind.title : L("花费")
        case .percent, .count: return kind.title
        }
    }

    var isLow: Bool {
        remainingPercent < 20
    }
}

struct ProviderQuota: Equatable, Identifiable, Codable {
    var provider: QuotaProviderID
    var windows: [QuotaWindow]
    var status: QuotaStatus
    var fetchedAt: Date?
    var message: String?

    var id: String { provider.rawValue }

    var isAvailable: Bool {
        status == .available && !windows.isEmpty
    }

    var shouldDisplay: Bool {
        isAvailable
    }

    var lowestRemainingPercent: Double? {
        windows.map(\.remainingPercent).min()
    }

    var isLow: Bool {
        windows.contains(where: \.isLow)
    }

    static func unavailable(
        _ provider: QuotaProviderID,
        status: QuotaStatus = .unavailable,
        fetchedAt: Date? = nil,
        message: String? = nil
    ) -> ProviderQuota {
        ProviderQuota(
            provider: provider,
            windows: [],
            status: status,
            fetchedAt: fetchedAt,
            message: message
        )
    }

    var asCodexSnapshot: CodexQuotaSnapshot {
        CodexQuotaSnapshot(
            fetchedAt: fetchedAt,
            fiveHour: windows.first(where: { $0.kind == .fiveHour }).map {
                CodexQuotaWindow(kind: .fiveHour, usedPercent: $0.usedPercent, resetsAt: $0.resetsAt)
            },
            sevenDay: windows.first(where: { $0.kind == .sevenDay }).map {
                CodexQuotaWindow(kind: .sevenDay, usedPercent: $0.usedPercent, resetsAt: $0.resetsAt)
            }
        )
    }
}

extension CodexQuotaSnapshot {
    func asProviderQuota(_ provider: QuotaProviderID) -> ProviderQuota {
        var windows: [QuotaWindow] = []
        if let fiveHour {
            windows.append(
                QuotaWindow(
                    kind: .fiveHour,
                    usedPercent: fiveHour.usedPercent,
                    remaining: fiveHour.remainingPercent,
                    total: 100,
                    resetsAt: fiveHour.resetsAt
                )
            )
        }
        if let sevenDay {
            windows.append(
                QuotaWindow(
                    kind: .sevenDay,
                    usedPercent: sevenDay.usedPercent,
                    remaining: sevenDay.remainingPercent,
                    total: 100,
                    resetsAt: sevenDay.resetsAt
                )
            )
        }
        return ProviderQuota(
            provider: provider,
            windows: windows,
            status: isAvailable ? .available : .unavailable,
            fetchedAt: fetchedAt,
            message: isAvailable ? nil : L("暂不可用")
        )
    }
}

/// Assembly and copy rules for the main-window quota card. Kept out of the
/// view so the enabled/unavailable behaviour is covered by unit tests.
enum QuotaPresentation {
    /// Every enabled provider, including ones without a reading yet: the card
    /// explains why a provider is missing instead of silently dropping it.
    static func displayQuotas(
        enabled: Set<QuotaProviderID>,
        quotas: [QuotaProviderID: ProviderQuota]
    ) -> [ProviderQuota] {
        QuotaProviderID.allCases.compactMap { id in
            guard enabled.contains(id) else { return nil }
            return quotas[id] ?? ProviderQuota.unavailable(id)
        }
    }

    static func unavailableReason(_ quota: ProviderQuota, isRefreshing: Bool) -> String {
        guard !quota.isAvailable else { return "" }
        if let message = quota.message, !message.isEmpty {
            return message
        }
        switch quota.status {
        case .notLoggedIn:
            return L("未登录，请在设置里授权")
        case .wrongKeyType:
            return L("凭证类型不对，请在设置里更新")
        case .needsLogin:
            return L("登录已过期，请在设置里重新授权")
        case .available, .unavailable:
            return isRefreshing ? L("正在读取额度…") : L("尚未读取到额度，稍后会自动重试")
        }
    }
}

struct CursorCodeModelCount: Equatable {
    var name: String
    var blocks: Int
}

struct CursorCodeSignal: Equatable {
    var fetchedAt: Date
    var blockCount: Int
    var modelCount: Int
    var conversationCount: Int
    var requestCount: Int
    var fileCount: Int
    var models: [CursorCodeModelCount]
    var status: String

    var isEmpty: Bool {
        blockCount <= 0
    }

    static func empty(status: String = "empty") -> CursorCodeSignal {
        CursorCodeSignal(
            fetchedAt: Date(),
            blockCount: 0,
            modelCount: 0,
            conversationCount: 0,
            requestCount: 0,
            fileCount: 0,
            models: [],
            status: status
        )
    }
}
