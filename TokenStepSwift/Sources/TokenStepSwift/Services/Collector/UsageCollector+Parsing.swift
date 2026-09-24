import Foundation

extension UsageCollector {
    static func forEachLine(in url: URL, matchingAny markers: [String] = [], _ body: (String) -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let newline = Data([0x0A])
        let markerData = markers.map { Data($0.utf8) }
        var buffer = Data()
        buffer.reserveCapacity(128 * 1024)
        var discardingOversizedLine = false

        func processLine(_ lineData: Data) {
            guard lineMatches(lineData, markers: markerData),
                  let line = String(data: lineData, encoding: .utf8),
                  !line.isEmpty
            else {
                return
            }
            body(line)
        }

        while try autoreleasepool(invoking: { () throws -> Bool in
            guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else {
                return false
            }
            buffer.append(chunk)

            var consumedEnd = buffer.startIndex
            var lineStart = buffer.startIndex
            var searchRange = buffer.startIndex..<buffer.endIndex
            while let range = buffer.range(of: newline, options: [], in: searchRange) {
                let lineEnd = range.lowerBound
                if discardingOversizedLine {
                    discardingOversizedLine = false
                } else if lineEnd > lineStart {
                    let lineData = buffer.subdata(in: lineStart..<lineEnd)
                    processLine(lineData)
                }
                consumedEnd = range.upperBound
                lineStart = range.upperBound
                searchRange = lineStart..<buffer.endIndex
            }

            if consumedEnd > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<consumedEnd)
            }

            if buffer.count > maxRelevantLineBytes {
                discardingOversizedLine = true
                buffer.removeAll(keepingCapacity: true)
            }
            return true
        }) {}

        if !discardingOversizedLine,
           !buffer.isEmpty,
           buffer.count <= maxRelevantLineBytes {
            processLine(buffer)
        }
    }

    @discardableResult
    static func forEachCompleteLine(
        in url: URL,
        fromOffset offset: UInt64,
        matchingAny markers: [String] = [],
        _ body: (String) -> Void
    ) throws -> UInt64 {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)

        let newline = Data([0x0A])
        let markerData = markers.map { Data($0.utf8) }
        var buffer = Data()
        buffer.reserveCapacity(128 * 1024)
        var discardingOversizedLine = false
        var discardedIncompleteBytes = 0
        var processedSize = offset

        func processLine(_ lineData: Data) {
            guard lineMatches(lineData, markers: markerData),
                  let line = String(data: lineData, encoding: .utf8),
                  !line.isEmpty
            else {
                return
            }
            body(line)
        }

        while try autoreleasepool(invoking: { () throws -> Bool in
            guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else {
                return false
            }
            buffer.append(chunk)

            var consumedEnd = buffer.startIndex
            var lineStart = buffer.startIndex
            var searchRange = buffer.startIndex..<buffer.endIndex
            while let range = buffer.range(of: newline, options: [], in: searchRange) {
                let lineEnd = range.lowerBound
                if discardingOversizedLine {
                    discardingOversizedLine = false
                } else if lineEnd > lineStart {
                    processLine(buffer.subdata(in: lineStart..<lineEnd))
                }
                consumedEnd = range.upperBound
                lineStart = range.upperBound
                searchRange = lineStart..<buffer.endIndex
            }

            if consumedEnd > buffer.startIndex {
                let consumedBytes = buffer.distance(from: buffer.startIndex, to: consumedEnd)
                processedSize += UInt64(discardedIncompleteBytes + consumedBytes)
                discardedIncompleteBytes = 0
                buffer.removeSubrange(buffer.startIndex..<consumedEnd)
            }

            if buffer.count > maxRelevantLineBytes {
                discardingOversizedLine = true
                discardedIncompleteBytes += buffer.count
                buffer.removeAll(keepingCapacity: true)
            }
            return true
        }) {}

        return processedSize
    }

    static func lineMatches(_ data: Data, markers: [Data]) -> Bool {
        markers.isEmpty || markers.contains { data.range(of: $0) != nil }
    }

    static func jsonObject(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return nil
        }
        return dictionary
    }

    static func normalizeUsage(_ raw: [String: Any]?) -> TokenUsageCounts {
        guard let raw else { return TokenUsageCounts() }
        func value(_ keys: [String]) -> Int {
            for key in keys where raw.keys.contains(key) {
                return max(0, integerValue(raw[key] as Any))
            }
            return 0
        }

        let explicitTotal = ["total_tokens", "total"].first(where: { raw.keys.contains($0) })
            .map { max(0, integerValue(raw[$0] as Any)) }
        return canonicalUsageCounts(
            rawInputTokens: value(["input_tokens", "input"]),
            outputTokens: value(["output_tokens", "output"]),
            cacheCreationInputTokens: value(["cache_creation_input_tokens"]),
            cacheReadInputTokens: value(["cache_read_input_tokens", "cached_input_tokens", "cached"]),
            reasoningOutputTokens: value(["reasoning_output_tokens", "reasoning_tokens", "thoughts"]),
            inputIncludesCachedTokens: false,
            explicitTotalTokens: explicitTotal
        )
    }

    static func normalizeCodexUsage(_ raw: [String: Any]) -> TokenUsageCounts {
        func value(_ keys: [String]) -> Int {
            for key in keys where raw.keys.contains(key) {
                return max(0, integerValue(raw[key] as Any))
            }
            return 0
        }

        let input = value(["input_tokens", "input"])
        let output = value(["output_tokens", "output"])
        let cached = value(["cached_input_tokens", "cache_read_input_tokens", "cached"])
        let reasoning = value(["reasoning_output_tokens", "reasoning_tokens", "thoughts"])
        let explicitTotal = ["total_tokens", "total"].first(where: { raw.keys.contains($0) })
            .map { max(0, integerValue(raw[$0] as Any)) }
        return canonicalUsageCounts(
            rawInputTokens: input,
            outputTokens: output,
            cacheCreationInputTokens: value(["cache_creation_input_tokens", "cache_write_input_tokens"]),
            cacheReadInputTokens: cached,
            reasoningOutputTokens: reasoning,
            inputIncludesCachedTokens: true,
            explicitTotalTokens: explicitTotal,
            explicitTotalIsAuthoritative: true
        )
    }

    static func canonicalUsageCounts(
        rawInputTokens: Int,
        outputTokens: Int,
        cacheCreationInputTokens: Int = 0,
        cacheReadInputTokens: Int = 0,
        reasoningOutputTokens: Int = 0,
        inputIncludesCachedTokens: Bool,
        explicitTotalTokens: Int? = nil,
        explicitTotalIsAuthoritative: Bool = false
    ) -> TokenUsageCounts {
        let rawInput = max(0, rawInputTokens)
        let output = max(0, outputTokens)
        let cacheCreation = max(0, cacheCreationInputTokens)
        let cacheRead = max(0, cacheReadInputTokens)
        let reasoning = max(0, reasoningOutputTokens)
        let input = rawInput + (inputIncludesCachedTokens ? 0 : cacheCreation + cacheRead)
        let derivedTotal = input + output
        let explicitTotal = max(0, explicitTotalTokens ?? 0)
        let total = explicitTotalIsAuthoritative && explicitTotal > 0
            ? explicitTotal
            : (derivedTotal > 0 ? derivedTotal : explicitTotal)
        return TokenUsageCounts(
            inputTokens: input,
            outputTokens: output,
            cacheCreationInputTokens: cacheCreation,
            cacheReadInputTokens: cacheRead,
            reasoningOutputTokens: reasoning,
            totalTokens: total
        )
    }

    static func integerValue(_ value: Any) -> Int {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    static func doubleValue(_ value: Any) -> Double {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) ?? 0 }
        return 0
    }

    static func nonEmptyString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func dayString(fromISO value: String) -> String? {
        guard let date = parseISO(value) else { return nil }
        return dayFormatter.string(from: date)
    }

    static func dayString(for event: CodexTokenEvent) -> String? {
        if let timestamp = event.timestampEpoch {
            return dayFormatter.string(from: Date(timeIntervalSince1970: timestamp))
        }
        return event.timestamp.flatMap(dayString(fromISO:))
    }

    static func hour(fromEpoch value: TimeInterval) -> Int {
        calendar.component(.hour, from: Date(timeIntervalSince1970: value))
    }

    static func hour(fromISO value: String?) -> Int? {
        guard let value, let date = parseISO(value) else { return nil }
        return calendar.component(.hour, from: date)
    }

    static func dayString(fromEpoch value: Any?) -> String? {
        guard let seconds = epochSeconds(value) else { return nil }
        return dayFormatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    static func isoString(fromEpoch value: Any?) -> String? {
        guard let seconds = epochSeconds(value) else { return nil }
        return isoFormatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    static func epochSeconds(_ value: Any?) -> Double? {
        var seconds: Double
        if let int = value as? Int {
            seconds = Double(int)
        } else if let double = value as? Double {
            seconds = double
        } else if let string = value as? String, let parsed = Double(string) {
            seconds = parsed
        } else {
            return nil
        }
        if seconds > 10_000_000_000 {
            seconds /= 1_000
        }
        return seconds
    }

    static func parseISO(_ value: String) -> Date? {
        if let date = isoFormatterWithFractional.date(from: value) {
            return date
        }
        return isoFormatter.date(from: value)
    }

    static func modelKey(_ model: String?) -> String {
        let value = (model ?? "unknown").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "unknown" : value
    }

    static func sqliteJSONRows(database: URL, query: String) -> [[String: Any]]? {
        SQLiteReadonly.jsonRows(database: database, query: query)
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        return calendar
    }()

    static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
