import SwiftUI

enum AgentSourceTier: String, Codable {
    case ledger = "l1"
    case quota = "l2"
    case signal = "l3"
}

struct AgentSourceColorToken: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

struct AgentSourceDescriptor: Identifiable, Equatable {
    var id: String
    var displayName: String
    var tier: AgentSourceTier
    var colorToken: AgentSourceColorToken
    var isExperimental: Bool
    var probePaths: [String]
    var aliases: [String]
    var rankClientKeys: [String]

    var color: Color { colorToken.color }

    var allNames: [String] {
        [id, displayName] + aliases
    }
}

enum AgentSourceRegistry {
    static let all: [AgentSourceDescriptor] = [
        AgentSourceDescriptor(
            id: "codex",
            displayName: "Codex",
            tier: .ledger,
            colorToken: AgentSourceColorToken(red: 0.18, green: 0.62, blue: 0.38),
            isExperimental: false,
            probePaths: ["~/.codex"],
            aliases: ["Codex via CC Switch"],
            rankClientKeys: ["codex"]
        ),
        AgentSourceDescriptor(
            id: "claude",
            displayName: "Claude Code",
            tier: .ledger,
            colorToken: AgentSourceColorToken(red: 0.88, green: 0.42, blue: 0.24),
            isExperimental: false,
            probePaths: ["~/.claude"],
            aliases: ["Claude Code via CC Switch", "Claude"],
            rankClientKeys: ["claude"]
        ),
        AgentSourceDescriptor(
            id: "cc-switch",
            displayName: "CC Switch Proxy",
            tier: .ledger,
            colorToken: AgentSourceColorToken(red: 0.10, green: 0.64, blue: 0.72),
            isExperimental: false,
            probePaths: ["~/.cc-switch/cc-switch.db"],
            aliases: ["Codex via CC Switch", "Claude Code via CC Switch", "Gemini via CC Switch"],
            rankClientKeys: []
        ),
        AgentSourceDescriptor(
            id: "zcode",
            displayName: "ZCode",
            tier: .ledger,
            colorToken: AgentSourceColorToken(red: 0.20, green: 0.52, blue: 0.92),
            isExperimental: true,
            probePaths: ["~/.zcode"],
            aliases: [],
            rankClientKeys: ["zcode"]
        ),
        AgentSourceDescriptor(
            id: "hermes",
            displayName: "Hermes Agent",
            tier: .ledger,
            colorToken: AgentSourceColorToken(red: 0.50, green: 0.28, blue: 0.92),
            isExperimental: true,
            probePaths: ["~/.hermes"],
            aliases: ["Hermes"],
            rankClientKeys: ["hermes"]
        ),
        AgentSourceDescriptor(
            id: "workbuddy",
            displayName: "WorkBuddy",
            tier: .ledger,
            colorToken: AgentSourceColorToken(red: 0.94, green: 0.63, blue: 0.16),
            isExperimental: true,
            probePaths: ["~/.workbuddy"],
            aliases: [],
            rankClientKeys: ["workbuddy"]
        ),
        AgentSourceDescriptor(
            id: "deepseek-harness",
            displayName: "DeepSeek Harness",
            tier: .ledger,
            colorToken: AgentSourceColorToken(red: 0.82, green: 0.32, blue: 0.58),
            isExperimental: true,
            probePaths: [
                "~/.dsh",
                "~/Library/Application Support/@deepseek-ai/dsh-desktop/harness"
            ],
            aliases: [],
            rankClientKeys: ["deepseek-harness"]
        ),
        AgentSourceDescriptor(
            id: "autoclaw",
            displayName: "AutoClaw",
            tier: .ledger,
            colorToken: AgentSourceColorToken(red: 0.85, green: 0.33, blue: 0.44),
            isExperimental: false,
            probePaths: ["~/.openclaw-autoclaw"],
            aliases: ["OpenClaw"],
            rankClientKeys: ["autoclaw"]
        ),
        AgentSourceDescriptor(
            id: "cursor",
            displayName: "Cursor",
            tier: .quota,
            colorToken: AgentSourceColorToken(red: 0.15, green: 0.15, blue: 0.16),
            isExperimental: false,
            probePaths: [
                "~/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
            ],
            aliases: [],
            rankClientKeys: ["cursor"]
        ),
        AgentSourceDescriptor(
            id: "glm",
            displayName: "GLM",
            tier: .quota,
            colorToken: AgentSourceColorToken(red: 0.16, green: 0.45, blue: 0.86),
            isExperimental: false,
            probePaths: [],
            aliases: ["Zhipu", "智谱"],
            rankClientKeys: ["glm"]
        ),
        AgentSourceDescriptor(
            id: "kimi",
            displayName: "Kimi",
            tier: .quota,
            colorToken: AgentSourceColorToken(red: 0.22, green: 0.55, blue: 0.48),
            isExperimental: false,
            probePaths: ["~/.kimi"],
            aliases: [],
            rankClientKeys: ["kimi"]
        ),
        AgentSourceDescriptor(
            id: "grok",
            displayName: "Grok",
            tier: .quota,
            colorToken: AgentSourceColorToken(red: 0.72, green: 0.28, blue: 0.22),
            isExperimental: false,
            probePaths: ["~/.grok/auth.json"],
            aliases: [],
            rankClientKeys: ["grok"]
        ),
        AgentSourceDescriptor(
            id: "cursor-code",
            displayName: "Cursor 代码产出",
            tier: .signal,
            colorToken: AgentSourceColorToken(red: 0.15, green: 0.15, blue: 0.16),
            isExperimental: false,
            probePaths: ["~/.cursor/ai-tracking/ai-code-tracking.db"],
            aliases: [],
            rankClientKeys: []
        )
    ]

    static var ledgerSources: [AgentSourceDescriptor] {
        all.filter { $0.tier == .ledger }
    }

    static var quotaSources: [AgentSourceDescriptor] {
        all.filter { $0.tier == .quota }
    }

    static var signalSources: [AgentSourceDescriptor] {
        all.filter { $0.tier == .signal }
    }

    static var preferredToolOrder: [String] {
        [
            "Codex",
            "Claude Code",
            "Cursor",
            "ZCode",
            "Hermes",
            "Hermes Agent",
            "WorkBuddy",
            "DeepSeek Harness",
            "AutoClaw",
            "Codex via CC Switch",
            "Claude Code via CC Switch"
        ]
    }

    static var defaultLegendNames: [String] {
        ["Codex", "Claude Code"]
    }

    static func descriptor(for name: String) -> AgentSourceDescriptor? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        if let exact = all.first(where: { $0.id == key || $0.displayName == key }) {
            return exact
        }
        let lowered = key.lowercased()
        if let alias = all.first(where: { descriptor in
            descriptor.allNames.contains { $0.caseInsensitiveCompare(key) == .orderedSame }
                || descriptor.rankClientKeys.contains(lowered)
        }) {
            return alias
        }
        return all.first { descriptor in
            descriptor.allNames.contains { lowered.contains($0.lowercased()) }
        }
    }

    static func color(for name: String) -> Color {
        descriptor(for: name)?.color ?? Color.tokenInk.opacity(0.44)
    }

    static func displayName(for clientKey: String) -> String {
        if let descriptor = descriptor(for: clientKey) {
            return descriptor.displayName
        }
        return clientKey
    }

    static func matches(_ source: String, family: String) -> Bool {
        let normalized = source.lowercased()
        switch family {
        case "codex":
            return normalized == "codex" || normalized.hasPrefix("codex via")
        case "hermes":
            return normalized.contains("hermes")
        default:
            return descriptor(for: source)?.id == family
        }
    }
}
