import Darwin
import Foundation
import SQLite3
import SwiftData
@testable import Kudos

/// T-567 P1b prototypes (test target only; no production behaviour change). Two building blocks for an atomic,
/// bounded-memory apply on SwiftData: (1) batched apply that recycles the context or the whole container, and
/// (2) a shadow store that is built beside the live one and published by a journaled file swap.
enum BatchApply {
    enum Recycle: String, CaseIterable {
        /// One long-lived container, a new `ModelContext` per batch (what P1's `control_batched_500` did).
        case freshContext = "fresh_context"
        /// As above, plus `context.rollback()` (SwiftData has no `reset()`) before the context is dropped.
        case freshContextRollback = "fresh_context_rollback"
        /// A new `ModelContainer` and context per batch; everything dropped between batches.
        case freshContainer = "fresh_container"
        /// A new container every 16 batches (a cheaper compromise).
        case containerEvery16 = "container_every_16"
    }

    static func uuidNew(_ i: Int) -> UUID { ManifestFixtureGenerator.uuid(8, i, seed: 1) }
    static func uuidExisting(_ i: Int) -> UUID { ManifestFixtureGenerator.uuid(9, i, seed: 1) }

    /// Incoming row `i`: every 4th one updates an existing row (when `existing` has one at i/4), the rest are new.
    static func incomingID(_ i: Int, existing: Int) -> UUID {
        (i % 4 == 0 && i / 4 < existing) ? uuidExisting(i / 4) : uuidNew(i)
    }

    static func makeWork(id: UUID, i: Int, author: String) -> SavedWork {
        let work = SavedWork(
            id: id, title: "Row \(i)", author: author,
            summary: ManifestFixtureGenerator.text(count: 400, seed: UInt64(i))
        )
        work.workTags = (0 ..< 8).map { "tag \(($0 * 13 + i) % 1_999)" }
        return work
    }

    /// Applies `ids` (index -> id) in batches. Insert-or-update by id, then (when `sweepExisting > 0`) soft-deletes the
    /// existing rows that the incoming set did not touch, also in bounded batches.
    /// - Returns: number of batches saved.
    @discardableResult
    static func upsert(
        container open: () throws -> ModelContainer, incoming: Int, existing: Int, batch: Int, recycle: Recycle,
        author: String = "A", sweepExisting: Bool = false, onProgress: (Int) -> Void = { _ in }
    ) throws -> Int {
        var container: ModelContainer? = try open()
        var batches = 0
        var lo = 0
        while lo < incoming {
            let hi = min(incoming, lo + batch)
            try autoreleasepool {
                try applyOne(container!, range: lo ..< hi, existing: existing, author: author, reset: recycle == .freshContextRollback)
            }
            batches += 1
            lo = hi
            onProgress(lo)
            if recycle == .freshContainer || (recycle == .containerEvery16 && batches % 16 == 0) {
                container = nil
                container = try open()
            }
        }
        if sweepExisting, existing > 0 {
            let touched = Set((0 ..< incoming).compactMap { $0 % 4 == 0 && $0 / 4 < existing ? $0 / 4 : nil })
            var lo = 0
            while lo < existing {
                let hi = min(existing, lo + batch)
                try autoreleasepool {
                    let ids = (lo ..< hi).filter { !touched.contains($0) }.map(uuidExisting)
                    let context = ModelContext(container!)
                    context.autosaveEnabled = false
                    let rows = try context.fetch(FetchDescriptor<SavedWork>(predicate: #Predicate { ids.contains($0.id) }))
                    for row in rows { row.deletedAt = Date(timeIntervalSince1970: 1_700_000_000) }
                    try context.save()
                    if recycle == .freshContextRollback { context.rollback() }
                }
                lo = hi
                if recycle == .freshContainer || (recycle == .containerEvery16 && (lo / batch) % 16 == 0) {
                    container = nil
                    container = try open()
                }
            }
        }
        return batches
    }

    private static func applyOne(_ container: ModelContainer, range: Range<Int>, existing: Int, author: String, reset: Bool) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let ids = range.map { incomingID($0, existing: existing) }
        let found = try context.fetch(FetchDescriptor<SavedWork>(predicate: #Predicate { ids.contains($0.id) }))
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (n, i) in range.enumerated() {
            if let row = byID[ids[n]] {
                row.title = "Row \(i)"
                row.author = author
            } else {
                context.insert(makeWork(id: ids[n], i: i, author: author))
            }
        }
        try context.save()
        if reset { context.rollback() }
    }

    /// Pre-populates `rows` existing works (id kind 9, author "Local") with the cheapest bounded path.
    static func populateExisting(_ open: () throws -> ModelContainer, rows: Int) throws {
        var container: ModelContainer? = try open()
        var lo = 0
        while lo < rows {
            let hi = min(rows, lo + 2_000)
            try autoreleasepool {
                let context = ModelContext(container!)
                context.autosaveEnabled = false
                for i in lo ..< hi { context.insert(makeWork(id: uuidExisting(i), i: i, author: "Local")) }
                try context.save()
            }
            lo = hi
            if (lo / 2_000) % 16 == 0 { container = nil; container = try open() }
        }
    }
}

// MARK: - SQLite helpers (the store is plain SQLite underneath; used only by the prototype)

enum StoreSQLite {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func exec(_ url: URL, _ sql: String, readOnly: Bool = false) throws {
        var db: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw Failure(description: "open \(url.lastPathComponent)")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 5_000)
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            let message = err.map { String(cString: $0) } ?? "?"
            sqlite3_free(err)
            throw Failure(description: "\(sql): \(message)")
        }
    }

    /// Folds the WAL into the main file and truncates it, so the store is one self-contained file.
    static func checkpoint(_ url: URL) throws { try exec(url, "PRAGMA wal_checkpoint(TRUNCATE);") }

    /// `PRAGMA quick_check` result ("ok" when sound).
    static func quickCheck(_ url: URL) throws -> String {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); throw Failure(description: "open") }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA quick_check(1);", -1, &stmt, nil) == SQLITE_OK else { throw Failure(description: "prepare") }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? String(cString: sqlite3_column_text(stmt, 0)) : "no row"
    }

    /// `copyfile` without the clone flag: a real byte copy (what a non-APFS volume would do).
    static func byteCopy(_ from: URL, _ to: URL) throws {
        guard copyfile(from.path, to.path, nil, copyfile_flags_t(COPYFILE_DATA | COPYFILE_STAT)) == 0 else {
            throw Failure(description: "copyfile errno \(errno)")
        }
    }

    /// `fcntl(F_FULLFSYNC)` on a file or directory.
    static func fullSync(_ url: URL) {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return }
        if fcntl(fd, F_FULLFSYNC) != 0 { fsync(fd) }
        close(fd)
    }

    static func openPaths(containing needle: String) -> [String] {
        var found: [String] = []
        for fd in 0 ..< 4_096 {
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            if fcntl(Int32(fd), F_GETPATH, &buffer) != -1 {
                let path = String(cString: buffer)
                if path.contains(needle) { found.append(path) }
            }
        }
        return found
    }

    static func size(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }
}

// MARK: - Shadow store + journaled swap

/// Layout under `root`:
/// `live/store.sqlite(-wal,-shm)` and `live/Works/<id>.epub`; `staging/store.sqlite` and `staging/Works/…` (complete
/// and fsynced before the journal is written); `old/…` (displaced live files); `journal.json`.
///
/// Commit point = the atomic appearance of `journal.json` (write temp, fsync, rename, fsync directory).
/// Before it: recovery deletes `staging/` (old store wins). After it: recovery rolls forward by re-running the same
/// ordered, idempotent moves ("move iff source exists and destination does not") — new store wins.
final class StoreSwapPrototype {
    struct Journal: Codable, Equatable {
        var phase = "prepared"
        var displacedWorks: [String]
        var newWorks: [String]
        var stagedStoreBytes: Int
    }

    struct SimulatedCrash: Error { let after: Int }

    let root: URL
    var crashAfter: Int?
    private(set) var ticks = 0
    private let fm = FileManager.default

    init(root: URL) { self.root = root }

    var live: URL { root.appendingPathComponent("live", isDirectory: true) }
    var staging: URL { root.appendingPathComponent("staging", isDirectory: true) }
    var old: URL { root.appendingPathComponent("old", isDirectory: true) }
    var journalURL: URL { root.appendingPathComponent("journal.json") }
    var liveStore: URL { live.appendingPathComponent("store.sqlite") }
    var stagingStore: URL { staging.appendingPathComponent("store.sqlite") }

    private func tick() throws {
        ticks += 1
        if let crashAfter, ticks == crashAfter { throw SimulatedCrash(after: ticks) }
    }

    private func moveIfNeeded(_ from: URL, _ to: URL) throws {
        guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { return }
        try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: from, to: to)
    }

    /// The ordered, idempotent publication. The caller has closed every container on `live` and checkpointed it.
    func publish(_ journal: Journal) throws {
        ticks = 0
        // 0. commit point
        try writeJournal(journal)
        try tick()
        try rollForward(journal)
    }

    /// Write-temp, fsync, rename over, fsync directory: the journal is never seen half-written.
    private func writeJournal(_ journal: Journal) throws {
        let temp = root.appendingPathComponent("journal.json.tmp")
        try JSONEncoder().encode(journal).write(to: temp)
        StoreSQLite.fullSync(temp)
        _ = try fm.replaceItemAt(journalURL, withItemAt: temp)
        StoreSQLite.fullSync(root)
    }

    private func rollForward(_ journal: Journal) throws {
        var journal = journal
        if journal.phase == "prepared" { try install(journal) ; journal.phase = "installed"; try writeJournal(journal); try tick() }
        // 4. cleanup, journal last. Only after "installed": before it, `old/` and `staging/` are still needed to resume.
        try? fm.removeItem(at: staging)
        try tick()
        try? fm.removeItem(at: old)
        try tick()
        try fm.removeItem(at: journalURL)
        StoreSQLite.fullSync(root)
        try tick()
    }

    private func install(_ journal: Journal) throws {
        // 1. displace the live store (wal, shm first so a stale wal can never meet the new main file)
        for suffix in ["-wal", "-shm", ""] {
            try moveIfNeeded(
                live.appendingPathComponent("store.sqlite" + suffix), old.appendingPathComponent("store.sqlite" + suffix)
            )
            try tick()
        }
        // 2. displace the live EPUBs the new generation replaces or removes
        for name in journal.displacedWorks {
            try moveIfNeeded(live.appendingPathComponent("Works/\(name)"), old.appendingPathComponent("Works/\(name)"))
            try tick()
        }
        // 3. install the new store, then the new EPUBs
        try moveIfNeeded(stagingStore, liveStore)
        try tick()
        for name in journal.newWorks {
            try moveIfNeeded(staging.appendingPathComponent("Works/\(name)"), live.appendingPathComponent("Works/\(name)"))
            try tick()
        }
    }

    /// Startup recovery; run before any container opens. Safe to run twice and safe to crash inside.
    func recover() throws {
        ticks = 0
        try? fm.removeItem(at: root.appendingPathComponent("journal.json.tmp")) // a commit that never happened
        if fm.fileExists(atPath: journalURL.path),
           let data = try? Data(contentsOf: journalURL),
           let journal = try? JSONDecoder().decode(Journal.self, from: data), (journal.phase == "prepared" || journal.phase == "installed") {
            try rollForward(journal)
        } else {
            try? fm.removeItem(at: staging) // never committed: the old store stands
            try? fm.removeItem(at: old)
            try? fm.removeItem(at: journalURL)
        }
    }
}
