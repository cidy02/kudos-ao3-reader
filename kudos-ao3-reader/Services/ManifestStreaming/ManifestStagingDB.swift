import Foundation
import SQLite3

/// A private SQLite database for one staging run (system `libsqlite3`; no dependency). It lives in its own directory
/// so that the database and any sidecar files go away together.
nonisolated final class ManifestStagingDB {
    enum Bind {
        case int(Int64), double(Double), text(String), blob(UnsafeRawBufferPointer), null
    }

    /// One result row; valid only inside the `query` callback.
    struct Row {
        fileprivate let stmt: OpaquePointer
        func isNull(_ i: Int32) -> Bool { sqlite3_column_type(stmt, i) == SQLITE_NULL }
        func int(_ i: Int32) -> Int { Int(sqlite3_column_int64(stmt, i)) }
        func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
        /// Read with the stored byte length: a NUL inside a key is part of the key, not the end of it.
        func text(_ i: Int32) -> String {
            guard let p = sqlite3_column_text(stmt, i) else { return "" }
            return String(decoding: UnsafeBufferPointer(start: p, count: Int(sqlite3_column_bytes(stmt, i))), as: UTF8.self)
        }
        func data(_ i: Int32) -> Data {
            Data(bytes: sqlite3_column_blob(stmt, i) ?? UnsafeRawPointer(bitPattern: 1)!, count: Int(sqlite3_column_bytes(stmt, i)))
        }
    }

    let directory: URL
    private var handle: OpaquePointer?
    private var cache: [String: OpaquePointer] = [:]
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(directory: URL) throws {
        self.directory = directory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ManifestStreamError.io("staging directory: \(error.localizedDescription)")
        }
        let path = directory.appendingPathComponent("staging.sqlite").path
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            close()
            throw ManifestStreamError.io("sqlite open: \(message)")
        }
        // Private, disposable, rebuilt from the source on failure: no journal, no fsync, a small page cache.
        do {
            try exec("PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF; PRAGMA cache_size = -4096; PRAGMA temp_store = FILE")
        } catch {
            close() // an initializer that throws must not leave the handle open
            throw error
        }
    }

    deinit { close() }

    func close() {
        for stmt in cache.values { sqlite3_finalize(stmt) }
        cache.removeAll()
        if let handle { sqlite3_close(handle) }
        handle = nil
    }

    /// Closes and deletes the whole staging directory. Safe to call twice. A failure to delete is returned, not swallowed.
    @discardableResult
    func destroy() -> Error? {
        close()
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
        do { try FileManager.default.removeItem(at: directory); return nil } catch { return error }
    }

    private func failure(_ what: String) -> ManifestStreamError {
        let code = handle.map { sqlite3_errcode($0) } ?? SQLITE_ERROR
        let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "closed"
        return code == SQLITE_FULL ? .resourceExhausted("disk full while staging") : .io("sqlite \(what): \(message)")
    }

    func exec(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure("exec") }
    }

    private func statement(_ sql: String) throws -> OpaquePointer {
        if let cached = cache[sql] { return cached }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw failure("prepare") }
        cache[sql] = stmt
        return stmt
    }

    private func bind(_ stmt: OpaquePointer, _ binds: [Bind]) throws {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        for (offset, value) in binds.enumerated() {
            let i = Int32(offset + 1)
            let rc: Int32
            switch value {
            case let .int(v): rc = sqlite3_bind_int64(stmt, i, v)
            case let .double(v): rc = sqlite3_bind_double(stmt, i, v)
            case let .text(v): // explicit byte length, never a C string: a NUL inside a key must not truncate it
                var copy = v
                rc = copy.withUTF8 { sqlite3_bind_text(stmt, i, UnsafeRawPointer($0.baseAddress ?? UnsafePointer(bitPattern: 1)!).assumingMemoryBound(to: CChar.self), Int32($0.count), Self.transient) }
            case let .blob(v): rc = sqlite3_bind_blob(stmt, i, v.baseAddress ?? UnsafeRawPointer(bitPattern: 1), Int32(v.count), Self.transient)
            case .null: rc = sqlite3_bind_null(stmt, i)
            }
            guard rc == SQLITE_OK else { throw failure("bind") }
        }
    }

    /// Runs a statement that returns no rows.
    func run(_ sql: String, _ binds: [Bind] = []) throws {
        let stmt = try statement(sql)
        try bind(stmt, binds)
        let rc = sqlite3_step(stmt)
        sqlite3_reset(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw failure("step") }
    }

    func query(_ sql: String, _ binds: [Bind] = [], _ row: (Row) throws -> Void) throws {
        let stmt = try statement(sql)
        try bind(stmt, binds)
        defer { sqlite3_reset(stmt) }
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { return }
            guard rc == SQLITE_ROW else { throw failure("step") }
            try row(Row(stmt: stmt))
        }
    }

    func scalar(_ sql: String, _ binds: [Bind] = []) throws -> Int {
        var value = 0
        try query(sql, binds) { value = $0.int(0) }
        return value
    }
}
