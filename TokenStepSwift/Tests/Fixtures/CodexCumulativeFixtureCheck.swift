import Darwin
import Foundation

@main
struct CodexCumulativeFixtureCheck {
    static func main() {
        do {
            try checkCumulativeDeduplicationAndCompaction()
            try checkCredibleCounterReset()
            try checkLegacyFallback()
            try checkResumedSessionExplicitBaseline()
            try checkReplayChildWithSecondMetadata()
            try checkReplayChildWithSingleMetadata()
            try checkIsolatedChild()
            try checkParallelChildren()
            try checkNestedChild()
            try checkRescanAppendAndRebuildStability()
            try checkFirstFullValidationDoesNotTrustMissingHash()
            try checkFullValidationDetectsMiddleRewrite()
            try checkFullValidationRescansRewriteThenAppend()
            try checkParentAnchorCacheDependency()
            try checkLateSessionMetadataForcesFullRescan()
            try checkCorruptIncrementalCacheSelfHeals()
            try checkCorruptIncrementalPayloadSelfHeals()
            try checkLegacyCacheRevisionTriggersRecalibration()
            try checkReasoningAndCachedSubsetsAreNotDoublePriced()
            try checkShanghaiMidnightBoundary()
            print("Codex cumulative collector fixture checks passed")
        } catch {
            fputs("Codex cumulative collector fixture failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func checkCumulativeDeduplicationAndCompaction() throws {
        try withFixtureHome("cumulative") { home in
            let v100 = UsageVector(input: 80, output: 20, cached: 60, reasoning: 5)
            let v160 = UsageVector(input: 125, output: 35, cached: 90, reasoning: 10)
            let v230 = UsageVector(input: 180, output: 50, cached: 120, reasoning: 15)
            let d60 = UsageVector(input: 45, output: 15, cached: 30, reasoning: 5)
            let d70 = UsageVector(input: 55, output: 15, cached: 30, reasoning: 5)
            let hugeLast = UsageVector(
                input: 1_600_000,
                output: 366_220,
                cached: 1_200_000,
                reasoning: 300_000
            )
            let compactedLast = UsageVector(input: 7_000, output: 1_271, cached: 5_000, reasoning: 1_000)

            try writeSession(
                home: home,
                filename: "normal-and-repeated.jsonl",
                lines: [
                    sessionMeta(id: "normal-session", timestamp: "2026-07-13T08:00:00Z"),
                    turnContext(model: "gpt-5", timestamp: "2026-07-13T08:00:01Z"),
                    tokenCount(timestamp: "2026-07-13T08:01:00Z", cumulative: v100, last: v100),
                    tokenCount(timestamp: "2026-07-13T08:02:00Z", cumulative: v160, last: d60),
                    tokenCount(timestamp: "2026-07-13T08:03:00Z", cumulative: v160, last: d60, marker: "turn_complete"),
                    tokenCount(timestamp: "2026-07-13T08:04:00Z", cumulative: v160, last: d60, marker: "paused"),
                    tokenCount(timestamp: "2026-07-13T08:05:00Z", cumulative: v160, last: hugeLast, marker: "context_compacted"),
                    tokenCount(
                        timestamp: "2026-07-13T08:05:01Z",
                        cumulative: nil,
                        last: compactedLast,
                        marker: "compaction_last_only"
                    ),
                    tokenCount(timestamp: "2026-07-13T08:06:00Z", cumulative: v230, last: d70, marker: "resumed"),
                    tokenCount(timestamp: "2026-07-13T08:07:00Z", cumulative: v230, last: d70, marker: "task_complete")
                ]
            )

            let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home)
            try expectEqual(snapshot.totals.tokens, 230, "cumulative total uses only positive deltas")
            try expectEqual(snapshot.sources["Codex"]?.exactRecords, 3, "three positive cumulative increments")
            try expectEqual(snapshot.sources["Codex"]?.legacyRecords, 0, "mixed-schema last-only event is not legacy fallback")
            try expectEqual(snapshot.sources["Codex"]?.duplicateRecords, 4, "same cumulative snapshots are duplicates")
            try expectEqual(snapshot.sources["Codex"]?.skippedRecords, 1, "last-only compaction event is skipped")
            try expectEqual(
                snapshot.sources["Codex"]?.tokenBreakdown,
                SourceTokenBreakdown(
                    processedTokens: 230,
                    inputTokens: 180,
                    cachedInputTokens: 120,
                    uncachedInputTokens: 60,
                    outputTokens: 50,
                    reasoningTokens: 15
                ),
                "component deltas remain intact"
            )
        }
    }

    private static func checkCredibleCounterReset() throws {
        try withFixtureHome("reset") { home in
            let v50 = UsageVector(input: 40, output: 10, cached: 25, reasoning: 3)
            let v80 = UsageVector(input: 60, output: 20, cached: 40, reasoning: 8)
            let v10 = UsageVector(input: 8, output: 2, cached: 5, reasoning: 1)
            let v30 = UsageVector(input: 20, output: 10, cached: 15, reasoning: 4)
            try writeSession(
                home: home,
                filename: "counter-reset.jsonl",
                lines: [
                    sessionMeta(id: "reset-session", timestamp: "2026-07-13T09:00:00Z"),
                    turnContext(model: "gpt-5", timestamp: "2026-07-13T09:00:01Z"),
                    tokenCount(timestamp: "2026-07-13T09:01:00Z", cumulative: v50, last: v50),
                    tokenCount(
                        timestamp: "2026-07-13T09:02:00Z",
                        cumulative: v80,
                        last: UsageVector(input: 20, output: 10, cached: 15, reasoning: 5)
                    ),
                    contextWindowSentinel(timestamp: "2026-07-13T09:02:30Z", contextWindow: 40),
                    tokenCount(timestamp: "2026-07-13T09:03:00Z", cumulative: v10, last: v10, marker: "counter_reset"),
                    tokenCount(
                        timestamp: "2026-07-13T09:04:00Z",
                        cumulative: v30,
                        last: UsageVector(input: 12, output: 8, cached: 10, reasoning: 3)
                    )
                ]
            )

            let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home)
            try expectEqual(snapshot.totals.tokens, 110, "credible reset starts a new cumulative epoch")
            try expectEqual(snapshot.sources["Codex"]?.counterResets, 1, "one reset is diagnosed")
            try expectEqual(snapshot.sources["Codex"]?.skippedRecords, 1, "context-window sentinel is ignored without moving the counter")
            try expectEqual(snapshot.sources["Codex"]?.exactRecords, 4, "all positive increments across epochs survive")
            try expectEqual(snapshot.sources["Codex"]?.tokenBreakdown?.inputTokens, 80, "reset input components")
            try expectEqual(snapshot.sources["Codex"]?.tokenBreakdown?.outputTokens, 30, "reset output components")
        }
    }

    private static func checkLegacyFallback() throws {
        try withFixtureHome("legacy") { home in
            let first = UsageVector(input: 80, output: 20, cached: 50, reasoning: 5)
            let second = UsageVector(input: 35, output: 15, cached: 20, reasoning: 4)
            try writeSession(
                home: home,
                filename: "legacy-last-only.jsonl",
                lines: [
                    sessionMeta(id: "legacy-session", timestamp: "2026-07-13T10:00:00Z"),
                    turnContext(model: "gpt-5", timestamp: "2026-07-13T10:00:01Z"),
                    tokenCount(timestamp: "2026-07-13T10:01:00Z", cumulative: nil, last: first),
                    tokenCount(timestamp: "2026-07-13T10:02:00Z", cumulative: nil, last: second)
                ]
            )

            let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home)
            try expectEqual(snapshot.totals.tokens, 150, "legacy last-only usage remains available")
            try expectEqual(snapshot.sources["Codex"]?.exactRecords, 0, "legacy events are not presented as exact")
            try expectEqual(snapshot.sources["Codex"]?.legacyRecords, 2, "legacy records are explicitly diagnosed")
        }
    }

    private static func checkResumedSessionExplicitBaseline() throws {
        try withFixtureHome("resumed-explicit-baseline") { home in
            let resumedBaseline = UsageVector(
                input: 80,
                output: 20,
                cached: 60,
                reasoning: 5,
                explicitTotal: 250
            )
            let resumedNext = UsageVector(
                input: 125,
                output: 35,
                cached: 90,
                reasoning: 10,
                explicitTotal: 310
            )
            let delta = UsageVector(input: 45, output: 15, cached: 30, reasoning: 5)
            try writeSession(
                home: home,
                filename: "resumed-explicit-baseline.jsonl",
                lines: [
                    sessionMeta(id: "resumed-explicit", timestamp: "2026-07-13T10:30:00Z"),
                    turnContext(model: "gpt-5", timestamp: "2026-07-13T10:30:01Z"),
                    tokenCount(
                        timestamp: "2026-07-13T10:31:00Z",
                        cumulative: resumedBaseline,
                        last: UsageVector(input: 80, output: 20, cached: 60, reasoning: 5)
                    ),
                    tokenCount(
                        timestamp: "2026-07-13T10:32:00Z",
                        cumulative: resumedNext,
                        last: delta
                    )
                ]
            )

            let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home)
            try expectEqual(
                snapshot.totals.tokens,
                310,
                "explicit cumulative total preserves a resumed-session historical baseline"
            )
            try expectEqual(
                snapshot.sources["Codex"]?.unknownBreakdownRecords,
                1,
                "an unreconciled baseline is retained as total-only"
            )
            try expectEqual(
                snapshot.sources["Codex"]?.tokenBreakdown,
                SourceTokenBreakdown(
                    processedTokens: 310,
                    inputTokens: 45,
                    cachedInputTokens: 30,
                    uncachedInputTokens: 15,
                    outputTokens: 15,
                    reasoningTokens: 5
                ),
                "known post-resume deltas keep their canonical breakdown"
            )
            try expectEqual(
                snapshot.agentWork.first?.cacheHitRate,
                nil,
                "an unknown historical baseline must not be presented as a zero cache rate"
            )
        }
    }

    private static func checkReplayChildWithSecondMetadata() throws {
        try withFixtureHome("replay-second-meta") { home in
            let parentID = "parent-with-replay"
            try writeParentWithPostForkUsage(home: home, filename: "99-parent.jsonl", id: parentID)
            try writeSession(
                home: home,
                filename: "00-child.jsonl",
                lines: replayChildLines(
                    id: "replay-child",
                    parentID: parentID,
                    includeSecondParentMetadata: true,
                    terminalTotals: [360, 420]
                )
            )

            let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home)
            try expectEqual(snapshot.totals.tokens, 570, "parent 450 plus child-exclusive 120")
            try expectEqual(snapshot.sources["Codex"]?.inheritedTokens, 300, "replayed parent anchor is diagnosed")
            try expectEqual(snapshot.sources["Codex"]?.files, 2, "child filename sorting before parent is safe")
        }
    }

    private static func checkReplayChildWithSingleMetadata() throws {
        try withFixtureHome("replay-single-meta") { home in
            let parentID = "parent-single-meta"
            try writeSimpleParent(home: home, filename: "parent.jsonl", id: parentID)
            try writeSession(
                home: home,
                filename: "child.jsonl",
                lines: replayChildLines(
                    id: "single-meta-child",
                    parentID: parentID,
                    includeSecondParentMetadata: false,
                    replayTotals: [300],
                    terminalTotals: [360]
                )
            )

            let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home)
            try expectEqual(snapshot.totals.tokens, 360, "single-meta replay child contributes only 60")
            try expectEqual(snapshot.sources["Codex"]?.inheritedTokens, 300, "single-meta anchor is recognized")
        }
    }

    private static func checkIsolatedChild() throws {
        try withFixtureHome("isolated-child") { home in
            let parentID = "parent-isolated"
            try writeSimpleParent(home: home, filename: "parent.jsonl", id: parentID)
            try writeSession(
                home: home,
                filename: "child.jsonl",
                lines: [
                    sessionMeta(id: "isolated-child", timestamp: "2026-07-13T00:04:00Z", parentID: parentID),
                    turnContext(model: "gpt-5", timestamp: "2026-07-13T00:04:01Z"),
                    tokenCount(timestamp: "2026-07-13T00:05:00Z", cumulative: vector(total: 20), last: vector(total: 20)),
                    tokenCount(timestamp: "2026-07-13T00:06:00Z", cumulative: vector(total: 50), last: vector(total: 30))
                ]
            )

            let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home)
            try expectEqual(snapshot.totals.tokens, 350, "isolated child starts at zero and keeps all 50")
            try expectEqual(snapshot.sources["Codex"]?.inheritedTokens, 0, "isolated child is not force-subtracted")
        }
    }

    private static func checkParallelChildren() throws {
        try withFixtureHome("parallel-children") { home in
            let parentID = "parallel-parent"
            try writeSimpleParent(home: home, filename: "parent.jsonl", id: parentID)
            try writeSession(
                home: home,
                filename: "child-a.jsonl",
                lines: replayChildLines(
                    id: "parallel-child-a",
                    parentID: parentID,
                    includeSecondParentMetadata: false,
                    replayTotals: [300],
                    terminalTotals: [350]
                )
            )
            try writeSession(
                home: home,
                filename: "child-b.jsonl",
                lines: replayChildLines(
                    id: "parallel-child-b",
                    parentID: parentID,
                    includeSecondParentMetadata: true,
                    terminalTotals: [370]
                )
            )

            let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home)
            try expectEqual(snapshot.totals.tokens, 420, "parallel children retain independent 50 and 70 deltas")
            try expectEqual(snapshot.sources["Codex"]?.inheritedTokens, 600, "each sibling has its own parent anchor")
        }
    }

    private static func checkNestedChild() throws {
        try withFixtureHome("nested-child") { home in
            let rootID = "nested-root"
            let childID = "nested-child"
            try writeSimpleParent(home: home, filename: "root.jsonl", id: rootID)
            try writeSession(
                home: home,
                filename: "child.jsonl",
                lines: replayChildLines(
                    id: childID,
                    parentID: rootID,
                    includeSecondParentMetadata: false,
                    replayTotals: [300],
                    terminalTotals: [360, 420]
                )
            )
            try writeSession(
                home: home,
                filename: "grandchild.jsonl",
                lines: [
                    sessionMeta(id: "nested-grandchild", timestamp: "2026-07-13T00:08:00Z", parentID: childID),
                    turnContext(model: "gpt-5", timestamp: "2026-07-13T00:08:01Z"),
                    tokenCount(timestamp: "2026-07-13T00:08:10Z", cumulative: vector(total: 300), last: vector(total: 300)),
                    tokenCount(timestamp: "2026-07-13T00:08:20Z", cumulative: vector(total: 420), last: vector(total: 120)),
                    tokenCount(timestamp: "2026-07-13T00:09:00Z", cumulative: vector(total: 455), last: vector(total: 35)),
                    tokenCount(timestamp: "2026-07-13T00:09:10Z", cumulative: vector(total: 455), last: vector(total: 35), marker: "task_complete"),
                    tokenCount(timestamp: "2026-07-13T00:10:00Z", cumulative: vector(total: 500), last: vector(total: 45))
                ]
            )

            let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home)
            try expectEqual(snapshot.totals.tokens, 500, "root 300 + child 120 + grandchild 80")
            try expectEqual(snapshot.sources["Codex"]?.inheritedTokens, 720, "nested child anchors to immediate parent raw cumulative")
            try expectEqual(snapshot.sources["Codex"]?.duplicateRecords, 1, "nested repeated snapshot is ignored")
        }
    }

    private static func checkRescanAppendAndRebuildStability() throws {
        try withFixtureHome("stable-rescan") { home in
            let cacheURL = home.appendingPathComponent("fixture-cache/codex-incremental.sqlite3")
            let initialLines = [
                sessionMeta(id: "stable-session", timestamp: "2026-07-13T11:00:00Z"),
                turnContext(model: "gpt-5", timestamp: "2026-07-13T11:00:01Z"),
                tokenCount(timestamp: "2026-07-13T11:01:00Z", cumulative: vector(total: 100), last: vector(total: 100)),
                tokenCount(timestamp: "2026-07-13T11:02:00Z", cumulative: vector(total: 160), last: vector(total: 60))
            ]
            let log = try writeSession(home: home, filename: "stable.jsonl", lines: initialLines)

            let first = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home, cacheURL: cacheURL)
            let firstStats = try requireCacheStats(cacheURL)
            let repeated = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home, cacheURL: cacheURL)
            try expectEqual(first.totals.tokens, 160, "initial scan total")
            try expectEqual(snapshotSignature(repeated), snapshotSignature(first), "unchanged repeated scan is deterministic")
            try expectEqual(try requireCacheStats(cacheURL), firstStats, "unchanged cache hit performs no writes")

            let originalMetadata = try FileManager.default.attributesOfItem(atPath: log.path)
            let originalModificationDate = originalMetadata[.modificationDate] as? Date
            let rewrittenLines = [
                initialLines[0],
                initialLines[1],
                initialLines[2],
                tokenCount(timestamp: "2026-07-13T11:02:00Z", cumulative: vector(total: 190), last: vector(total: 90))
            ]
            let originalSize = try Data(contentsOf: log).count
            try (rewrittenLines.joined(separator: "\n") + "\n").write(to: log, atomically: true, encoding: .utf8)
            try expectEqual(try Data(contentsOf: log).count, originalSize, "rewrite preserves file size")
            if let originalModificationDate {
                try FileManager.default.setAttributes([.modificationDate: originalModificationDate], ofItemAtPath: log.path)
                let restoredAttributes = try FileManager.default.attributesOfItem(atPath: log.path)
                let restoredModificationDate = restoredAttributes[.modificationDate] as? Date
                guard let restoredModificationDate,
                      abs(
                        restoredModificationDate.timeIntervalSince1970
                            - originalModificationDate.timeIntervalSince1970
                      ) < 0.001
                else {
                    throw FixtureFailure(
                        "rewrite restores the cached modification time within filesystem precision"
                    )
                }
            }
            let afterSameMetadataRewrite = UsageCollector.collectCodexUsageSnapshotForTests(
                homeURL: home,
                cacheURL: cacheURL,
                forceFullValidation: true
            )
            try expectEqual(
                afterSameMetadataRewrite.totals.tokens,
                190,
                "content fingerprint invalidates same-size same-mtime rewrites"
            )

            let appended = tokenCount(
                timestamp: "2026-07-13T11:03:00Z",
                cumulative: vector(total: 230),
                last: vector(total: 70)
            )
            try appendLine(appended, to: log)
            let afterAppend = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home, cacheURL: cacheURL)
            try expectEqual(afterAppend.totals.tokens, 230, "append advances only to final cumulative total")

            let rebuiltCacheURL = home.appendingPathComponent("fixture-cache/codex-rebuilt.sqlite3")
            let afterCacheRebuild = UsageCollector.collectCodexUsageSnapshotForTests(
                homeURL: home,
                cacheURL: rebuiltCacheURL
            )
            try expectEqual(
                snapshotSignature(afterCacheRebuild),
                snapshotSignature(afterAppend),
                "deleting and rebuilding the cache preserves accounting"
            )

            try withFixtureHome("rebuilt-copy") { rebuiltHome in
                try writeSession(home: rebuiltHome, filename: "renamed-after-rebuild.jsonl", lines: initialLines + [appended])
                let rebuilt = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: rebuiltHome)
                try expectEqual(
                    snapshotSignature(rebuilt),
                    snapshotSignature(afterAppend),
                    "fresh cache-equivalent rebuild has identical accounting"
                )
            }
        }
    }

    private static func checkParentAnchorCacheDependency() throws {
        try withFixtureHome("parent-cache-dependency") { home in
            let cacheURL = home.appendingPathComponent("fixture-cache/codex-incremental.sqlite3")
            let parentLines = [
                sessionMeta(id: "cache-parent", timestamp: "2026-07-13T00:00:00Z"),
                turnContext(model: "gpt-5", timestamp: "2026-07-13T00:00:01Z"),
                tokenCount(timestamp: "2026-07-13T00:01:00Z", cumulative: vector(total: 100), last: vector(total: 100)),
                tokenCount(timestamp: "2026-07-13T00:02:00Z", cumulative: vector(total: 200), last: vector(total: 100)),
                String(repeating: "ignored-padding-", count: 512)
            ]
            let parentLog = try writeSession(home: home, filename: "99-parent.jsonl", lines: parentLines)
            try writeSession(
                home: home,
                filename: "00-child.jsonl",
                lines: replayChildLines(
                    id: "cache-child",
                    parentID: "cache-parent",
                    includeSecondParentMetadata: false,
                    replayTotals: [100, 200, 300],
                    terminalTotals: [360]
                )
            )

            let beforeParentAppend = UsageCollector.collectCodexUsageSnapshotForTests(
                homeURL: home,
                cacheURL: cacheURL
            )
            try expectEqual(beforeParentAppend.totals.tokens, 360, "initial parent 200 plus child-exclusive 160")
            try expectEqual(beforeParentAppend.sources["Codex"]?.inheritedTokens, 200, "initial cached fork anchor")

            try appendLine(
                tokenCount(
                    timestamp: "2026-07-13T00:03:00Z",
                    cumulative: vector(total: 300),
                    last: vector(total: 100)
                ),
                to: parentLog
            )
            let afterParentAppend = UsageCollector.collectCodexUsageSnapshotForTests(
                homeURL: home,
                cacheURL: cacheURL
            )
            try expectEqual(afterParentAppend.totals.tokens, 360, "parent anchor update does not replay cached child history")
            try expectEqual(afterParentAppend.sources["Codex"]?.inheritedTokens, 300, "unchanged child cache uses refreshed parent anchor")
        }
    }

    private static func checkFullValidationDetectsMiddleRewrite() throws {
        try withFixtureHome("full-validation-middle-rewrite") { home in
            let cacheURL = home.appendingPathComponent("fixture-cache/codex-incremental.sqlite3")
            let initialLines = [
                String(repeating: "leading-padding-", count: 400),
                sessionMeta(id: "middle-rewrite", timestamp: "2026-07-13T11:30:00Z"),
                turnContext(model: "gpt-5", timestamp: "2026-07-13T11:30:01Z"),
                tokenCount(timestamp: "2026-07-13T11:31:00Z", cumulative: vector(total: 100), last: vector(total: 100)),
                tokenCount(timestamp: "2026-07-13T11:32:00Z", cumulative: vector(total: 160), last: vector(total: 60)),
                String(repeating: "trailing-padding-", count: 400)
            ]
            let log = try writeSession(home: home, filename: "middle.jsonl", lines: initialLines)
            let initial = UsageCollector.collectCodexUsageSnapshotForTests(
                homeURL: home,
                cacheURL: cacheURL
            )
            let initialStats = try requireCacheStats(cacheURL)
            try expectEqual(initial.totals.tokens, 160, "middle rewrite baseline")

            let validated = UsageCollector.collectCodexUsageSnapshotForTests(
                homeURL: home,
                cacheURL: cacheURL,
                forceFullValidation: true
            )
            try expectEqual(validated.totals.tokens, 160, "full validation baseline")
            try expectEqual(
                try requireCacheStats(cacheURL).generation,
                initialStats.generation,
                "recording a strong validation hash does not rewrite accounting payloads"
            )

            let originalAttributes = try FileManager.default.attributesOfItem(atPath: log.path)
            let originalModificationDate = originalAttributes[.modificationDate] as? Date
            var rewrittenLines = initialLines
            rewrittenLines[4] = tokenCount(
                timestamp: "2026-07-13T11:32:00Z",
                cumulative: vector(total: 190),
                last: vector(total: 90)
            )
            let originalSize = try Data(contentsOf: log).count
            try (rewrittenLines.joined(separator: "\n") + "\n").write(
                to: log,
                atomically: true,
                encoding: .utf8
            )
            try expectEqual(try Data(contentsOf: log).count, originalSize, "middle rewrite size")
            if let originalModificationDate {
                try FileManager.default.setAttributes(
                    [.modificationDate: originalModificationDate],
                    ofItemAtPath: log.path
                )
            }

            let rewritten = UsageCollector.collectCodexUsageSnapshotForTests(
                homeURL: home,
                cacheURL: cacheURL,
                forceFullValidation: true
            )
            try expectEqual(
                rewritten.totals.tokens,
                190,
                "strong validation detects a same-size same-mtime middle rewrite"
            )
        }
    }

    private static func checkFirstFullValidationDoesNotTrustMissingHash() throws {
        try withFixtureHome("first-validation-middle-rewrite") { home in
            let cacheURL = home.appendingPathComponent("fixture-cache/codex-incremental.sqlite3")
            let initialLines = [
                String(repeating: "leading-padding-", count: 400),
                sessionMeta(id: "first-validation", timestamp: "2026-07-13T11:30:00Z"),
                turnContext(model: "gpt-5", timestamp: "2026-07-13T11:30:01Z"),
                tokenCount(timestamp: "2026-07-13T11:31:00Z", cumulative: vector(total: 100), last: vector(total: 100)),
                tokenCount(timestamp: "2026-07-13T11:32:00Z", cumulative: vector(total: 160), last: vector(total: 60)),
                String(repeating: "trailing-padding-", count: 400)
            ]
            let log = try writeSession(home: home, filename: "first-validation.jsonl", lines: initialLines)
            let initial = UsageCollector.collectCodexUsageSnapshotForTests(
                homeURL: home,
                cacheURL: cacheURL
            )
            try expectEqual(initial.totals.tokens, 160, "first validation baseline")

            let originalAttributes = try FileManager.default.attributesOfItem(atPath: log.path)
            let originalModificationDate = originalAttributes[.modificationDate] as? Date
            let originalSize = try Data(contentsOf: log).count
            var rewrittenLines = initialLines
            rewrittenLines[4] = tokenCount(
                timestamp: "2026-07-13T11:32:00Z",
                cumulative: vector(total: 190),
                last: vector(total: 90)
            )
            try (rewrittenLines.joined(separator: "\n") + "\n").write(
                to: log,
                atomically: true,
                encoding: .utf8
            )
            try expectEqual(try Data(contentsOf: log).count, originalSize, "first validation rewrite size")
            if let originalModificationDate {
                try FileManager.default.setAttributes(
                    [.modificationDate: originalModificationDate],
                    ofItemAtPath: log.path
                )
            }

            let validated = UsageCollector.collectCodexUsageSnapshotForTests(
                homeURL: home,
                cacheURL: cacheURL,
                forceFullValidation: true
            )
            try expectEqual(
                validated.totals.tokens,
                190,
                "first validation rescans instead of trusting a missing strong-hash baseline"
            )
        }
    }

    private static func checkFullValidationRescansRewriteThenAppend() throws {
        try withFixtureHome("full-validation-rewrite-append") { home in
            let cacheURL = home.appendingPathComponent("fixture-cache/codex-incremental.sqlite3")
            let freshCacheURL = home.appendingPathComponent("fresh-cache/codex-incremental.sqlite3")
            let initialLines = [
                String(repeating: "leading-padding-", count: 400),
                sessionMeta(id: "rewrite-append", timestamp: "2026-07-13T11:30:00Z"),
                turnContext(model: "gpt-5", timestamp: "2026-07-13T11:30:01Z"),
                tokenCount(timestamp: "2026-07-13T11:31:00Z", cumulative: vector(total: 100), last: vector(total: 100)),
                tokenCount(timestamp: "2026-07-13T11:32:00Z", cumulative: vector(total: 160), last: vector(total: 60)),
                String(repeating: "trailing-padding-", count: 400)
            ]
            let log = try writeSession(home: home, filename: "rewrite-append.jsonl", lines: initialLines)
            _ = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home, cacheURL: cacheURL)
            _ = UsageCollector.collectCodexUsageSnapshotForTests(
                homeURL: home,
                cacheURL: cacheURL,
                forceFullValidation: true
            )

            let originalAttributes = try FileManager.default.attributesOfItem(atPath: log.path)
            let originalModificationDate = originalAttributes[.modificationDate] as? Date
            let originalSize = try Data(contentsOf: log).count
            var rewrittenLines = initialLines
            rewrittenLines[4] = tokenCount(
                timestamp: "2026-07-13T11:32:00Z",
                cumulative: vector(total: 190),
                last: vector(total: 90)
            )
            try (rewrittenLines.joined(separator: "\n") + "\n").write(
                to: log,
                atomically: true,
                encoding: .utf8
            )
            try expectEqual(try Data(contentsOf: log).count, originalSize, "rewrite-append prefix size")
            if let originalModificationDate {
                try FileManager.default.setAttributes(
                    [.modificationDate: originalModificationDate],
                    ofItemAtPath: log.path
                )
            }
            try appendLine(
                turnContext(model: "gpt-5", timestamp: "2026-07-14T00:00:00Z"),
                to: log
            )
            try appendLine(
                tokenCount(
                    timestamp: "2026-07-14T00:01:00Z",
                    cumulative: vector(total: 230),
                    last: vector(total: 40)
                ),
                to: log
            )

            let validated = UsageCollector.collectCodexUsageSnapshotForTests(
                homeURL: home,
                cacheURL: cacheURL,
                forceFullValidation: true
            )
            try expectEqual(dailyTokens(validated, date: "2026-07-13"), 190, "rewrite-append corrected prior day")
            try expectEqual(dailyTokens(validated, date: "2026-07-14"), 40, "rewrite-append keeps only the new-day delta")

            let rebuilt = UsageCollector.collectCodexUsageSnapshotForTests(
                homeURL: home,
                cacheURL: freshCacheURL
            )
            try expectEqual(
                snapshotSignature(validated),
                snapshotSignature(rebuilt),
                "forced rewrite-append validation matches a clean rebuild"
            )
        }
    }

    private static func checkCorruptIncrementalCacheSelfHeals() throws {
        try withFixtureHome("corrupt-incremental-cache") { home in
            let cacheURL = home.appendingPathComponent("fixture-cache/codex-incremental.sqlite3")
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("not-a-sqlite-database".utf8).write(to: cacheURL)
            try writeSession(
                home: home,
                filename: "recoverable.jsonl",
                lines: [
                    sessionMeta(id: "recoverable", timestamp: "2026-07-13T12:00:00Z"),
                    turnContext(model: "gpt-5", timestamp: "2026-07-13T12:00:01Z"),
                    tokenCount(
                        timestamp: "2026-07-13T12:01:00Z",
                        cumulative: vector(total: 140),
                        last: vector(total: 140)
                    )
                ]
            )

            let snapshot = UsageCollector.collectCodexWithIncrementalFallbackForTests(
                homeURL: home,
                cacheURL: cacheURL
            )
            try expectEqual(snapshot.totals.tokens, 140, "corrupt cache rebuild preserves accounting")
            try expectEqual(snapshot.sources["Codex"]?.status, "ok", "corrupt cache rebuild status")
            let stats = try requireCacheStats(cacheURL)
            try expectEqual(stats.sessions, 1, "corrupt cache is replaced with a valid incremental store")
        }
    }

    private static func checkLateSessionMetadataForcesFullRescan() throws {
        try withFixtureHome("late-session-metadata") { home in
            let cacheURL = home.appendingPathComponent("fixture-cache/codex-incremental.sqlite3")
            try writeSimpleParent(home: home, filename: "99-parent.jsonl", id: "late-meta-parent")
            let child = try writeSession(
                home: home,
                filename: "00-child.jsonl",
                lines: ["{\"type\":\"event_msg\",\"payload\":{\"type\":\"noop\"}}"]
            )

            let beforeMetadata = UsageCollector.collectCodexUsageSnapshotForTests(
                homeURL: home,
                cacheURL: cacheURL
            )
            try expectEqual(beforeMetadata.totals.tokens, 300, "leading child log is initially empty")

            for line in replayChildLines(
                id: "late-meta-child",
                parentID: "late-meta-parent",
                includeSecondParentMetadata: false,
                terminalTotals: [360]
            ) {
                try appendLine(line, to: child)
            }
            let afterMetadata = UsageCollector.collectCodexUsageSnapshotForTests(
                homeURL: home,
                cacheURL: cacheURL
            )
            try expectEqual(
                afterMetadata.totals.tokens,
                360,
                "an appended first session_meta forces a full fork-aware rescan"
            )
            try expectEqual(
                afterMetadata.sources["Codex"]?.inheritedTokens,
                300,
                "late metadata restores the parent fork anchor"
            )
        }
    }

    private static func checkCorruptIncrementalPayloadSelfHeals() throws {
        try withFixtureHome("corrupt-incremental-payload") { home in
            let cacheURL = home.appendingPathComponent("fixture-cache/codex-incremental.sqlite3")
            try writeSession(
                home: home,
                filename: "payload.jsonl",
                lines: [
                    sessionMeta(id: "payload-session", timestamp: "2026-07-13T13:00:00Z"),
                    turnContext(model: "gpt-5", timestamp: "2026-07-13T13:00:01Z"),
                    tokenCount(
                        timestamp: "2026-07-13T13:01:00Z",
                        cumulative: vector(total: 175),
                        last: vector(total: 175)
                    )
                ]
            )
            let initial = UsageCollector.collectCodexUsageSnapshotForTests(
                homeURL: home,
                cacheURL: cacheURL
            )
            try expectEqual(initial.totals.tokens, 175, "payload corruption fixture baseline")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            process.arguments = [
                cacheURL.path,
                "UPDATE codex_sessions SET diagnostics = X'00'"
            ]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            try expectEqual(process.terminationStatus, 0, "fixture corrupts one cache payload")

            let healed = UsageCollector.collectCodexWithIncrementalFallbackForTests(
                homeURL: home,
                cacheURL: cacheURL
            )
            try expectEqual(healed.totals.tokens, 175, "payload corruption rebuild preserves accounting")
            try expectEqual(healed.sources["Codex"]?.status, "ok", "payload corruption rebuild status")
            try expectEqual(
                try requireCacheStats(cacheURL).sessions,
                1,
                "payload corruption is replaced instead of repeatedly falling back"
            )
        }
    }

    private static func checkLegacyCacheRevisionTriggersRecalibration() throws {
        try withFixtureHome("legacy-cache-revision") { home in
            let cacheURL = home.appendingPathComponent("fixture-cache/collector-cache-v7.json")
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let legacyCache = """
            {
              "version": 7,
              "files": {
                "/tmp/legacy.jsonl": {
                  "tool": "Codex",
                  "size": 1,
                  "modificationTime": 1,
                  "records": [
                    {
                      "date": "2026-07-13",
                      "timestamp": "2026-07-13T00:01:00Z",
                      "tool": "Codex",
                      "model": "gpt-5",
                      "usage": {
                        "inputTokens": 80,
                        "outputTokens": 20,
                        "cacheCreationInputTokens": 0,
                        "cacheReadInputTokens": 60,
                        "reasoningOutputTokens": 5,
                        "totalTokens": 100
                      },
                      "source": "nativeCodex"
                    }
                  ]
                }
              }
            }
            """
            try legacyCache.write(to: cacheURL, atomically: true, encoding: .utf8)
            try expectEqual(
                UsageCollector.collectorCacheRecalibrationRevisionForTests(cacheURL: cacheURL),
                7,
                "v7 cache records without Agent counters still preserve the revision and request v8 recalibration"
            )
        }
    }

    private static func checkReasoningAndCachedSubsetsAreNotDoublePriced() throws {
        try withFixtureHome("gpt-54-cost") { home in
            let usage = UsageVector(
                input: 1_000_000,
                output: 200_000,
                cached: 400_000,
                reasoning: 100_000
            )
            try writeSession(
                home: home,
                filename: "gpt-54.jsonl",
                lines: [
                    sessionMeta(id: "gpt-54-cost", timestamp: "2026-07-13T12:00:00Z"),
                    turnContext(model: "gpt-5.4", timestamp: "2026-07-13T12:00:01Z"),
                    tokenCount(timestamp: "2026-07-13T12:01:00Z", cumulative: usage, last: usage)
                ]
            )

            let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home)
            try expectEqual(snapshot.totals.tokens, 1_200_000, "processed total is input plus output only")
            try expectEqual(snapshot.totals.cost, 4.6, "cached and reasoning subsets are not double-priced")
            try expectEqual(snapshot.sources["Codex"]?.tokenBreakdown?.cachedInputTokens, 400_000, "cached subset retained")
            try expectEqual(snapshot.sources["Codex"]?.tokenBreakdown?.reasoningTokens, 100_000, "reasoning subset retained")
            try expectEqual(snapshot.sources["Codex"]?.tokenBreakdown?.uncachedInputTokens, 600_000, "uncached input derived once")
        }
    }

    private static func checkShanghaiMidnightBoundary() throws {
        try withFixtureHome("shanghai-midnight") { home in
            try writeSession(
                home: home,
                filename: "midnight.jsonl",
                lines: [
                    sessionMeta(id: "midnight-session", timestamp: "2026-06-21T15:59:00Z"),
                    turnContext(model: "gpt-5", timestamp: "2026-06-21T15:59:01Z"),
                    tokenCount(timestamp: "2026-06-21T15:59:59Z", cumulative: vector(total: 100), last: vector(total: 100)),
                    tokenCount(timestamp: "2026-06-21T16:00:00Z", cumulative: vector(total: 160), last: vector(total: 60))
                ]
            )

            let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home)
            try expectEqual(snapshot.daily.count, 2, "UTC 16:00 crosses Shanghai midnight")
            try expectEqual(dailyTokens(snapshot, date: "2026-06-21"), 100, "pre-midnight delta stays on prior Shanghai day")
            try expectEqual(dailyTokens(snapshot, date: "2026-06-22"), 60, "post-midnight delta moves to next Shanghai day")
            try expectEqual(snapshot.rhythm(for: "2026-06-21")?.bucket(hour: 23).tokens, 100, "23:59 Shanghai rhythm bucket")
            try expectEqual(snapshot.rhythm(for: "2026-06-22")?.bucket(hour: 0).tokens, 60, "00:00 Shanghai rhythm bucket")
        }
    }

    private static func writeParentWithPostForkUsage(home: URL, filename: String, id: String) throws {
        try writeSession(
            home: home,
            filename: filename,
            lines: [
                sessionMeta(id: id, timestamp: "2026-07-13T00:00:00Z"),
                turnContext(model: "gpt-5", timestamp: "2026-07-13T00:00:01Z"),
                tokenCount(timestamp: "2026-07-13T00:01:00Z", cumulative: vector(total: 100), last: vector(total: 100)),
                tokenCount(timestamp: "2026-07-13T00:02:00Z", cumulative: vector(total: 200), last: vector(total: 100)),
                tokenCount(timestamp: "2026-07-13T00:03:00Z", cumulative: vector(total: 300), last: vector(total: 100)),
                tokenCount(timestamp: "2026-07-13T00:10:00Z", cumulative: vector(total: 450), last: vector(total: 150))
            ]
        )
    }

    private static func writeSimpleParent(home: URL, filename: String, id: String) throws {
        try writeSession(
            home: home,
            filename: filename,
            lines: [
                sessionMeta(id: id, timestamp: "2026-07-13T00:00:00Z"),
                turnContext(model: "gpt-5", timestamp: "2026-07-13T00:00:01Z"),
                tokenCount(timestamp: "2026-07-13T00:01:00Z", cumulative: vector(total: 100), last: vector(total: 100)),
                tokenCount(timestamp: "2026-07-13T00:02:00Z", cumulative: vector(total: 200), last: vector(total: 100)),
                tokenCount(timestamp: "2026-07-13T00:03:00Z", cumulative: vector(total: 300), last: vector(total: 100))
            ]
        )
    }

    private static func replayChildLines(
        id: String,
        parentID: String,
        includeSecondParentMetadata: Bool,
        replayTotals: [Int] = [100, 200, 300],
        terminalTotals: [Int]
    ) -> [String] {
        var lines = [
            sessionMeta(id: id, timestamp: "2026-07-13T00:04:00Z", parentID: parentID)
        ]
        if includeSecondParentMetadata {
            lines.append(sessionMeta(id: parentID, timestamp: "2026-07-13T00:04:01Z"))
        }
        lines.append(turnContext(model: "gpt-5", timestamp: "2026-07-13T00:04:02Z"))
        var previous = 0
        for (index, total) in (replayTotals + terminalTotals).enumerated() {
            let increment = max(0, total - previous)
            lines.append(
                tokenCount(
                    timestamp: String(format: "2026-07-13T00:%02d:00Z", 5 + index),
                    cumulative: vector(total: total),
                    last: vector(total: increment)
                )
            )
            previous = total
        }
        return lines
    }

    private static func sessionMeta(id: String, timestamp: String, parentID: String? = nil) -> String {
        var payload: [String: Any] = ["id": id]
        if let parentID {
            payload["source"] = [
                "subagent": [
                    "thread_spawn": ["parent_thread_id": parentID]
                ]
            ]
        }
        return jsonLine([
            "type": "session_meta",
            "timestamp": timestamp,
            "payload": payload
        ])
    }

    private static func turnContext(model: String, timestamp: String) -> String {
        jsonLine([
            "type": "turn_context",
            "timestamp": timestamp,
            "payload": ["model": model]
        ])
    }

    private static func tokenCount(
        timestamp: String,
        cumulative: UsageVector?,
        last: UsageVector?,
        marker: String? = nil
    ) -> String {
        var info: [String: Any] = [:]
        if let cumulative {
            info["total_token_usage"] = cumulative.dictionary
        }
        if let last {
            info["last_token_usage"] = last.dictionary
        }
        var payload: [String: Any] = [
            "type": "token_count",
            "info": info
        ]
        if let marker {
            payload["status"] = marker
        }
        return jsonLine([
            "type": "event_msg",
            "timestamp": timestamp,
            "payload": payload
        ])
    }

    private static func contextWindowSentinel(timestamp: String, contextWindow: Int) -> String {
        let zeroUsage: [String: Any] = [
            "input_tokens": 0,
            "output_tokens": 0,
            "cached_input_tokens": 0,
            "reasoning_output_tokens": 0,
            "total_tokens": 0
        ]
        var cumulative = zeroUsage
        cumulative["total_tokens"] = contextWindow
        return jsonLine([
            "type": "event_msg",
            "timestamp": timestamp,
            "payload": [
                "type": "token_count",
                "info": [
                    "total_token_usage": cumulative,
                    "last_token_usage": zeroUsage,
                    "model_context_window": contextWindow
                ]
            ]
        ])
    }

    private static func vector(total: Int) -> UsageVector {
        let output = max(1, total / 5)
        return UsageVector(
            input: total - output,
            output: output,
            cached: min(total - output, total / 2),
            reasoning: min(output, total / 10)
        )
    }

    @discardableResult
    private static func writeSession(home: URL, filename: String, lines: [String]) throws -> URL {
        let root = home.appendingPathComponent(".codex/sessions/2026/07/13", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(filename)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func appendLine(_ line: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line + "\n").utf8))
        try handle.synchronize()
    }

    private static func withFixtureHome(
        _ label: String,
        body: (URL) throws -> Void
    ) throws {
        let home = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("TokenStepCodex-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try body(home)
    }

    private static func dailyTokens(_ snapshot: UsageSnapshot, date: String) -> Int? {
        snapshot.daily.first(where: { $0.date == date })?.totalTokens
    }

    private static func requireCacheStats(_ url: URL) throws -> CodexIncrementalCacheStats {
        guard let stats = UsageCollector.codexIncrementalCacheStatsForTests(databaseURL: url) else {
            throw FixtureFailure("incremental cache stats are available")
        }
        return stats
    }

    private static func snapshotSignature(_ snapshot: UsageSnapshot) -> SnapshotSignature {
        SnapshotSignature(
            tokens: snapshot.totals.tokens,
            cost: snapshot.totals.cost,
            daily: snapshot.daily.map { "\($0.date):\($0.totalTokens)" },
            exact: snapshot.sources["Codex"]?.exactRecords,
            legacy: snapshot.sources["Codex"]?.legacyRecords,
            duplicates: snapshot.sources["Codex"]?.duplicateRecords,
            resets: snapshot.sources["Codex"]?.counterResets,
            breakdown: snapshot.sources["Codex"]?.tokenBreakdown
        )
    }

    private static func jsonLine(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    private static func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ label: String
    ) throws {
        guard actual == expected else {
            throw FixtureFailure("\(label): expected \(expected), got \(actual)")
        }
    }
}

private struct UsageVector {
    var input: Int
    var output: Int
    var cached: Int
    var reasoning: Int
    var explicitTotal: Int? = nil

    var dictionary: [String: Any] {
        [
            "input_tokens": input,
            "output_tokens": output,
            "cached_input_tokens": cached,
            "reasoning_output_tokens": reasoning,
            "total_tokens": explicitTotal ?? (input + output)
        ]
    }
}

private struct SnapshotSignature: Equatable {
    var tokens: Int
    var cost: Double
    var daily: [String]
    var exact: Int?
    var legacy: Int?
    var duplicates: Int?
    var resets: Int?
    var breakdown: SourceTokenBreakdown?
}

private struct FixtureFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
