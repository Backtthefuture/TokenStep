import Foundation
import SQLite3

enum CodexIncrementalStoreError: LocalizedError {
    case sqlite(String)
    case corruptPayload(String)
    case unstableSource(String)
    case incompleteCache(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case let .sqlite(message):
            return "Incremental cache error: \(message)"
        case let .corruptPayload(context):
            return "Incremental cache payload is corrupt: \(context)"
        case .unstableSource:
            return "A Codex session changed while it was being collected."
        case let .incompleteCache(expected, actual):
            return "Incremental cache is incomplete (expected \(expected), got \(actual))."
        }
    }

    var shouldRebuildCache: Bool {
        switch self {
        case .corruptPayload:
            return true
        case let .sqlite(message):
            let normalized = message.lowercased()
            return normalized.contains("not a database")
                || normalized.contains("database disk image is malformed")
                || normalized.contains("database malformed")
        case .incompleteCache:
            return true
        case .unstableSource:
            return false
        }
    }
}

final class CodexIncrementalStore {
    static let schemaVersion: Int32 = 6
    static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private var database: OpaquePointer?
    private var stagingTransactionActive = false

    static func discardDatabase(at url: URL) {
        let fileManager = FileManager.default
        for path in [url.path, url.path + "-wal", url.path + "-shm"] {
            guard fileManager.fileExists(atPath: path) else { continue }
            try? fileManager.removeItem(atPath: path)
        }
    }

    init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let database { sqlite3_close(database) }
            database = nil
            throw CodexIncrementalStoreError.sqlite(message)
        }
        do {
            sqlite3_busy_timeout(database, 2_000)
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=NORMAL")
            try migrateIfNeeded()
            try resetIfTimeZoneChanged()
        } catch {
            if let database {
                sqlite3_close(database)
            }
            database = nil
            throw error
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func metadataByPath() throws -> [String: StoredCodexSessionMetadata] {
        let statement = try prepare(
            """
            SELECT path, size, modification_time, fingerprint,
                   validation_fingerprint, session_id
            FROM codex_sessions
            """
        )
        defer { sqlite3_finalize(statement) }
        var result = [String: StoredCodexSessionMetadata]()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let path = columnText(statement, index: 0),
                  let fingerprint = columnText(statement, index: 3),
                  let sessionID = columnText(statement, index: 5)
            else { continue }
            result[path] = StoredCodexSessionMetadata(
                size: UInt64(max(0, sqlite3_column_int64(statement, 1))),
                modificationTime: sqlite3_column_double(statement, 2),
                fingerprint: fingerprint,
                validationFingerprint: columnText(statement, index: 4),
                sessionID: sessionID
            )
        }
        try checkFinalStep(statement)
        return result
    }

    func childPaths(parentSessionID: String) throws -> [String] {
        let statement = try prepare(
            "SELECT path FROM codex_sessions WHERE parent_session_id = ? ORDER BY path"
        )
        defer { sqlite3_finalize(statement) }
        bind(parentSessionID, to: statement, index: 1)
        var result = [String]()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let path = columnText(statement, index: 0) {
                result.append(path)
            }
        }
        try checkFinalStep(statement)
        return result
    }

    func childPaths(
        parentSessionID: String,
        createdAtOnOrAfter timestamp: TimeInterval
    ) throws -> [String] {
        let statement = try prepare(
            """
            SELECT path FROM codex_sessions
            WHERE parent_session_id = ?
              AND (created_at_epoch IS NULL OR created_at_epoch >= ?)
            ORDER BY path
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(parentSessionID, to: statement, index: 1)
        sqlite3_bind_double(statement, 2, timestamp)
        var result = [String]()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let path = columnText(statement, index: 0) {
                result.append(path)
            }
        }
        try checkFinalStep(statement)
        return result
    }

    func anchors(sessionID: String) throws -> [CodexAnchor]? {
        let statement = try prepare(
            "SELECT anchors FROM codex_sessions WHERE session_id = ? ORDER BY path LIMIT 1"
        )
        defer { sqlite3_finalize(statement) }
        bind(sessionID, to: statement, index: 1)
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW,
              let data = columnData(statement, index: 0)
        else {
            throw currentError()
        }
        return try decode([CodexAnchor].self, from: data, context: "anchors")
    }

    func session(path: String) throws -> CodexCachedSession? {
        let statement = try prepare(
            """
            SELECT size, modification_time, fingerprint, validation_fingerprint,
                   session_id, created_at_epoch, parent_session_id, anchors,
                   records, COALESCE(summary_records, records), cursor, diagnostics
            FROM codex_sessions WHERE path = ? LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(path, to: statement, index: 1)
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW,
              let fingerprint = columnText(statement, index: 2),
              let sessionID = columnText(statement, index: 4),
              let anchorsData = columnData(statement, index: 7),
              let recordsData = columnData(statement, index: 8),
              let summaryData = columnData(statement, index: 9),
              let cursorData = columnData(statement, index: 10),
              let diagnosticsData = columnData(statement, index: 11)
        else { return nil }
        return CodexCachedSession(
            path: path,
            size: UInt64(max(0, sqlite3_column_int64(statement, 0))),
            modificationTime: sqlite3_column_double(statement, 1),
            fingerprint: fingerprint,
            validationFingerprint: columnText(statement, index: 3),
            sessionID: sessionID,
            createdAtEpoch: sqlite3_column_type(statement, 5) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 5),
            parentSessionID: columnText(statement, index: 6),
            anchors: try decode([CodexAnchor].self, from: anchorsData, context: "session anchors"),
            records: try decode([UsageRecord].self, from: recordsData, context: "session records"),
            summaryRecords: try decode([UsageRecord].self, from: summaryData, context: "session summaries"),
            cursor: try decode(CodexSessionCursor.self, from: cursorData, context: "session cursor"),
            diagnostics: try decode(
                CodexCollectionDiagnostics.self,
                from: diagnosticsData,
                context: "session diagnostics"
            )
        )
    }

    func beginStaging() throws {
        guard !stagingTransactionActive else {
            throw CodexIncrementalStoreError.sqlite("staging transaction already active")
        }
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try execute("DELETE FROM codex_staged_scans")
            try execute("DELETE FROM codex_staged_sessions")
            stagingTransactionActive = true
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func abortStaging() {
        guard stagingTransactionActive else { return }
        try? execute("ROLLBACK")
        stagingTransactionActive = false
    }

    func updateValidationFingerprint(_ fingerprint: String, path: String) throws {
        guard stagingTransactionActive else {
            throw CodexIncrementalStoreError.sqlite("staging transaction is not active")
        }
        let statement = try prepare(
            "UPDATE codex_sessions SET validation_fingerprint = ? WHERE path = ?"
        )
        defer { sqlite3_finalize(statement) }
        bind(fingerprint, to: statement, index: 1)
        bind(path, to: statement, index: 2)
        try requireDone(statement)
    }

    func stage(
        scan item: PendingCodexSession,
        anchors: [CodexAnchor],
        createdAtEpoch: TimeInterval?
    ) throws {
        guard stagingTransactionActive else {
            throw CodexIncrementalStoreError.sqlite("staging transaction is not active")
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let anchors = try encoder.encode(anchors)
        let scan = try encoder.encode(item.scan)
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO codex_staged_scans (
                path, size, modification_time, fingerprint, validation_fingerprint,
                session_id, created_at_epoch, parent_session_id, anchors, scan
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(item.path.path, to: statement, index: 1)
        sqlite3_bind_int64(statement, 2, sqlite3_int64(item.metadata.size))
        sqlite3_bind_double(statement, 3, item.metadata.modificationTime)
        bind(item.fingerprint, to: statement, index: 4)
        bind(item.validationFingerprint, to: statement, index: 5)
        bind(item.scan.canonicalSessionID, to: statement, index: 6)
        bind(createdAtEpoch, to: statement, index: 7)
        bind(item.scan.parentSessionID, to: statement, index: 8)
        bind(anchors, to: statement, index: 9)
        bind(scan, to: statement, index: 10)
        try requireDone(statement)
    }

    func stagedScanPaths() throws -> [String] {
        let statement = try prepare("SELECT path FROM codex_staged_scans ORDER BY path")
        defer { sqlite3_finalize(statement) }
        var paths = [String]()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let path = columnText(statement, index: 0) {
                paths.append(path)
            }
        }
        try checkFinalStep(statement)
        return paths
    }

    func stagedScan(path: String) throws -> PendingCodexSession? {
        let statement = try prepare(
            """
            SELECT size, modification_time, fingerprint, validation_fingerprint, scan
            FROM codex_staged_scans WHERE path = ? LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(path, to: statement, index: 1)
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW,
              let fingerprint = columnText(statement, index: 2),
              let scanData = columnData(statement, index: 4)
        else { throw currentError() }
        return PendingCodexSession(
            path: URL(fileURLWithPath: path),
            metadata: (
                size: UInt64(max(0, sqlite3_column_int64(statement, 0))),
                modificationTime: sqlite3_column_double(statement, 1)
            ),
            fingerprint: fingerprint,
            validationFingerprint: columnText(statement, index: 3),
            scan: try decode(CodexSessionScan.self, from: scanData, context: "staged scan")
        )
    }

    func stagedAnchors(sessionID: String) throws -> [CodexAnchor]? {
        for table in ["codex_staged_scans", "codex_staged_sessions"] {
            let statement = try prepare(
                "SELECT anchors FROM \(table) WHERE session_id = ? ORDER BY path LIMIT 1"
            )
            defer { sqlite3_finalize(statement) }
            bind(sessionID, to: statement, index: 1)
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { continue }
            guard status == SQLITE_ROW,
                  let data = columnData(statement, index: 0)
            else { throw currentError() }
            return try decode([CodexAnchor].self, from: data, context: "staged anchors")
        }
        return nil
    }

    func stage(session: CodexCachedSession) throws {
        guard stagingTransactionActive else {
            throw CodexIncrementalStoreError.sqlite("staging transaction is not active")
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let anchors = try encoder.encode(session.anchors)
        let records = try encoder.encode(session.records)
        let summaryRecords = try encoder.encode(session.summaryRecords)
        let cursor = try encoder.encode(session.cursor)
        let diagnostics = try encoder.encode(session.diagnostics)
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO codex_staged_sessions (
                path, size, modification_time, fingerprint, validation_fingerprint,
                session_id, created_at_epoch, parent_session_id, anchors, records,
                summary_records, record_count, cursor, diagnostics
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(session.path, to: statement, index: 1)
        sqlite3_bind_int64(statement, 2, sqlite3_int64(session.size))
        sqlite3_bind_double(statement, 3, session.modificationTime)
        bind(session.fingerprint, to: statement, index: 4)
        bind(session.validationFingerprint, to: statement, index: 5)
        bind(session.sessionID, to: statement, index: 6)
        bind(session.createdAtEpoch, to: statement, index: 7)
        bind(session.parentSessionID, to: statement, index: 8)
        bind(anchors, to: statement, index: 9)
        bind(records, to: statement, index: 10)
        bind(summaryRecords, to: statement, index: 11)
        sqlite3_bind_int64(statement, 12, sqlite3_int64(session.records.count))
        bind(cursor, to: statement, index: 13)
        bind(diagnostics, to: statement, index: 14)
        try requireDone(statement)
    }

    func commitStaged(deletedPaths: Set<String>) throws {
        guard stagingTransactionActive else {
            throw CodexIncrementalStoreError.sqlite("staging transaction is not active")
        }
        do {
            let stagedCount = try stagedSessionCount()
            let stagedPayloadBytes = try stagedSessionPayloadBytes()
            if !deletedPaths.isEmpty {
                let statement = try prepare("DELETE FROM codex_sessions WHERE path = ?")
                defer { sqlite3_finalize(statement) }
                for path in deletedPaths {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    bind(path, to: statement, index: 1)
                    try requireDone(statement)
                }
            }
            if stagedCount > 0 {
                try execute(
                    """
                    INSERT OR REPLACE INTO codex_sessions (
                        path, size, modification_time, fingerprint, validation_fingerprint,
                        session_id, created_at_epoch, parent_session_id, anchors, records,
                        summary_records, record_count, cursor, diagnostics
                    )
                    SELECT path, size, modification_time, fingerprint,
                           validation_fingerprint, session_id, created_at_epoch,
                           parent_session_id, anchors, records, summary_records,
                           record_count, cursor, diagnostics
                    FROM codex_staged_sessions
                    """
                )
            }
            if stagedCount > 0 || !deletedPaths.isEmpty {
                try execute(
                    """
                    INSERT INTO cache_meta(key, value) VALUES ('generation', '1')
                    ON CONFLICT(key) DO UPDATE SET value = CAST(value AS INTEGER) + 1
                    """
                )
                let logicalWriteBytes = stagedPayloadBytes * 2
                try execute(
                    """
                    INSERT INTO cache_meta(key, value)
                    VALUES ('last_logical_write_bytes', '\(logicalWriteBytes)')
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """
                )
            }
            try execute("DELETE FROM codex_staged_scans")
            try execute("DELETE FROM codex_staged_sessions")
            try execute("COMMIT")
            stagingTransactionActive = false
        } catch {
            try? execute("ROLLBACK")
            stagingTransactionActive = false
            throw error
        }
    }

    private func stagedSessionCount() throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM codex_staged_sessions")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw currentError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func stagedSessionPayloadBytes() throws -> Int {
        let statement = try prepare(
            """
            SELECT COALESCE(SUM(
                LENGTH(anchors) + LENGTH(records) + LENGTH(summary_records)
                + LENGTH(cursor) + LENGTH(diagnostics)
            ), 0)
            FROM codex_staged_sessions
            """
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw currentError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func sessionCount() throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM codex_sessions")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw currentError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func forEachContribution(
        detailed: Bool,
        _ body: (CodexCachedContribution) throws -> Void
    ) throws {
        let statement = try prepare(
            detailed
                ? "SELECT records, diagnostics, record_count FROM codex_sessions ORDER BY path"
                : """
                  SELECT CASE
                      WHEN session_id IN (
                          SELECT session_id FROM codex_sessions
                          GROUP BY session_id HAVING COUNT(*) > 1
                      ) THEN records
                      ELSE COALESCE(summary_records, records)
                    END,
                    diagnostics,
                    record_count
                  FROM codex_sessions
                  ORDER BY path
                  """
        )
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let recordsData = columnData(statement, index: 0),
                  let diagnosticsData = columnData(statement, index: 1)
            else { throw currentError() }
            try body(
                CodexCachedContribution(
                    records: try decode(
                        [UsageRecord].self,
                        from: recordsData,
                        context: "contribution records"
                    ),
                    recordCount: Int(sqlite3_column_int64(statement, 2)),
                    diagnostics: try decode(
                        CodexCollectionDiagnostics.self,
                        from: diagnosticsData,
                        context: "contribution diagnostics"
                    )
                )
            )
        }
        try checkFinalStep(statement)
    }

    func stats() throws -> CodexIncrementalCacheStats {
        let statement = try prepare(
            """
            SELECT
                COALESCE((SELECT CAST(value AS INTEGER) FROM cache_meta WHERE key = 'generation'), 0),
                COUNT(*),
                COALESCE(SUM(record_count), 0),
                COALESCE((
                    SELECT CAST(value AS INTEGER) FROM cache_meta
                    WHERE key = 'last_logical_write_bytes'
                ), 0)
            FROM codex_sessions
            """
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw currentError() }
        return CodexIncrementalCacheStats(
            generation: Int(sqlite3_column_int64(statement, 0)),
            sessions: Int(sqlite3_column_int64(statement, 1)),
            records: Int(sqlite3_column_int64(statement, 2)),
            lastLogicalWriteBytes: Int(sqlite3_column_int64(statement, 3))
        )
    }

    private func migrateIfNeeded() throws {
        guard database != nil else { throw CodexIncrementalStoreError.sqlite("database closed") }
        let current = userVersion()
        guard current >= 0, current <= Self.schemaVersion else {
            throw CodexIncrementalStoreError.sqlite("unsupported schema version \(current)")
        }
        try execute(
            """
            CREATE TABLE IF NOT EXISTS cache_meta (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            )
            """
        )
        if current > 0, current < Self.schemaVersion {
            // v0.1.48 is the first public incremental-cache release. Recreate
            // older development schemas so interim payloads cannot survive.
            try execute("DROP TABLE IF EXISTS codex_sessions")
            try execute("DROP TABLE IF EXISTS codex_staged_scans")
            try execute("DROP TABLE IF EXISTS codex_staged_sessions")
            try execute("DELETE FROM cache_meta")
        }
        try execute(
            """
            CREATE TABLE IF NOT EXISTS codex_sessions (
                path TEXT PRIMARY KEY NOT NULL,
                size INTEGER NOT NULL,
                modification_time REAL NOT NULL,
                fingerprint TEXT NOT NULL,
                validation_fingerprint TEXT,
                session_id TEXT NOT NULL,
                created_at_epoch REAL,
                parent_session_id TEXT,
                anchors BLOB NOT NULL,
                records BLOB NOT NULL,
                summary_records BLOB,
                record_count INTEGER NOT NULL,
                cursor BLOB,
                diagnostics BLOB NOT NULL
            )
            """
        )
        try execute(
            "CREATE INDEX IF NOT EXISTS codex_sessions_session_id ON codex_sessions(session_id)"
        )
        try execute(
            "CREATE INDEX IF NOT EXISTS codex_sessions_parent_id ON codex_sessions(parent_session_id)"
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS codex_staged_scans (
                path TEXT PRIMARY KEY NOT NULL,
                size INTEGER NOT NULL,
                modification_time REAL NOT NULL,
                fingerprint TEXT NOT NULL,
                validation_fingerprint TEXT,
                session_id TEXT NOT NULL,
                created_at_epoch REAL,
                parent_session_id TEXT,
                anchors BLOB NOT NULL,
                scan BLOB NOT NULL
            )
            """
        )
        try execute(
            "CREATE INDEX IF NOT EXISTS codex_staged_scans_session_id ON codex_staged_scans(session_id)"
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS codex_staged_sessions (
                path TEXT PRIMARY KEY NOT NULL,
                size INTEGER NOT NULL,
                modification_time REAL NOT NULL,
                fingerprint TEXT NOT NULL,
                validation_fingerprint TEXT,
                session_id TEXT NOT NULL,
                created_at_epoch REAL,
                parent_session_id TEXT,
                anchors BLOB NOT NULL,
                records BLOB NOT NULL,
                summary_records BLOB NOT NULL,
                record_count INTEGER NOT NULL,
                cursor BLOB NOT NULL,
                diagnostics BLOB NOT NULL
            )
            """
        )
        try execute("PRAGMA user_version = \(Self.schemaVersion)")
    }

    /// Stored records and hourly summaries are bucketed into days, so they are
    /// dropped whenever the collection zone differs from the one that wrote them.
    private func resetIfTimeZoneChanged() throws {
        let current = UsageCollector.timezone.identifier
        let select = try prepare("SELECT value FROM cache_meta WHERE key = 'time_zone'")
        let stored = sqlite3_step(select) == SQLITE_ROW ? columnText(select, index: 0) : nil
        sqlite3_finalize(select)
        let storedZone = stored ?? TokenStepClock.legacyTimeZoneIdentifier
        // Also runs when the marker is missing, so legacy caches get one written.
        guard stored == nil || storedZone != current else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            if storedZone != current {
                try execute("DELETE FROM codex_sessions")
                try execute("DELETE FROM codex_staged_scans")
                try execute("DELETE FROM codex_staged_sessions")
            }
            let upsert = try prepare(
                """
                INSERT INTO cache_meta(key, value) VALUES ('time_zone', ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """
            )
            defer { sqlite3_finalize(upsert) }
            sqlite3_bind_text(upsert, 1, current, -1, Self.transient)
            guard sqlite3_step(upsert) == SQLITE_DONE else {
                throw CodexIncrementalStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func userVersion() -> Int32 {
        guard let statement = try? prepare("PRAGMA user_version") else { return -1 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return -1 }
        return sqlite3_column_int(statement, 0)
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw CodexIncrementalStoreError.sqlite("database closed") }
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(error)
            throw CodexIncrementalStoreError.sqlite(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else { throw CodexIncrementalStoreError.sqlite("database closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw currentError() }
        return statement
    }

    private func bind(_ value: String?, to statement: OpaquePointer, index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, Self.transient)
    }

    private func bind(_ value: TimeInterval?, to statement: OpaquePointer, index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_double(statement, index, value)
    }

    private func bind(_ data: Data, to statement: OpaquePointer, index: Int32) {
        _ = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), Self.transient)
        }
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        context: String
    ) throws -> T {
        do {
            return try PropertyListDecoder().decode(type, from: data)
        } catch {
            throw CodexIncrementalStoreError.corruptPayload(context)
        }
    }

    private func columnText(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func columnData(_ statement: OpaquePointer, index: Int32) -> Data? {
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count >= 0 else { return nil }
        if count == 0 { return Data() }
        guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
        return Data(bytes: bytes, count: count)
    }

    private func requireDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw currentError() }
    }

    private func checkFinalStep(_ statement: OpaquePointer) throws {
        let status = sqlite3_errcode(database)
        guard status == SQLITE_OK || status == SQLITE_DONE else { throw currentError() }
    }

    private func currentError() -> CodexIncrementalStoreError {
        guard let database else { return .sqlite("database closed") }
        return .sqlite(String(cString: sqlite3_errmsg(database)))
    }
}
