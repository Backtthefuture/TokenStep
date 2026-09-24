import Foundation

extension UsageCollector {
    static func deduplicateCrossSource(
        nativeRecords: [UsageRecord],
        proxyRecords: [UsageRecord]
    ) -> CrossSourceDedupeResult {
        var enrichedNativeRecords = nativeRecords
        let deduplicableProxyIndices = proxyRecords.indices.filter {
            isDeduplicableProxyRecord(proxyRecords[$0])
        }
        var matchedProxyIndices = Set<Int>()
        var matchedNativeIndices = Set<Int>()
        let skippedProxyRecords = 0

        let exactPairs = uniqueDedupePairs(
            proxyIndices: deduplicableProxyIndices,
            nativeIndices: Array(nativeRecords.indices)
        ) { proxyIndex, nativeIndex in
            isSameDedupeDomain(
                proxyRecord: proxyRecords[proxyIndex],
                nativeRecord: nativeRecords[nativeIndex]
            ) && hasExactIdentifierMatch(
                proxyRecord: proxyRecords[proxyIndex],
                nativeRecord: nativeRecords[nativeIndex]
            )
        }
        applyDedupePairs(
            exactPairs,
            proxyRecords: proxyRecords,
            enrichedNativeRecords: &enrichedNativeRecords,
            matchedProxyIndices: &matchedProxyIndices,
            matchedNativeIndices: &matchedNativeIndices
        )

        // Similar timing/model/token vectors alone are not proof of identity: concurrent
        // requests can legitimately look the same. A shared session is the minimum
        // fallback correlation when request/response IDs are unavailable.
        let remainingProxyIndices = deduplicableProxyIndices.filter { !matchedProxyIndices.contains($0) }
        let remainingNativeIndices = nativeRecords.indices.filter { !matchedNativeIndices.contains($0) }
        let sessionPairs = uniqueDedupePairs(
            proxyIndices: remainingProxyIndices,
            nativeIndices: Array(remainingNativeIndices)
        ) { proxyIndex, nativeIndex in
            isSameDedupeDomain(
                proxyRecord: proxyRecords[proxyIndex],
                nativeRecord: nativeRecords[nativeIndex]
            ) && hasSessionIdentityMatch(
                proxyRecord: proxyRecords[proxyIndex],
                nativeRecord: nativeRecords[nativeIndex]
            )
        }
        applyDedupePairs(
            sessionPairs,
            proxyRecords: proxyRecords,
            enrichedNativeRecords: &enrichedNativeRecords,
            matchedProxyIndices: &matchedProxyIndices,
            matchedNativeIndices: &matchedNativeIndices
        )

        let keptProxyRecords = proxyRecords.indices
            .filter { !matchedProxyIndices.contains($0) }
            .map { proxyRecords[$0] }
        return CrossSourceDedupeResult(
            records: enrichedNativeRecords + keptProxyRecords,
            rawProxyRecords: proxyRecords.count,
            keptProxyRecords: keptProxyRecords.count,
            dedupedProxyRecords: matchedProxyIndices.count,
            skippedProxyRecords: skippedProxyRecords
        )
    }

    static func uniqueDedupePairs(
        proxyIndices: [Int],
        nativeIndices: [Int],
        matches: (Int, Int) -> Bool
    ) -> [(proxy: Int, native: Int)] {
        var nativeCandidatesByProxy: [Int: [Int]] = [:]
        var proxyCandidateCountByNative: [Int: Int] = [:]
        for proxyIndex in proxyIndices {
            let candidates = nativeIndices.filter { matches(proxyIndex, $0) }
            nativeCandidatesByProxy[proxyIndex] = candidates
            for nativeIndex in candidates {
                proxyCandidateCountByNative[nativeIndex, default: 0] += 1
            }
        }
        return proxyIndices.compactMap { proxyIndex in
            guard let candidates = nativeCandidatesByProxy[proxyIndex],
                  candidates.count == 1,
                  let nativeIndex = candidates.first,
                  proxyCandidateCountByNative[nativeIndex] == 1
            else {
                return nil
            }
            return (proxy: proxyIndex, native: nativeIndex)
        }
    }

    static func applyDedupePairs(
        _ pairs: [(proxy: Int, native: Int)],
        proxyRecords: [UsageRecord],
        enrichedNativeRecords: inout [UsageRecord],
        matchedProxyIndices: inout Set<Int>,
        matchedNativeIndices: inout Set<Int>
    ) {
        for pair in pairs {
            enrichedNativeRecords[pair.native] = enrichedRecord(
                enrichedNativeRecords[pair.native],
                withProxyCostFrom: proxyRecords[pair.proxy]
            )
            matchedProxyIndices.insert(pair.proxy)
            matchedNativeIndices.insert(pair.native)
        }
    }

    static func sourceInfo(
        _ source: SourceInfo,
        annotatedWith result: CrossSourceDedupeResult
    ) -> SourceInfo {
        var annotated = source
        annotated.rawRecords = result.rawProxyRecords
        annotated.dedupedRecords = result.dedupedProxyRecords
        annotated.skippedRecords = result.skippedProxyRecords
        annotated.strategy = "request_level_dedupe"
        annotated.records = result.keptProxyRecords
        if source.status == "ok",
           result.rawProxyRecords > 0,
           result.keptProxyRecords == 0,
           result.dedupedProxyRecords > 0 {
            annotated.status = "all_deduped"
        }
        return annotated
    }

    static func isDeduplicableProxyRecord(_ record: UsageRecord) -> Bool {
        guard record.source == .ccSwitchProxy else { return false }
        guard let family = toolFamily(for: record.tool) else { return false }
        return family == "claude" || family == "codex"
    }

    static func isSameDedupeDomain(proxyRecord: UsageRecord, nativeRecord: UsageRecord) -> Bool {
        guard proxyRecord.date == nativeRecord.date,
              let proxyFamily = toolFamily(for: proxyRecord.tool),
              let nativeFamily = toolFamily(for: nativeRecord.tool),
              proxyFamily == nativeFamily,
              nativeRecord.source != .ccSwitchProxy
        else {
            return false
        }
        return true
    }

    static func hasExactIdentifierMatch(proxyRecord: UsageRecord, nativeRecord: UsageRecord) -> Bool {
        let proxyIDs = Set([proxyRecord.requestID, proxyRecord.responseID].compactMap(nonEmptyString))
        let nativeIDs = Set([nativeRecord.requestID, nativeRecord.responseID].compactMap(nonEmptyString))
        return !proxyIDs.isDisjoint(with: nativeIDs)
    }

    static func hasSessionIdentityMatch(proxyRecord: UsageRecord, nativeRecord: UsageRecord) -> Bool {
        guard let proxySessionID = nonEmptyString(proxyRecord.sessionID),
              let nativeSessionID = nonEmptyString(nativeRecord.sessionID),
              proxySessionID == nativeSessionID,
              areTimestampsClose(proxyRecord.timestamp, nativeRecord.timestamp, seconds: 10),
              modelsCompatible(proxyRecord.model, nativeRecord.model),
              usageVectorsClose(proxyRecord: proxyRecord, nativeRecord: nativeRecord)
        else {
            return false
        }
        return true
    }

    static func enrichedRecord(
        _ nativeRecord: UsageRecord,
        withProxyCostFrom proxyRecord: UsageRecord
    ) -> UsageRecord {
        var record = nativeRecord
        if record.costUSD == nil,
           let proxyCost = proxyRecord.costUSD,
           proxyCost > 0 {
            record.costUSD = proxyCost
        }
        return record
    }

    static func toolFamily(for tool: String) -> String? {
        let value = tool.lowercased()
        if value.contains("claude") { return "claude" }
        if value.contains("codex") { return "codex" }
        if value.contains("gemini") { return "gemini" }
        return nil
    }

    static func areTimestampsClose(_ lhs: String?, _ rhs: String?, seconds: TimeInterval) -> Bool {
        guard let lhs,
              let rhs,
              let lhsDate = parseISO(lhs),
              let rhsDate = parseISO(rhs)
        else {
            return false
        }
        return abs(lhsDate.timeIntervalSince(rhsDate)) <= seconds
    }

    static func modelsCompatible(_ lhs: String, _ rhs: String) -> Bool {
        let left = canonicalModel(lhs)
        let right = canonicalModel(rhs)
        if left == right { return true }
        guard left != "unknown",
              right != "unknown",
              min(left.count, right.count) >= 8
        else {
            return false
        }
        return left.contains(right) || right.contains(left)
    }

    static func canonicalModel(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
    }

    static func usageVectorsClose(_ lhs: TokenUsageCounts, _ rhs: TokenUsageCounts) -> Bool {
        guard tokenValuesClose(lhs.totalTokens, rhs.totalTokens) else { return false }
        let pairs = [
            (lhs.inputTokens, rhs.inputTokens),
            (lhs.outputTokens, rhs.outputTokens),
            (lhs.cacheCreationInputTokens, rhs.cacheCreationInputTokens),
            (lhs.cacheReadInputTokens, rhs.cacheReadInputTokens),
            (lhs.reasoningOutputTokens, rhs.reasoningOutputTokens)
        ]
        return pairs.allSatisfy { pair in
            let left = pair.0
            let right = pair.1
            return left == 0 && right == 0 || tokenValuesClose(left, right)
        }
    }

    static func usageVectorsClose(proxyRecord: UsageRecord, nativeRecord: UsageRecord) -> Bool {
        guard toolFamily(for: proxyRecord.tool) == "codex",
              toolFamily(for: nativeRecord.tool) == "codex"
        else {
            return usageVectorsClose(proxyRecord.usage, nativeRecord.usage)
        }

        let proxy = proxyRecord.usage
        let native = nativeRecord.usage
        guard tokenValuesClose(proxy.outputTokens, native.outputTokens),
              tokenValuesClose(proxy.cacheReadInputTokens, native.cacheReadInputTokens),
              tokenValuesClose(proxy.cacheCreationInputTokens, native.cacheCreationInputTokens)
        else {
            return false
        }

        // Native Codex reports cached input as a subset of input. CC Switch versions
        // have emitted input both inclusive and exclusive of cached input, so compare
        // both canonical interpretations without changing either source's stored data.
        let nativeUncachedInput = max(0, native.inputTokens - native.cacheReadInputTokens)
        let inputMatches = tokenValuesClose(proxy.inputTokens, native.inputTokens)
            || tokenValuesClose(proxy.inputTokens, nativeUncachedInput)
        guard inputMatches else { return false }

        let proxyProcessedCandidates = [
            proxy.inputTokens + proxy.outputTokens,
            proxy.inputTokens + proxy.cacheReadInputTokens + proxy.cacheCreationInputTokens + proxy.outputTokens
        ]
        return proxyProcessedCandidates.contains { tokenValuesClose($0, native.totalTokens) }
    }

    static func tokenValuesClose(_ lhs: Int, _ rhs: Int) -> Bool {
        if lhs == rhs { return true }
        let baseline = max(lhs, rhs)
        guard baseline > 0 else { return true }
        let tolerance = max(4, Int((Double(baseline) * 0.01).rounded(.up)))
        return abs(lhs - rhs) <= tolerance
    }
}
