import Foundation
import SQLite3

enum SQLiteReadonly {
    /// Runs one read-only query in process and returns rows shaped like
    /// `sqlite3 -json` output after `JSONSerialization`: numbers as `NSNumber`,
    /// text and blobs as `String`, NULL as `NSNull`. Returns nil if the database
    /// cannot be opened or the query fails.
    static func jsonRows(database: URL, query: String) -> [[String: Any]]? {
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(database.path, &connection, flags, nil) == SQLITE_OK,
              let connection
        else {
            sqlite3_close(connection)
            return nil
        }
        defer { sqlite3_close(connection) }
        // Other apps keep these databases open and may be mid-write.
        sqlite3_busy_timeout(connection, 2_000)

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
