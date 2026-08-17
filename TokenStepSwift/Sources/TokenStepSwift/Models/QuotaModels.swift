import Foundation

enum QuotaProviderID: String, Codable, CaseIterable, Identifiable, Hashable {
    case codex
    case claude
    case cursor
    case glm
    case kimi
    case grok

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .cursor: return "Cursor"
        case .glm: return "GLM"
        case .kimi: return "Kimi"
        case .grok: return "Grok"
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
        case .cursorModels: return L("Cursor 模型")
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
        case .cursorModels: return L("自有")
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

struct QuotaWindow: Equatable, Identifiable, Codable {
    var kind: QuotaWindowKind
    var usedPercent: Double
    var remaining: Double?
    var total: Double?
    var resetsAt: Date?

    var id: String { kind.rawValue }

    var remainingPercent: Double {
        if let remaining, let total, total > 0 {
            return min(max(remaining / total * 100, 0), 100)
        }
        return min(max(100 - usedPercent, 0), 100)
    }

    var title: String { kind.title }

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
