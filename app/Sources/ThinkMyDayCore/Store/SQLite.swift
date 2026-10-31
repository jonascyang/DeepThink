import Foundation
import SQLite3

/// SQLite tells it to copy bound text and blobs before the call returns.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct SQLiteError: Error, CustomStringConvertible, Sendable {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite \(code): \(message)" }
}

public enum SQLValue: Sendable, Equatable {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
}

/// A single SQLite connection. Not thread-safe; owned by one actor.
final class SQLiteConnection {
    private(set) var handle: OpaquePointer?

    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open \(path)"
            sqlite3_close_v2(handle)
            throw SQLiteError(code: rc, message: message)
        }
        sqlite3_busy_timeout(handle, 5_000)
    }

    deinit { sqlite3_close_v2(handle) }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &error)
        if rc != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(error)
            throw SQLiteError(code: rc, message: message)
        }
    }

    func run(_ sql: String, _ args: [SQLValue] = []) throws {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw lastError(rc) }
    }

    func query(_ sql: String, _ args: [SQLValue] = []) throws -> [[SQLValue]] {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        var rows: [[SQLValue]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw lastError(rc) }
            rows.append((0..<sqlite3_column_count(stmt)).map { column(stmt, $0) })
        }
        return rows
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    /// Runs `body` inside BEGIN IMMEDIATE … COMMIT; rolls back if it throws.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String, _ args: [SQLValue]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw lastError(rc) }
        for (i, arg) in args.enumerated() {
            let index = Int32(i + 1)
            let bindRC: Int32
            switch arg {
            case .null: bindRC = sqlite3_bind_null(stmt, index)
            case .int(let v): bindRC = sqlite3_bind_int64(stmt, index, v)
            case .double(let v): bindRC = sqlite3_bind_double(stmt, index, v)
            case .text(let v): bindRC = sqlite3_bind_text(stmt, index, v, -1, SQLITE_TRANSIENT)
            case .blob(let v):
                bindRC = v.withUnsafeBytes { sqlite3_bind_blob(stmt, index, $0.baseAddress, Int32($0.count), SQLITE_TRANSIENT) }
            }
            guard bindRC == SQLITE_OK else {
                sqlite3_finalize(stmt)
                throw lastError(bindRC)
            }
        }
        return stmt
    }

    private func column(_ stmt: OpaquePointer?, _ i: Int32) -> SQLValue {
        switch sqlite3_column_type(stmt, i) {
        case SQLITE_INTEGER: return .int(sqlite3_column_int64(stmt, i))
        case SQLITE_FLOAT: return .double(sqlite3_column_double(stmt, i))
        case SQLITE_TEXT: return .text(String(cString: sqlite3_column_text(stmt, i)))
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(stmt, i))
            guard count > 0, let bytes = sqlite3_column_blob(stmt, i) else { return .blob(Data()) }
            return .blob(Data(bytes: bytes, count: count))
        default: return .null
        }
    }

    private func lastError(_ rc: Int32) -> SQLiteError {
        SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(handle)))
    }
}

extension SQLValue {
    var int: Int64? { if case .int(let v) = self { v } else { nil } }
    var double: Double? {
        switch self {
        case .double(let v): v
        case .int(let v): Double(v)
        default: nil
        }
    }
    var text: String? { if case .text(let v) = self { v } else { nil } }
    var blob: Data? { if case .blob(let v) = self { v } else { nil } }
}
