import Darwin
import Foundation

@main
struct EnergyEfficiencyBenchmark {
    static func main() {
        do {
            let arguments = CommandLine.arguments
            guard arguments.count >= 3 else {
                throw BenchmarkError.message("Usage: EnergyEfficiencyBenchmark <database> <cold|warm|validate|cache-compare|database-compare|compare|migration-compare>")
            }
            let database = URL(fileURLWithPath: arguments[1])
            let mode = arguments[2]
            let home = ProcessInfo.processInfo.environment["TOKENSTEP_BENCHMARK_HOME"]
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? FileManager.default.homeDirectoryForCurrentUser
            let codexStateBefore = UsageCollector.codexCollectionStateForTests(homeURL: home)

            let stateStarted = ContinuousClock.now
            let state = UsageCollector.collectionState(
                historyDays: 180,
                includeExperimentalAgentSources: true,
                homeURL: home
            )
            let stateElapsed = stateStarted.duration(to: .now)

            let collectStarted = ContinuousClock.now
            var migrationComparison: CodexAccountingComparisonDiagnostics?
            let snapshot: UsageSnapshot
            if mode == "migration-compare" {
                let comparison = try UsageCollector.compareLegacyMigrationCodexAccountingForTests(
                    homeURL: home,
                    databaseURL: database
                )
                migrationComparison = comparison
                snapshot = comparison.incrementalSnapshot
            } else {
                snapshot = UsageCollector.collectCodexUsageSnapshotForTests(
                    homeURL: home,
                    cacheURL: database,
                    forceFullValidation: mode == "validate"
                )
            }
            let collectElapsed = collectStarted.duration(to: .now)
            guard snapshot.sources["Codex"]?.status == "ok",
                  let stats = UsageCollector.codexIncrementalCacheStatsForTests(databaseURL: database)
            else {
                throw BenchmarkError.message("incremental collection failed")
            }

            print("mode=\(mode)")
            print("state_files=\(state.files.count)")
            print("state_ms=\(milliseconds(stateElapsed))")
            print("collect_ms=\(milliseconds(collectElapsed))")
            print("cache_generation=\(stats.generation)")
            print("cached_sessions=\(stats.sessions)")
            print("cached_records=\(stats.records)")
            print("last_logical_write_bytes=\(stats.lastLogicalWriteBytes)")

            if mode == "cache-compare" {
                let detailed = UsageCollector.collectCodexUsageSnapshotForTests(
                    homeURL: home,
                    cacheURL: database,
                    requiresDetailedRecords: true
                )
                let mismatches = try mismatchSections(snapshot, detailed)
                print("mismatch_sections=\(mismatches.joined(separator: ","))")
                guard mismatches.isEmpty else {
                    throw BenchmarkError.message("cached summary differs from cached detailed accounting")
                }
                print("cache_accounting_match=true")
            }

            if mode == "database-compare" {
                guard let referencePath = ProcessInfo.processInfo.environment[
                    "TOKENSTEP_BENCHMARK_REFERENCE_DATABASE"
                ] else {
                    throw BenchmarkError.message(
                        "TOKENSTEP_BENCHMARK_REFERENCE_DATABASE is required"
                    )
                }
                let reference = UsageCollector.collectCodexUsageSnapshotForTests(
                    homeURL: home,
                    cacheURL: URL(fileURLWithPath: referencePath)
                )
                let mismatches = try mismatchSections(snapshot, reference)
                print("mismatch_sections=\(mismatches.joined(separator: ","))")
                guard mismatches.isEmpty else {
                    throw BenchmarkError.message("incremental databases disagree")
                }
                print("database_accounting_match=true")
            }

            if mode == "compare" || mode == "migration-compare" {
                let referenceStarted = ContinuousClock.now
                let comparison = try migrationComparison
                    ?? UsageCollector.compareIncrementalCodexAccountingForTests(
                        homeURL: home,
                        databaseURL: database
                    )
                let referenceElapsed = referenceStarted.duration(to: .now)
                let codexStateAfterReference = UsageCollector.codexCollectionStateForTests(
                    homeURL: home
                )
                guard codexStateBefore == codexStateAfterReference else {
                    throw BenchmarkError.message("Codex session files changed during accounting comparison")
                }
                let mismatches = try mismatchSections(
                    comparison.incrementalSnapshot,
                    comparison.referenceSnapshot
                )
                print("mismatch_sections=\(mismatches.joined(separator: ","))")
                print("mismatched_path_count=\(comparison.mismatchedPathHashes.count)")
                print("mismatched_path_hashes=\(comparison.mismatchedPathHashes.prefix(12).joined(separator: ","))")
                print("record_count_delta=\(comparison.incrementalRecordCount - comparison.referenceRecordCount)")
                guard mismatches.isEmpty else {
                    throw BenchmarkError.message("incremental accounting differs from full rebuild")
                }
                print("reference_ms=\(milliseconds(referenceElapsed))")
                print("accounting_match=true")
            }
        } catch {
            fputs("Energy efficiency benchmark failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        return Int(components.seconds * 1_000)
            + Int(components.attoseconds / 1_000_000_000_000_000)
    }

    private static func accountingSignature(_ snapshot: UsageSnapshot) throws -> Data {
        var normalized = snapshot
        normalized.generatedAt = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(normalized)
    }

    private static func mismatchSections(
        _ lhs: UsageSnapshot,
        _ rhs: UsageSnapshot
    ) throws -> [String] {
        var mismatches = [String]()
        if try canonical(lhs.totals) != canonical(rhs.totals) { mismatches.append("totals") }
        if try canonical(lhs.daily) != canonical(rhs.daily) { mismatches.append("daily") }
        if try canonical(lhs.rhythms) != canonical(rhs.rhythms) { mismatches.append("rhythms") }
        if try canonical(lhs.agentWork) != canonical(rhs.agentWork) { mismatches.append("agent_work") }
        if try canonical(lhs.tools) != canonical(rhs.tools) { mismatches.append("tools") }
        if try canonical(lhs.models) != canonical(rhs.models) { mismatches.append("models") }
        if try canonical(lhs.sources) != canonical(rhs.sources) { mismatches.append("sources") }
        return mismatches
    }

    private static func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}

private enum BenchmarkError: Error {
    case message(String)
}
