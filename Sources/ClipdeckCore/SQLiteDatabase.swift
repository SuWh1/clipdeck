import Foundation
import SQLite3

public enum SQLValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

public struct SQLiteError: LocalizedError, CustomStringConvertible, Equatable {
    public let code: Int32
    public let message: String

    public var description: String {
        "SQLite error \(code): \(message)"
    }

    public var errorDescription: String? {
        description
    }
}

public struct SQLRow: Sendable {
    let values: [String: SQLValue]

    public func int(_ column: String) -> Int64? {
        switch values[column] {
        case .integer(let value): value
        case .real(let value): Int64(value)
        default: nil
        }
    }

    public func double(_ column: String) -> Double? {
        switch values[column] {
        case .real(let value): value
        case .integer(let value): Double(value)
        default: nil
        }
    }

    public func string(_ column: String) -> String? {
        if case .text(let value) = values[column] { return value }
        return nil
    }

    public func data(_ column: String) -> Data? {
        switch values[column] {
        case .blob(let value): value
        case .text(let value): Data(value.utf8)
        default: nil
        }
    }
}

public final class SQLiteDatabase {
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private let handle: OpaquePointer

    public init(path: String) throws {
        var connection: OpaquePointer?
        let code = sqlite3_open_v2(path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard code == SQLITE_OK, let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open \(path)"
            sqlite3_close_v2(connection)
            throw SQLiteError(code: code, message: message)
        }
        handle = connection
        sqlite3_busy_timeout(connection, 5_000)
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    public var lastInsertRowID: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    public func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        guard code == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
            sqlite3_free(errorMessage)
            throw SQLiteError(code: code, message: message)
        }
    }

    public func run(_ sql: String, _ parameters: [SQLValue] = []) throws {
        try withStatement(sql, parameters) { statement in
            let code = sqlite3_step(statement)
            guard code == SQLITE_DONE || code == SQLITE_ROW else { throw error(code) }
        }
    }

    public func query(_ sql: String, _ parameters: [SQLValue] = []) throws -> [SQLRow] {
        try withStatement(sql, parameters) { statement in
            var rows: [SQLRow] = []
            while true {
                let code = sqlite3_step(statement)
                if code == SQLITE_DONE { return rows }
                guard code == SQLITE_ROW else { throw error(code) }
                rows.append(row(from: statement))
            }
        }
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
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

    private func withStatement<T>(_ sql: String, _ parameters: [SQLValue], _ body: (OpaquePointer) throws -> T) throws -> T {
        var prepared: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &prepared, nil)
        guard code == SQLITE_OK, let statement = prepared else { throw error(code) }
        defer { sqlite3_finalize(statement) }
        for (index, value) in parameters.enumerated() {
            try bind(value, at: Int32(index + 1), in: statement)
        }
        return try body(statement)
    }

    private func bind(_ value: SQLValue, at index: Int32, in statement: OpaquePointer) throws {
        let code: Int32 = switch value {
        case .null: sqlite3_bind_null(statement, index)
        case .integer(let number): sqlite3_bind_int64(statement, index, number)
        case .real(let number): sqlite3_bind_double(statement, index, number)
        case .text(let text): sqlite3_bind_text(statement, index, text, Int32(text.utf8.count), Self.transient)
        case .blob(let data) where data.isEmpty: sqlite3_bind_zeroblob(statement, index, 0)
        case .blob(let data):
            data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), Self.transient) }
        }
        guard code == SQLITE_OK else { throw error(code) }
    }

    private func row(from statement: OpaquePointer) -> SQLRow {
        let columns = (0..<sqlite3_column_count(statement)).map { column in
            (String(cString: sqlite3_column_name(statement, column)), value(at: column, in: statement))
        }
        return SQLRow(values: Dictionary(columns, uniquingKeysWith: { first, _ in first }))
    }

    private func value(at column: Int32, in statement: OpaquePointer) -> SQLValue {
        let count = Int(sqlite3_column_bytes(statement, column))
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, column))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, column))
        case SQLITE_TEXT:
            let bytes = UnsafeBufferPointer(start: sqlite3_column_text(statement, column), count: count)
            return .text(String(decoding: bytes, as: UTF8.self))
        case SQLITE_BLOB:
            guard count > 0, let pointer = sqlite3_column_blob(statement, column) else { return .blob(Data()) }
            return .blob(Data(bytes: pointer, count: count))
        default:
            return .null
        }
    }

    private func error(_ code: Int32) -> SQLiteError {
        SQLiteError(code: code, message: String(cString: sqlite3_errmsg(handle)))
    }
}
