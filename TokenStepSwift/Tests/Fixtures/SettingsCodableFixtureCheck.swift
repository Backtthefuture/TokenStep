import Darwin
import Foundation

// `TokenStepSettings` has a hand-written Codable implementation because it carries
// migrations from older settings files. Adding a field means updating the
// property list, CodingKeys, defaults, init, init(from:) and encode(to:); a missed
// step still compiles but silently drops the setting. These checks catch that.
@main
struct SettingsCodableFixtureCheck {
    /// Every stored property differs from `TokenStepSettings.defaults`. When a new
    /// setting is added, set it to a non-default value here.
    static let sample = TokenStepSettings(
        dailyGoalTokens: 250_000_000,
        refreshIntervalSeconds: 900,
        historyDays: 90,
        theme: .eventHorizon,
        autoUpdateEnabled: false,
        askBeforeDownloadingUpdates: false,
        requireVerifiedUpdates: false,
        tokenIslandEnabled: true,
        tokenIslandPlacement: .notchLeft,
        enabledQuotaProviders: [.codex, .glm, .cursor],
        cursorQuotaEnabled: true,
        cursorCodeSignalEnabled: true,
        agentWorkRankVisibility: .hidden,
        showExperimentalAgentSources: true,
        language: .en,
        skippedUpdateVersion: "9.9.9",
        classicTheme: .ocean,
        odysseyChapter: .trojanInferno
    )

    static func main() {
        do {
            try checkSampleCoversEveryProperty()
            try checkEveryPropertyIsEncoded()
            try checkRoundTripKeepsEveryProperty()
            try checkMissingKeysFallBackToDefaults()
            print("Settings Codable fixture checks passed")
        } catch {
            fputs("Settings Codable fixture failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func checkSampleCoversEveryProperty() throws {
        let defaults = properties(TokenStepSettings.defaults)
        let values = properties(sample)
        let unchanged = defaults.keys.filter { defaults[$0] == values[$0] }.sorted()
        try expect(
            unchanged.isEmpty,
            "sample keeps the default for \(unchanged); give each new setting a non-default sample value"
        )
    }

    private static func checkEveryPropertyIsEncoded() throws {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sample)) as? [String: Any] ?? [:]
        let encodedKeys = Set(object.keys)
        let missing = properties(sample).keys
            .filter { !encodedKeys.contains(snakeCase($0)) }
            .sorted()
        try expect(missing.isEmpty, "not written by encode(to:): \(missing)")
    }

    private static func checkRoundTripKeepsEveryProperty() throws {
        let decoded = try JSONDecoder().decode(TokenStepSettings.self, from: JSONEncoder().encode(sample))
        let before = properties(sample)
        let after = properties(decoded)
        let lost = before.keys.filter { before[$0] != after[$0] }.sorted()
        try expect(lost.isEmpty, "changed by encode then decode: \(lost.map { "\($0): \(before[$0]!) -> \(after[$0]!)" })")
    }

    private static func checkMissingKeysFallBackToDefaults() throws {
        let decoded = try JSONDecoder().decode(TokenStepSettings.self, from: Data("{}".utf8))
        let defaults = properties(TokenStepSettings.defaults)
        let values = properties(decoded)
        let differing = defaults.keys.filter { defaults[$0] != values[$0] }.sorted()
        try expect(differing.isEmpty, "an empty settings file does not decode to defaults: \(differing)")
    }

    /// Stored properties by name, compared through a stable description.
    private static func properties(_ settings: TokenStepSettings) -> [String: String] {
        var result: [String: String] = [:]
        for child in Mirror(reflecting: settings).children {
            guard let label = child.label else { continue }
            if let set = child.value as? Set<QuotaProviderID> {
                result[label] = set.map(\.rawValue).sorted().description
            } else {
                result[label] = String(describing: child.value)
            }
        }
        return result
    }

    private static func snakeCase(_ name: String) -> String {
        name.reduce(into: "") { result, character in
            if character.isUppercase {
                result += "_" + character.lowercased()
            } else {
                result.append(character)
            }
        }
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw FixtureError(message) }
    }
}

private struct FixtureError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
