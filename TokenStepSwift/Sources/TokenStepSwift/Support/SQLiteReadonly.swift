import Foundation

enum SQLiteReadonly {
    static func jsonRows(database: URL, query: String) -> [[String: Any]]? {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenstep-sqlite-\(UUID().uuidString).json")
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        guard let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            return nil
        }
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", database.path, query]
        process.standardOutput = outputHandle
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        guard !data.isEmpty else { return [] }
        return try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
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
