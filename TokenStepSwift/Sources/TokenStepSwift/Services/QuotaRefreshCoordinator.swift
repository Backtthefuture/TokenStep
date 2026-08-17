import Foundation

enum QuotaRefreshCoordinator {
    static func fetch(providers: Set<QuotaProviderID>) -> [QuotaProviderID: ProviderQuota] {
        var result: [QuotaProviderID: ProviderQuota] = [:]
        let lock = NSLock()
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let quota = read(provider)
                lock.lock()
                result[provider] = quota
                lock.unlock()
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + 12)
        return result
    }

    static func read(_ provider: QuotaProviderID) -> ProviderQuota {
        do {
            switch provider {
            case .codex:
                return try CodexQuotaService.read().asProviderQuota(.codex)
            case .claude:
                return try ClaudeQuotaService.read().asProviderQuota(.claude)
            case .cursor:
                return try CursorQuotaService.read()
            case .glm:
                return try GLMQuotaService.read()
            case .kimi:
                return try KimiQuotaService.read()
            case .grok:
                return try GrokQuotaService.read()
            }
        } catch {
            return ProviderQuota.unavailable(
                provider,
                status: status(for: provider, error: error),
                message: error.localizedDescription
            )
        }
    }

    private static func status(for provider: QuotaProviderID, error: Error) -> QuotaStatus {
        let text = error.localizedDescription
        if text.contains("未登录") {
            return .notLoggedIn
        }
        if text.contains("非订阅") || text.contains("按量") {
            return .wrongKeyType
        }
        if text.contains("grok login") || text.contains("需要") && provider == .grok {
            return .needsLogin
        }
        return .unavailable
    }
}
