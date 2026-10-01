import Foundation
import SQLite3

nonisolated enum ScreenshotTextIndex {
    struct Stamp: Equatable, Sendable {
        let modifiedAt: TimeInterval
        let byteCount: Int
        let mode: ScreenshotRecognitionMode

        init(_ entry: ScreenshotEntry, mode: ScreenshotRecognitionMode) {
            modifiedAt = entry.modifiedAt.timeIntervalSince1970
            byteCount = entry.byteCount
            self.mode = mode
        }

        fileprivate init(_ statement: OpaquePointer) {
            modifiedAt = sqlite3_column_double(statement, 1)
            byteCount = Int(sqlite3_column_int64(statement, 2))
            mode = ScreenshotRecognitionMode(rawValue: Connection.string(statement, 3)) ?? .fast
        }
    }

    static func stamps(at url: URL) throws -> [String: Stamp] {
        let connection = try Connection(url)
        let statement = try connection.prepare("SELECT path, modified, bytes, mode FROM image_text")
        defer { sqlite3_finalize(statement) }
        var result: [String: Stamp] = [:]
        while try connection.next(statement) {
            try Task.checkCancellation()
            result[Connection.string(statement, 0)] = Stamp(statement)
        }
        return result
    }

    static func save(_ text: String, entry: ScreenshotEntry, mode: ScreenshotRecognitionMode, at url: URL) throws {
        let connection = try Connection(url)
        let statement = try connection.prepare(
            "INSERT OR REPLACE INTO image_text(path, modified, bytes, mode, text) VALUES (?, ?, ?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        Connection.bind(entry.id, to: statement, at: 1)
        sqlite3_bind_double(statement, 2, entry.modifiedAt.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 3, Int64(entry.byteCount))
        Connection.bind(mode.rawValue, to: statement, at: 4)
        Connection.bind(text, to: statement, at: 5)
        _ = try connection.next(statement)
    }

    static func matches(
        query: ScreenshotQuery, entries: [ScreenshotEntry], mode: ScreenshotRecognitionMode,
        now: Date, calendar: Calendar, at url: URL
    ) throws -> Set<String> {
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let connection = try Connection(url)
        let statement = try connection.prepare("SELECT path, modified, bytes, mode, text FROM image_text")
        defer { sqlite3_finalize(statement) }
        var matches = Set<String>()
        while try connection.next(statement) {
            try Task.checkCancellation()
            let path = Connection.string(statement, 0)
            guard let entry = byID[path], Stamp(statement) == Stamp(entry, mode: mode) else { continue }
            if query.matches(entry, text: Connection.string(statement, 4), now: now, calendar: calendar) {
                matches.insert(path)
            }
        }
        return matches
    }

    static func remove(_ paths: Set<String>, at url: URL) throws {
        guard !paths.isEmpty else { return }
        let connection = try Connection(url)
        let statement = try connection.prepare("DELETE FROM image_text WHERE path = ?")
        defer { sqlite3_finalize(statement) }
        for path in paths {
            try Task.checkCancellation()
            Connection.bind(path, to: statement, at: 1)
            _ = try connection.next(statement)
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
    }

    private enum Failure: LocalizedError {
        case database(String)
        var errorDescription: String? {
            switch self {
            case .database(let message): "Screenshot text index: \(message)"
            }
        }
    }

    private final class Connection {
        private let database: OpaquePointer
        private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        init(_ url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var pointer: OpaquePointer?
            let result = sqlite3_open_v2(url.path, &pointer, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
            guard result == SQLITE_OK, let pointer else {
                let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open the database."
                sqlite3_close(pointer)
                throw Failure.database(message)
            }
            sqlite3_busy_timeout(pointer, 1000)
            let schema = """
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS image_text (
                    path TEXT PRIMARY KEY, modified REAL NOT NULL, bytes INTEGER NOT NULL,
                    mode TEXT NOT NULL, text TEXT NOT NULL
                );
                """
            guard sqlite3_exec(pointer, schema, nil, nil, nil) == SQLITE_OK else {
                let error = Failure.database(String(cString: sqlite3_errmsg(pointer)))
                sqlite3_close(pointer)
                throw error
            }
            database = pointer
        }

        deinit { sqlite3_close(database) }

        func prepare(_ sql: String) throws -> OpaquePointer {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw Failure.database(String(cString: sqlite3_errmsg(database)))
            }
            return statement
        }

        func next(_ statement: OpaquePointer) throws -> Bool {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: return true
            case SQLITE_DONE: return false
            default: throw Failure.database(String(cString: sqlite3_errmsg(database)))
            }
        }

        static func bind(_ text: String, to statement: OpaquePointer, at index: Int32) {
            sqlite3_bind_text(statement, index, text, -1, transient)
        }

        static func string(_ statement: OpaquePointer, _ column: Int32) -> String {
            sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
        }
    }
}
