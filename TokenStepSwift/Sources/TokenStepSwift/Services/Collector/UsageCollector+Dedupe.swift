import Foundation

extension UsageCollector {
    /// Dedupe grouping key: `isSameDedupeDomain` requires an exact date string and
    /// tool-family match, so candidate lookups can be bucketed by this key without
    /// changing which pairs are ever considered.
    fileprivate struct DedupeDomain: Hashable {
        let date: String
        let family: String
    }

    /// Session-pass lookup key: `hasSessionIdentityMatch` requires equal non-empty
    /// session IDs inside the same domain, so session candidates can be bucketed by
    /// this key too.
    fileprivate struct DedupeSessionKey: Hashable {
        let domain: DedupeDomain
        let sessionID: String
    }

    /// Session identity requires both timestamps to sit inside this window; the
    /// candidate lookup and the predicate must agree on the value.
    fileprivate static let sessionEpochTolerance: TimeInterval = 10

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

        // Index native records once instead of scanning every (date, family) bucket
        // pairwise. Both passes below only walk pairs that satisfy a cheap necessary
        // condition of their predicate — a shared request/response identifier for the
        // exact pass, or the same session ID inside the ±10 s epoch window for the
        // session pass — so the lookups return exactly the pairs the per-bucket
        // pairwise scan compared. That scan was O(P*N) inside a single heavy day,
        // which alone exceeded the helper's collect budget once a day held thousands
        // of native and proxy records.
        var nativeIdentifiersByDomain: [DedupeDomain: [String: [Int]]] = [:]
        var nativeSessionsByDomain: [DedupeSessionKey: [(epoch: TimeInterval, index: Int)]] = [:]
        for nativeIndex in nativeRecords.indices {
            let record = nativeRecords[nativeIndex]
            guard record.source != .ccSwitchProxy,
                  let family = toolFamily(for: record.tool) else { continue }
            let domain = DedupeDomain(date: record.date, family: family)
            for identifier in Set([record.requestID, record.responseID].compactMap(nonEmptyString)) {
                nativeIdentifiersByDomain[domain, default: [:]][identifier, default: []].append(nativeIndex)
            }
            if let sessionID = nonEmptyString(record.sessionID),
               let timestamp = record.timestamp,
               let epoch = parseISO(timestamp)?.timeIntervalSince1970 {
                nativeSessionsByDomain[
                    DedupeSessionKey(domain: domain, sessionID: sessionID),
                    default: []
                ].append((epoch: epoch, index: nativeIndex))
            }
        }
        for key in nativeSessionsByDomain.keys {
            nativeSessionsByDomain[key]?.sort { $0.epoch < $1.epoch }
        }

        // Parse each distinct timestamp string once. The previous code re-parsed
        // both sides of every candidate pair through NSISO8601DateFormatter,
        // which dominated collection CPU time as record counts grew.
        var epochByTimestamp: [String: TimeInterval?] = [:]
        func cachedEpoch(_ value: String?) -> TimeInterval? {
            guard let value else { return nil }
            if let cached = epochByTimestamp[value] { return cached }
            let epoch = parseISO(value)?.timeIntervalSince1970
            epochByTimestamp[value] = epoch
            return epoch
        }

        // Shared-identifier lookup: every native record whose request/response IDs
        // intersect the proxy's is a candidate; the predicate below re-checks both
        // halves so the accepted pairs stay identical to the pairwise scan.
        func exactNativeCandidates(forProxyAt proxyIndex: Int) -> [Int] {
            let record = proxyRecords[proxyIndex]
            guard let family = toolFamily(for: record.tool) else { return [] }
            let domain = DedupeDomain(date: record.date, family: family)
            guard let identifiersByID = nativeIdentifiersByDomain[domain] else { return [] }
            var seen = Set<Int>()
            var candidates: [Int] = []
            for identifier in [record.requestID, record.responseID].compactMap(nonEmptyString) {
                for nativeIndex in identifiersByID[identifier] ?? [] where seen.insert(nativeIndex).inserted {
                    candidates.append(nativeIndex)
                }
            }
            return candidates
        }

        func firstEntry(atOrAfter entries: [(epoch: TimeInterval, index: Int)], epoch: TimeInterval) -> Int {
            var low = 0
            var high = entries.count
            while low < high {
                let mid = (low + high) / 2
                if entries[mid].epoch < epoch {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            return low
        }

        func firstEntry(after entries: [(epoch: TimeInterval, index: Int)], epoch: TimeInterval) -> Int {
            var low = 0
            var high = entries.count
            while low < high {
                let mid = (low + high) / 2
                if entries[mid].epoch <= epoch {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            return low
        }

        // Same-session lookup: native records sharing the proxy's session ID whose
        // timestamp falls inside the ±10 s window are candidates; the session pass
        // runs after the exact pass, so already-matched natives are excluded here
        // just like the previous remainingNativeCandidates did.
        func sessionNativeCandidates(forProxyAt proxyIndex: Int) -> [Int] {
            let record = proxyRecords[proxyIndex]
            guard let family = toolFamily(for: record.tool),
                  let sessionID = nonEmptyString(record.sessionID),
                  let proxyEpoch = cachedEpoch(record.timestamp)
            else { return [] }
            let key = DedupeSessionKey(
                domain: DedupeDomain(date: record.date, family: family),
                sessionID: sessionID
            )
            guard let entries = nativeSessionsByDomain[key], !entries.isEmpty else { return [] }
            let lower = firstEntry(atOrAfter: entries, epoch: proxyEpoch - sessionEpochTolerance)
            let upper = firstEntry(after: entries, epoch: proxyEpoch + sessionEpochTolerance)
            var candidates: [Int] = []
            for position in lower..<upper {
                let nativeIndex = entries[position].index
                guard !matchedNativeIndices.contains(nativeIndex) else { continue }
                candidates.append(nativeIndex)
            }
            return candidates
        }

        let exactPairs = uniqueDedupePairs(
            proxyIndices: deduplicableProxyIndices,
            nativeCandidatesFor: exactNativeCandidates
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
        let sessionPairs = uniqueDedupePairs(
            proxyIndices: remainingProxyIndices,
            nativeCandidatesFor: sessionNativeCandidates
        ) { proxyIndex, nativeIndex in
            isSameDedupeDomain(
                proxyRecord: proxyRecords[proxyIndex],
                nativeRecord: nativeRecords[nativeIndex]
            ) && hasSessionIdentityMatch(
                proxyRecord: proxyRecords[proxyIndex],
                nativeRecord: nativeRecords[nativeIndex],
                proxyEpoch: cachedEpoch(proxyRecords[proxyIndex].timestamp),
                nativeEpoch: cachedEpoch(nativeRecords[nativeIndex].timestamp)
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
        nativeCandidatesFor proxyCandidates: (Int) -> [Int],
        matches: (Int, Int) -> Bool
    ) -> [(proxy: Int, native: Int)] {
        var nativeCandidatesByProxy: [Int: [Int]] = [:]
        var proxyCandidateCountByNative: [Int: Int] = [:]
        for proxyIndex in proxyIndices {
            let candidates = proxyCandidates(proxyIndex).filter { matches(proxyIndex, $0) }
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

    static func hasSessionIdentityMatch(
        proxyRecord: UsageRecord,
        nativeRecord: UsageRecord,
        proxyEpoch: TimeInterval?,
        nativeEpoch: TimeInterval?
    ) -> Bool {
        guard let proxySessionID = nonEmptyString(proxyRecord.sessionID),
              let nativeSessionID = nonEmptyString(nativeRecord.sessionID),
              proxySessionID == nativeSessionID,
              epochsClose(proxyEpoch, nativeEpoch, seconds: sessionEpochTolerance),
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

    static func epochsClose(_ lhs: TimeInterval?, _ rhs: TimeInterval?, seconds: TimeInterval) -> Bool {
        guard let lhs,
              let rhs
        else {
            return false
        }
        return abs(lhs - rhs) <= seconds
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
