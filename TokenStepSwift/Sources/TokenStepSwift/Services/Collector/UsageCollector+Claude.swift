import Foundation

extension UsageCollector {
    static func collectClaudeCode(
        cache: inout CollectorCache,
        livePaths: inout Set<String>,
        rootURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true),
        modifiedSince cutoffDate: Date?,
        forceFullValidation: Bool = false
    ) -> CollectorResult {
        let root = rootURL
        let paths = jsonlFiles(under: root, modifiedSince: cutoffDate)
        var records: [UsageRecord] = []

        for path in paths.sorted(by: { $0.path < $1.path }) {
            livePaths.insert(path.path)
            if let cached = cachedRecords(for: path, tool: "Claude Code", cache: cache) {
                records.append(contentsOf: cached)
                continue
            }
            guard FileManager.default.isReadableFile(atPath: path.path) else { continue }

            // Active sessions only ever grow, so resume after the last complete line
            // instead of re-reading the whole transcript on every collection.
            var state = forceFullValidation
                ? ClaudeFileState()
                : resumableClaudeState(for: path, cache: cache) ?? ClaudeFileState()
            let scan = scanClaudeFile(at: path, state: &state)
            records.append(contentsOf: scan.records)
            updateCache(
                path: path,
                tool: "Claude Code",
                records: scan.records,
                claudeState: scan.stateIsComplete ? state : nil,
                cache: &cache
            )
        }

        return CollectorResult(
            records: records,
            source: SourceInfo(
                status: records.isEmpty ? "missing" : "ok",
                files: paths.count,
                records: records.count
            )
        )
    }

    static func resumableClaudeState(for path: URL, cache: CollectorCache) -> ClaudeFileState? {
        guard let cached = cache.files[path.path],
              cached.tool == "Claude Code",
              let state = cached.claudeState,
              let metadata = fileMetadata(for: path),
              metadata.size >= state.processedBytes,
              let prefix = contentFingerprint(for: path, size: state.processedBytes),
              prefix == state.prefixFingerprint
        else {
            return nil
        }
        return state
    }

    /// Reads complete lines after `state.processedBytes` into `state`. A trailing line
    /// that is still being written is counted in the returned records but not stored
    /// in `state`, so the next scan reads it again once it is complete.
    static func scanClaudeFile(
        at path: URL,
        state: inout ClaudeFileState
    ) -> (records: [UsageRecord], stateIsComplete: Bool) {
        var lineNumber = state.usageLineCount
        var candidates = state.candidates
        let processedBytes: UInt64?
        do {
            processedBytes = try forEachCompleteLine(
                in: path,
                fromOffset: state.processedBytes,
                matchingAny: ["usage"]
            ) { line in
                autoreleasepool {
                    lineNumber += 1
                    mergeClaudeLine(line, path: path, lineNumber: lineNumber, into: &candidates)
                }
            }
        } catch {
            processedBytes = nil
        }
        guard let processedBytes else {
            return (orderedClaudeRecords(candidates), false)
        }

        state.processedBytes = processedBytes
        state.usageLineCount = lineNumber
        state.candidates = candidates
        state.prefixFingerprint = contentFingerprint(for: path, size: processedBytes)

        if let trailing = unterminatedTail(of: path, from: processedBytes),
           let line = String(data: trailing, encoding: .utf8),
           line.contains("usage") {
            mergeClaudeLine(line, path: path, lineNumber: lineNumber + 1, into: &candidates)
        }
        return (orderedClaudeRecords(candidates), state.prefixFingerprint != nil)
    }

    /// File order keeps downstream floating-point cost sums identical no matter
    /// how the candidate dictionary happens to iterate.
    static func orderedClaudeRecords(_ candidates: [String: ClaudeUsageCandidate]) -> [UsageRecord] {
        candidates.values
            .sorted { $0.lineNumber < $1.lineNumber }
            .map(\.record)
    }

    static func mergeClaudeLine(
        _ line: String,
        path: URL,
        lineNumber: Int,
        into candidates: inout [String: ClaudeUsageCandidate]
    ) {
        guard let obj = jsonObject(line),
              obj["type"] as? String == "assistant",
              let message = obj["message"] as? [String: Any]
        else {
            return
        }

        let usage = normalizeUsage(message["usage"] as? [String: Any])
        guard usage.totalTokens > 0,
              let timestamp = obj["timestamp"] as? String,
              let day = dayString(fromISO: timestamp)
        else {
            return
        }

        let identity = claudeIdentity(obj: obj, message: message, path: path, lineNumber: lineNumber)
        let candidate = ClaudeUsageCandidate(
            date: day,
            timestamp: timestamp,
            model: modelKey(message["model"] as? String),
            usage: usage,
            hasStopReason: hasStopReason(message["stop_reason"]),
            lineNumber: lineNumber,
            requestID: identity.requestID,
            responseID: identity.responseID,
            sessionID: identity.sessionID,
            sourcePath: path.path
        )
        if let existing = candidates[identity.deduplicationKey],
           !candidate.isPreferred(over: existing) {
            return
        }
        candidates[identity.deduplicationKey] = candidate
    }

    static func unterminatedTail(of path: URL, from offset: UInt64) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: path) else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.read(upToCount: maxRelevantLineBytes + 1),
              !data.isEmpty,
              data.count <= maxRelevantLineBytes,
              !data.contains(0x0A)
        else {
            return nil
        }
        return data
    }

    static func claudeIdentity(
        obj: [String: Any],
        message: [String: Any],
        path: URL,
        lineNumber: Int
    ) -> ClaudeIdentity {
        let responseID = nonEmptyString(message["id"] as? String)
        let requestID = [
            obj["requestId"] as? String,
            obj["request_id"] as? String,
            message["requestId"] as? String,
            message["request_id"] as? String
        ].compactMap(nonEmptyString).first
        let sessionID = [
            obj["sessionId"] as? String,
            obj["session_id"] as? String,
            obj["sessionID"] as? String
        ].compactMap(nonEmptyString).first
        let uuid = nonEmptyString(obj["uuid"] as? String)

        let deduplicationKey: String
        if let responseID {
            deduplicationKey = "response:\(responseID)"
        } else if let requestID {
            deduplicationKey = "request:\(requestID)"
        } else if let uuid {
            deduplicationKey = "uuid:\(uuid)"
        } else {
            deduplicationKey = "line:\(path.path):\(lineNumber)"
        }
        return ClaudeIdentity(
            deduplicationKey: deduplicationKey,
            requestID: requestID,
            responseID: responseID,
            sessionID: sessionID
        )
    }

    static func hasStopReason(_ value: Any?) -> Bool {
        guard let text = value as? String else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
