import Foundation
import SQLite3

/// SQLite errors lifted into Swift. The underlying SQLite return code and
/// human message from `sqlite3_errmsg` are preserved for diagnostics.
enum SQLiteError: Error, CustomStringConvertible {
    case openFailed(path: String, code: Int32, message: String)
    case prepareFailed(sql: String, code: Int32, message: String)
    case stepFailed(sql: String, code: Int32, message: String)
    case execFailed(sql: String, code: Int32, message: String)
    case bindFailed(index: Int32, code: Int32, message: String)

    var description: String {
        switch self {
        case .openFailed(let p, let c, let m):
            return "SQLite open failed (\(c)) at \(p): \(m)"
        case .prepareFailed(let s, let c, let m):
            return "SQLite prepare failed (\(c)) for `\(s.prefix(80))…`: \(m)"
        case .stepFailed(let s, let c, let m):
            return "SQLite step failed (\(c)) for `\(s.prefix(80))…`: \(m)"
        case .execFailed(let s, let c, let m):
            return "SQLite exec failed (\(c)) for `\(s.prefix(80))…`: \(m)"
        case .bindFailed(let i, let c, let m):
            return "SQLite bind failed at idx \(i) (\(c)): \(m)"
        }
    }
}

/// SQLite uses two sentinel destructors for `sqlite3_bind_text/blob`:
/// STATIC (data outlives the statement) and TRANSIENT (SQLite makes its own
/// copy). We pass TRANSIENT — Swift `String`/`Data` lifetimes are scoped to
/// the binding call.
let SQLITE_TRANSIENT_BRIDGE = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Owns the SQLite connection lifecycle. Single connection; all writes are
/// funneled through a serial dispatch queue so concurrent callers don't
/// trample each other. WAL journaling is enabled for better reader/writer
/// concurrency.
final class Database {
    private var handle: OpaquePointer?
    /// Serial queue for write-side work. Reads also use it for simplicity —
    /// the connection is single-threaded.
    let queue = DispatchQueue(label: "ScreenshotInbox.Database.serial")

    /// Opens (or creates) the SQLite file at `path`. Enables WAL mode and
    /// foreign keys. Throws on failure.
    init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        if rc != SQLITE_OK {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if db != nil { sqlite3_close(db) }
            throw SQLiteError.openFailed(path: path, code: rc, message: msg)
        }
        self.handle = db
        try exec("PRAGMA foreign_keys = ON;")
        try exec("PRAGMA journal_mode = WAL;")
        try exec("PRAGMA synchronous = NORMAL;")
        print("[Database] opened \(path)")
    }

    /// No-op default init kept for source compatibility with the previous
    /// stub. Don't use; prefer `init(path:)`.
    init() {}

    deinit { close() }

    func close() {
        if let h = handle {
            sqlite3_close(h)
            handle = nil
            print("[Database] closed")
        }
    }

    /// One-shot SQL (CREATE TABLE, PRAGMA, …). Not for parametric queries.
    func exec(_ sql: String) throws {
        guard let handle else { return }
        var errPtr: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &errPtr)
        if rc != SQLITE_OK {
            let msg = errPtr.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(errPtr)
            throw SQLiteError.execFailed(sql: sql, code: rc, message: msg)
        }
    }

    /// Compiles a parametric SQL statement.
    func prepare(_ sql: String) throws -> Statement {
        guard let handle else {
            throw SQLiteError.prepareFailed(sql: sql, code: -1, message: "no open DB")
        }
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        if rc != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw SQLiteError.prepareFailed(sql: sql, code: rc, message: msg)
        }
        return Statement(stmt: stmt!, sql: sql, db: handle)
    }

    /// Runs `block` inside `BEGIN IMMEDIATE … COMMIT`. Rolls back on throw.
    func transaction<T>(_ block: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE;")
        do {
            let value = try block()
            try exec("COMMIT;")
            return value
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }
}

// MARK: - Statement

extension Database {
    /// RAII wrapper around `sqlite3_stmt`. Auto-finalizes on `deinit`.
    final class Statement {
        private let stmt: OpaquePointer
        private let sql: String
        private let db: OpaquePointer

        init(stmt: OpaquePointer, sql: String, db: OpaquePointer) {
            self.stmt = stmt
            self.sql = sql
            self.db = db
        }

        deinit { sqlite3_finalize(stmt) }

        // MARK: Binding

        func bind(_ idx: Int32, _ value: Int64) throws {
            try check(sqlite3_bind_int64(stmt, idx, value), idx: idx)
        }
        func bind(_ idx: Int32, _ value: Int) throws {
            try bind(idx, Int64(value))
        }
        func bind(_ idx: Int32, _ value: Double) throws {
            try check(sqlite3_bind_double(stmt, idx, value), idx: idx)
        }
        func bind(_ idx: Int32, _ value: String) throws {
            try check(sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT_BRIDGE), idx: idx)
        }
        func bindNull(_ idx: Int32) throws {
            try check(sqlite3_bind_null(stmt, idx), idx: idx)
        }
        func bind(_ idx: Int32, _ value: String?) throws {
            if let v = value { try bind(idx, v) } else { try bindNull(idx) }
        }
        func bind(_ idx: Int32, _ value: Int?) throws {
            if let v = value { try bind(idx, v) } else { try bindNull(idx) }
        }
        func bind(_ idx: Int32, _ value: Double?) throws {
            if let v = value { try bind(idx, v) } else { try bindNull(idx) }
        }
        func bindBool(_ idx: Int32, _ value: Bool) throws {
            try bind(idx, Int64(value ? 1 : 0))
        }

        // MARK: Stepping

        /// Returns true if a row is available, false once exhausted.
        func step() throws -> Bool {
            let rc = sqlite3_step(stmt)
            switch rc {
            case SQLITE_ROW:  return true
            case SQLITE_DONE: return false
            default:
                let msg = String(cString: sqlite3_errmsg(db))
                throw SQLiteError.stepFailed(sql: sql, code: rc, message: msg)
            }
        }

        func reset() {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }

        // MARK: Column accessors

        func columnInt(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
        func columnDouble(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
        func columnString(_ i: Int32) -> String? {
            guard let raw = sqlite3_column_text(stmt, i) else { return nil }
            return String(cString: raw)
        }
        func columnIsNull(_ i: Int32) -> Bool {
            sqlite3_column_type(stmt, i) == SQLITE_NULL
        }

        // MARK: Internal

        private func check(_ rc: Int32, idx: Int32) throws {
            guard rc != SQLITE_OK else { return }
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.bindFailed(index: idx, code: rc, message: msg)
        }
    }
}
