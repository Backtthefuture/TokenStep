import CryptoKit
import Foundation

extension UsageCollector {
    static func jsonlFiles(under root: URL, modifiedSince cutoffDate: Date? = nil) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
              )
        else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true
            else {
                return nil
            }
            if let cutoffDate,
               let modificationDate = values.contentModificationDate,
               modificationDate < cutoffDate {
                return nil
            }
            return url
        }
    }

    static func cachedRecords(for url: URL, tool: String, cache: CollectorCache) -> [UsageRecord]? {
        guard let metadata = fileMetadata(for: url),
              let fingerprint = contentFingerprint(for: url, size: metadata.size),
              let cached = cache.files[url.path],
              cached.tool == tool,
              cached.size == metadata.size,
              abs(cached.modificationTime - metadata.modificationTime) < 0.001,
              cached.contentFingerprint == fingerprint
        else {
            return nil
        }
        return cached.records
    }

    static func cachedCodexScan(for url: URL, cache: CollectorCache) -> CodexSessionScan? {
        guard let metadata = fileMetadata(for: url),
              let fingerprint = contentFingerprint(for: url, size: metadata.size),
              let cached = cache.files[url.path],
              cached.tool == "Codex",
              cached.size == metadata.size,
              abs(cached.modificationTime - metadata.modificationTime) < 0.001,
              cached.contentFingerprint == fingerprint
        else {
            return nil
        }
        return cached.codexScan
    }

    static func updateCache(
        path: URL,
        tool: String,
        records: [UsageRecord],
        claudeState: ClaudeFileState? = nil,
        cache: inout CollectorCache
    ) {
        guard let metadata = fileMetadata(for: path),
              let fingerprint = contentFingerprint(for: path, size: metadata.size)
        else {
            return
        }
        cache.files[path.path] = CachedUsageFile(
            tool: tool,
            size: metadata.size,
            modificationTime: metadata.modificationTime,
            records: records,
            contentFingerprint: fingerprint,
            claudeState: claudeState
        )
    }

    static func updateCodexCache(
        path: URL,
        scan: CodexSessionScan,
        metadata: (size: UInt64, modificationTime: TimeInterval),
        cache: inout CollectorCache
    ) {
        guard let currentMetadata = fileMetadata(for: path),
              UsageCollector.metadata(metadata, matches: currentMetadata),
              let fingerprint = contentFingerprint(for: path, size: currentMetadata.size),
              let finalMetadata = fileMetadata(for: path),
              UsageCollector.metadata(currentMetadata, matches: finalMetadata)
        else {
            return
        }
        cache.files[path.path] = CachedUsageFile(
            tool: "Codex",
            size: finalMetadata.size,
            modificationTime: finalMetadata.modificationTime,
            records: [],
            codexScan: scan,
            contentFingerprint: fingerprint
        )
    }

    static func fileMetadata(for url: URL) -> (size: UInt64, modificationTime: TimeInterval)? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize,
              let modificationDate = values.contentModificationDate
        else {
            return nil
        }
        return (UInt64(max(0, size)), modificationDate.timeIntervalSince1970)
    }

    static func metadata(
        _ lhs: (size: UInt64, modificationTime: TimeInterval),
        matches rhs: (size: UInt64, modificationTime: TimeInterval)
    ) -> Bool {
        lhs.size == rhs.size && abs(lhs.modificationTime - rhs.modificationTime) < 0.001
    }

    static func contentFingerprint(for url: URL, size: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let chunkSize = 4_096
        var hash: UInt64 = 14_695_981_039_346_656_037
        func include(_ data: Data) {
            for byte in data {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
        }

        do {
            include(withUnsafeBytes(of: size.littleEndian) { Data($0) })
            let leadingCount = min(chunkSize, Int(clamping: size))
            include(try handle.read(upToCount: leadingCount) ?? Data())
            if size > UInt64(leadingCount) {
                let trailingCount = min(chunkSize, Int(clamping: size))
                try handle.seek(toOffset: size - UInt64(trailingCount))
                include(try handle.read(upToCount: trailingCount) ?? Data())
            }
            return String(format: "%016llx", hash)
        } catch {
            return nil
        }
    }

    static func fullContentFingerprint(for url: URL, size: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        hasher.update(data: withUnsafeBytes(of: size.littleEndian) { Data($0) })
        var remaining = size
        do {
            while remaining > 0 {
                let requested = min(1_048_576, Int(clamping: remaining))
                guard let chunk = try autoreleasepool(invoking: {
                    try handle.read(upToCount: requested)
                }), !chunk.isEmpty else {
                    return nil
                }
                hasher.update(data: chunk)
                remaining -= UInt64(chunk.count)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch {
            return nil
        }
    }

    static func loadCache() -> CollectorCacheLoad {
        loadCache(at: AppPaths.collectorCacheJSON)
    }

    static func loadCache(at url: URL) -> CollectorCacheLoad {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CollectorCache.self, from: data)
        else {
            return CollectorCacheLoad(cache: CollectorCache(), recalibratedFromRevision: nil)
        }
        guard decoded.version == CollectorCache.currentVersion else {
            return CollectorCacheLoad(
                cache: CollectorCache(),
                recalibratedFromRevision: decoded.version < CollectorCache.currentVersion ? decoded.version : nil
            )
        }
        guard TokenStepClock.matchesCurrent(decoded.timeZone) else {
            return CollectorCacheLoad(cache: CollectorCache(), recalibratedFromRevision: nil)
        }
        return CollectorCacheLoad(cache: decoded, recalibratedFromRevision: nil)
    }

    static func saveCache(_ cache: CollectorCache) {
        saveCache(cache, to: AppPaths.collectorCacheJSON)
    }

    static func loadCurrentCache(at url: URL) -> CollectorCache {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(CollectorCache.self, from: data),
              cache.version == CollectorCache.currentVersion,
              TokenStepClock.matchesCurrent(cache.timeZone)
        else {
            return CollectorCache()
        }
        return cache
    }

    static func saveCache(_ cache: CollectorCache, to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(cache)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let existingSize = (attributes[.size] as? NSNumber)?.intValue,
               existingSize == data.count,
               let existing = try? Data(contentsOf: url),
               existing == data {
                return
            }
            try data.write(to: url, options: .atomic)
        } catch {
            // Cache misses should never prevent the app from showing fresh usage.
        }
    }

    static func sourceFileCutoffDate(historyDays: Int) -> Date? {
        calendar.date(byAdding: .day, value: -max(7, historyDays + 1), to: Date())
    }

    static func recordsInHistoryWindow(
        _ records: [UsageRecord],
        historyDays: Int,
        now: Date
    ) -> [UsageRecord] {
        let inclusiveDays = max(1, historyDays)
        let today = calendar.startOfDay(for: now)
        guard let firstDay = calendar.date(
            byAdding: .day,
            value: -(inclusiveDays - 1),
            to: today
        ) else {
            return records
        }
        let firstDayString = dayFormatter.string(from: firstDay)
        let todayString = dayFormatter.string(from: today)
        return records.filter {
            $0.date >= firstDayString && $0.date <= todayString
        }
    }
}
