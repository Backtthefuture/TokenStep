import Foundation

enum CursorCodeSignalService {
    static var databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cursor/ai-tracking/ai-code-tracking.db")

    static func read() throws -> CursorCodeSignal {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return .empty(status: "missing_db")
        }

        let summaryQuery = """
        select count(*) as blocks,
               count(distinct model) as models,
               count(distinct conversationId) as conversations,
               count(distinct requestId) as requests,
               count(distinct fileName) as files
        from ai_code_hashes
        where date(createdAt/1000, 'unixepoch', 'localtime') = date('now', 'localtime')
        """
        guard let summary = SQLiteReadonly.jsonRows(database: databaseURL, query: summaryQuery)?.first else {
            return .empty(status: "query_failed")
        }

        let blocks = SQLiteReadonly.scalar(summary["blocks"])
        if blocks <= 0 {
            return .empty(status: "empty")
        }

        let modelQuery = """
        select model, count(*) as n
        from ai_code_hashes
        where date(createdAt/1000, 'unixepoch', 'localtime') = date('now', 'localtime')
        group by model
        order by n desc
        """
        let models = (SQLiteReadonly.jsonRows(database: databaseURL, query: modelQuery) ?? []).compactMap { row -> CursorCodeModelCount? in
            let name = (row["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name, !name.isEmpty else { return nil }
            return CursorCodeModelCount(name: name, blocks: SQLiteReadonly.scalar(row["n"]))
        }

        return CursorCodeSignal(
            fetchedAt: Date(),
            blockCount: blocks,
            modelCount: SQLiteReadonly.scalar(summary["models"]),
            conversationCount: SQLiteReadonly.scalar(summary["conversations"]),
            requestCount: SQLiteReadonly.scalar(summary["requests"]),
            fileCount: SQLiteReadonly.scalar(summary["files"]),
            models: models,
            status: "ok"
        )
    }
}
