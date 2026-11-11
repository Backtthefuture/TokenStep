import Foundation
import SQLite3

enum SQLiteReadonly {
    /// Runs one read-only query in process and returns rows shaped like
    /// `sqlite3 -json` output after `JSONSerialization`: numbers as `NSNumber`,
    /// text and blobs as `String`, NULL as `NSNull`. Returns nil if the database
    /// cannot be opened or the query fails.
    ///
    /// WAL databases cannot be opened by a plain read-only connection once the
    /// owning app has exited and removed its `-shm` sidecar: SQLite needs to
    /// create that file and refuses on a read-only handle. Callers therefore
    /// fall back to a writable handle restricted with `PRAGMA query_only`, and
    /// only then to `immutable`, which skips the WAL and can miss live rows.
    static func jsonRows(database: URL, query: String) -> [[String: Any]]? {
        for attempt in attempts {
            if let rows = tryRead(database: database, query: query, attempt: attempt) {
                return rows
            }
        }
        return nil
    }

    enum OpenAttempt {
        case readOnly
        // A writable handle lets SQLite create the -shm file; query_only keeps
        // the connection from modifying anything.
        case queryOnly
        // Last resort: ignores -wal entirely, so it may be stale while the
        // owning app is live.
        case immutable
    }

    /// Ordered by fidelity. `queryOnly` must precede `immutable`: a live WAL
    /// database rejects `immutable` (its reads miss unmerged rows), while a
    /// cleanly closed WAL database rejects `readOnly`.
    private static let attempts: [OpenAttempt] = [.readOnly, .queryOnly, .immutable]

    private static func tryRead(database: URL, query: String, attempt: OpenAttempt) -> [[String: Any]]? {
        func open(_ path: String, _ flags: Int32) -> (OpaquePointer?, Int32) {
            var handle: OpaquePointer?
            let code = sqlite3_open_v2(path, &handle, flags, nil)
            return (handle, code)
        }

        var (connection, openCode): (OpaquePointer?, Int32)
        switch attempt {
        case .readOnly:
            (connection, openCode) = open(database.path, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX)
        case .queryOnly:
            (connection, openCode) = open(database.path, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX)
        case .immutable:
            let uri = "file:\(database.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? database.path)?immutable=1"
            (connection, openCode) = open(uri, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX)
        }
        guard openCode == SQLITE_OK, let connection else {
            sqlite3_close(connection)
            return nil
        }
        defer { sqlite3_close(connection) }
        // Other apps keep these databases open and may be mid-write.
        sqlite3_busy_timeout(connection, 2_000)
        if attempt == .queryOnly {
            guard sqlite3_exec(connection, "PRAGMA query_only=1", nil, nil, nil) == SQLITE_OK else {
                return nil
            }
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            sqlite3_finalize(statement)
            return nil
        }
        defer { sqlite3_finalize(statement) }

        let columnCount = sqlite3_column_count(statement)
        let names = (0..<columnCount).map { index in
            sqlite3_column_name(statement, index).map { String(cString: $0) } ?? ""
        }
        var rows: [[String: Any]] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                var row = [String: Any](minimumCapacity: Int(columnCount))
                for index in 0..<columnCount {
                    row[names[Int(index)]] = value(statement, column: index)
                }
                rows.append(row)
            case SQLITE_DONE:
                return rows
            default:
                return nil
            }
        }
    }

    private static func value(_ statement: OpaquePointer, column: Int32) -> Any {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER:
            return NSNumber(value: sqlite3_column_int64(statement, column))
        case SQLITE_FLOAT:
            return NSNumber(value: sqlite3_column_double(statement, column))
        case SQLITE_TEXT, SQLITE_BLOB:
            // Fetch the pointer before the length, as SQLite requires.
            let bytes = sqlite3_column_blob(statement, column)
            let count = Int(sqlite3_column_bytes(statement, column))
            guard count > 0, let bytes else { return "" }
            return String(decoding: UnsafeRawBufferPointer(start: bytes, count: count), as: UTF8.self)
        default:
            return NSNull()
        }
    }

    static func scalar(_ value: Any?) -> Int {
        switch value {
        case let number as Int:
            return number
        case let number as Int64:
            return Int(number)
        case let number as Double:
            return Int(number)
        case let text as String:
            return Int(text) ?? 0
        default:
            return 0
        }
    }
}
