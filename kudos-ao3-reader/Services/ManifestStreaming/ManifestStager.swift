import Foundation

nonisolated struct ManifestStagingOptions {
    /// A record or value up to this many source bytes is decoded with the production `Codable` type while staging.
    /// A larger lossy element is syntax-validated and stored in chunks (`ManifestRecordStatus.deferred`). A larger strict
    /// record or value is resource exhaustion, decided when the run reaches EOF (so a malformed tail still reports its own
    /// class first). The supported ~20 MiB recovery copy decodes at about twice its size (P1), so the default keeps it typed.
    var typedRecordBudget = 8 << 20
    /// Same for one single-value member (`settings`, `pronunciations`); the root-value limit (16 MiB) is its natural ceiling.
    var typedValueBudget = ManifestLimits.maxRootValueBytes
    /// Payloads are stored as rows of at most this many bytes.
    var chunkSize = 256 << 10
    /// Where the per-run directory is created. Default: the system temporary directory.
    var parentDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ManifestStaging", isDirectory: true)
    /// Free bytes on the volume of `parentDirectory`; nil when unknown (the checks are then skipped).
    var availableCapacity: (URL) -> Int64? = { url in
        try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    }
    /// Staging disk use as a multiple of the manifest (measured high-water on the P1 fixtures: 1.7x; indexes included).
    var diskFactor = 1.7
    /// Free space that must remain at the end (the last commit and a safety margin).
    var diskFloor: Int64 = 16 << 20
}

/// Directories of runs in this process that are still open, so a startup sweep never deletes a live run.
nonisolated enum ManifestActiveRuns {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var names: Set<String> = []
    nonisolated(unsafe) private static var failures: [String] = []
    static func add(_ name: String) { lock.lock(); names.insert(name); lock.unlock() }
    static func remove(_ name: String) { lock.lock(); names.remove(name); lock.unlock() }
    static func contains(_ name: String) -> Bool { lock.lock(); defer { lock.unlock() }; return names.contains(name) }
    static func recordFailure(_ message: String) { lock.lock(); failures.append(message); lock.unlock() }
    /// Cleanup that failed (a directory that could not be deleted), for surfacing and for the next sweep to retry.
    static var cleanupFailures: [String] { lock.lock(); defer { lock.unlock() }; return failures }
    static func clearFailures() { lock.lock(); failures.removeAll(); lock.unlock() }
}

/// A validated manifest, staged in a private SQLite database. Owns its directory: `discard()` (or deinit) removes it.
nonisolated final class ManifestStagedRun {
    let db: ManifestStagingDB
    let version: Int
    let sourceLength: Int

    init(db: ManifestStagingDB, version: Int, sourceLength: Int) {
        self.db = db
        self.version = version
        self.sourceLength = sourceLength
    }

    /// Removes the run. A deletion failure is returned (and remembered for the next sweep), never swallowed.
    @discardableResult
    func discard() -> Error? {
        ManifestActiveRuns.remove(db.directory.lastPathComponent)
        let failure = db.destroy()
        if let failure { ManifestActiveRuns.recordFailure("\(db.directory.path): \(failure)") }
        return failure
    }

    deinit { discard() }
}

nonisolated enum ManifestStager {
    /// Reads the whole document (validating it to EOF), stages it, and only then returns. Every thrown error is a
    /// `ManifestStreamError`, and no staging directory is left behind by a throw. Synchronous: call it off the main
    /// actor, from a `Task` so cancellation reaches it (polled in every unbounded loop, at least once per 1 MiB of input).
    /// Outcome precedence, decided at EOF: I/O > cancellation > syntax > resource > schema > unsupported version.
    static func stage(_ input: ManifestInput, options: ManifestStagingOptions = .init()) throws -> ManifestStagedRun {
        let directory = options.parentDirectory.appendingPathComponent("run-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: options.parentDirectory, withIntermediateDirectories: true)
        } catch {
            throw ManifestStreamError.io("staging folder: \(error.localizedDescription)")
        }
        let needed = Int64(Double(input.length) * options.diskFactor) + options.diskFloor
        if let free = options.availableCapacity(options.parentDirectory), free < needed {
            throw ManifestStreamError.resourceExhausted("need \(needed) bytes to stage, \(free) free")
        }
        ManifestActiveRuns.add(directory.lastPathComponent)
        var db: ManifestStagingDB?
        do {
            let opened = try ManifestStagingDB(directory: directory)
            db = opened
            let version = try ManifestStagingPass(input: input, db: opened, options: options).run()
            return ManifestStagedRun(db: opened, version: version, sourceLength: input.length)
        } catch {
            ManifestActiveRuns.remove(directory.lastPathComponent)
            var failure: Error?
            if let db { failure = db.destroy() } else if FileManager.default.fileExists(atPath: directory.path) {
                do { try FileManager.default.removeItem(at: directory) } catch { failure = error }
            }
            if let failure { ManifestActiveRuns.recordFailure("\(directory.path): \(failure)") }
            throw translate(error, input: input)
        }
    }

    private static func translate(_ error: Error, input: ManifestInput) -> ManifestStreamError {
        if let failure = input.failure { return .io(failure) } // a failed read can look like any syntax error
        if Task.isCancelled { return .cancelled }
        if let e = error as? ManifestStreamError { return e }
        if let scan = error as? ManifestScanError {
            switch scan {
            case .cancelled: return .cancelled
            case .tooDeep: return .invalidDocument(.depth)
            default: return .invalidDocument(.notJSON)
            }
        }
        return .io(String(describing: error))
    }

    /// Deletes staging directories a crashed run left behind (call at launch, before any run starts). Runs open in this
    /// process are never touched. Returns what could not be deleted.
    @discardableResult
    static func removeStale(in parent: URL = ManifestStagingOptions().parentDirectory, olderThan age: TimeInterval = 3600) -> [(URL, Error)] {
        var failures: [(URL, Error)] = []
        let urls = (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for url in urls where url.lastPathComponent.hasPrefix("run-") && !ManifestActiveRuns.contains(url.lastPathComponent) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            guard Date().timeIntervalSince(modified) > age else { continue }
            do { try FileManager.default.removeItem(at: url) } catch { failures.append((url, error)) }
        }
        if failures.isEmpty { ManifestActiveRuns.clearFailures() }
        return failures
    }
}

/// One pass over the document: validates it and stages each record as it goes. Staging before the end is safe because
/// the database is private and thrown away on any failure.
nonisolated final class ManifestStagingPass {
    private let input: ManifestInput
    private let db: ManifestStagingDB
    private let options: ManifestStagingOptions
    private let decoder = KudosBackupContents.makeDecoder()
    private let encoder: JSONEncoder = {
        let e = KudosBackupContents.makeEncoder()
        e.outputFormatting = []
        return e
    }()
    private var tokenizer: ManifestTokenizer
    private var presence: [String: ManifestPresence] = [:]
    private var ord = 0
    private var schemaFailed = false
    private var version: Int?
    private var pendingRows = 0
    private var pendingBytes = 0

    init(input: ManifestInput, db: ManifestStagingDB, options: ManifestStagingOptions) {
        self.input = input
        self.db = db
        self.options = options
        tokenizer = ManifestTokenizer(input: input)
    }

    /// Whatever has gone wrong so far, staging more would not change the outcome: keep scanning, stop writing.
    private var abandoned: Bool { schemaFailed || tokenizer.limitHit != nil || tokenizer.depthExceeded }

    /// Returns the manifest `version`; throws a `ManifestStreamError` or a `ManifestScanError`.
    func run() throws -> Int {
        try createSchema()
        try db.exec("BEGIN")
        tokenizer.skipBOM()
        tokenizer.skipWhitespace()
        var rootKind = ManifestValueKind.object
        if tokenizer.peek() == UInt8(ascii: "{") {
            tokenizer.pos += 1
            try scanMembers()
            try tokenizer.expectEnd()
        } else {
            (rootKind, _) = try tokenizer.skipValue()
            try tokenizer.expectEnd()
        }
        // EOF reached. Decide in precedence order: I/O > cancellation > syntax (thrown above) > resource > schema.
        if let failure = input.failure { throw ManifestStreamError.io(failure) }
        if Task.isCancelled { throw ManifestStreamError.cancelled }
        if let message = tokenizer.limitHit { throw ManifestStreamError.resourceExhausted(message) }
        if tokenizer.depthExceeded { throw ManifestStreamError.invalidDocument(.depth) }
        // `JSONSerialization` takes only an object or an array at the top level; an array is JSON but not a manifest.
        if rootKind != .object { throw ManifestStreamError.invalidDocument(rootKind == .array ? .schema : .notJSON) }

        for spec in ManifestSectionSpec.all where presence[spec.name] == nil { try recordMember(spec.name, .missing, nil, 0, 0) }
        for spec in ManifestValueSpec.all where presence[spec.name] == nil { try recordMember(spec.name, .missing, nil, 0, 0) }
        for name in ["version", "exportedAt", "settings"] where presence[name] != .present { schemaFailed = true }
        for spec in ManifestSectionSpec.all where spec.policy == .required && presence[spec.name] != .present { schemaFailed = true }
        if schemaFailed { throw ManifestStreamError.invalidDocument(.schema) }
        guard let version else { throw ManifestStreamError.invalidDocument(.schema) }
        guard KudosBackupManifest.supportedVersions.contains(version) else { throw ManifestStreamError.unsupportedVersion(version) }
        try db.exec("COMMIT")
        try checkDisk(final: true)
        if Task.isCancelled { throw ManifestStreamError.cancelled } // not even a finished run is handed over after cancellation
        return version
    }

    // MARK: Walk

    private func scanMembers() throws {
        var scan = ManifestObjectScan()
        defer { tokenizer.release(scan) }
        tokenizer.skipWhitespace()
        if tokenizer.peek() == UInt8(ascii: "}") { tokenizer.pos += 1; return }
        while true {
            tokenizer.skipWhitespace()
            guard tokenizer.peek() == UInt8(ascii: "\"") else { throw tokenizer.fail("object key") }
            let keyRange = try tokenizer.skipString()
            let (units, duplicate) = try tokenizer.noteKey(keyRange, in: &scan)
            tokenizer.skipWhitespace()
            guard tokenizer.peek() == UInt8(ascii: ":") else { throw tokenizer.fail("colon") }
            tokenizer.pos += 1
            if duplicate || units == nil {
                // A later duplicate (first wins), or a run already abandoned for a limit: validated, not staged.
                _ = try tokenizer.skipValue(depth: 1)
                _ = tokenizer.takeRemovals()
            } else if let units {
                let key = String(decoding: units, as: UTF16.self)
                if let section = ManifestSectionSpec.byName[key] {
                    try stageArray(section)
                } else if let value = ManifestValueSpec.byName[key] {
                    try stageValue(value)
                } else {
                    let (kind, range) = try tokenizer.skipValue(depth: 1)
                    _ = tokenizer.takeRemovals()
                    if key == "exportedBy", range.count > ManifestLimits.maxRootValueBytes { noteRootValueTooLarge(key, range.count) }
                    if !abandoned { try recordMember(key, kind == .null ? .null : .present, kind, 0, range.count, known: false) }
                }
            }
            ord += 1
            tokenizer.skipWhitespace()
            guard let c = tokenizer.peek() else { throw ManifestScanError.unexpectedEnd }
            tokenizer.pos += 1
            if c == UInt8(ascii: "}") { return }
            guard c == UInt8(ascii: ",") else { throw tokenizer.fail("object separator") }
            tokenizer.skipWhitespace()
            if tokenizer.peek() == UInt8(ascii: "}") { tokenizer.pos += 1; return } // a trailing comma, as today's route
        }
    }

    private func noteRootValueTooLarge(_ name: String, _ bytes: Int) {
        tokenizer.noteLimit("\(name) is \(bytes) source bytes, over \(ManifestLimits.maxRootValueBytes)")
    }

    /// A record's bytes with every later duplicate member cut out, so the typed decoder sees first-wins at every depth
    /// whatever Foundation would do with a repeated key.
    private func firstWins(_ data: Data, base: Int, cuts: [Range<Int>]) -> Data {
        guard !cuts.isEmpty else { return data }
        let sorted = cuts.sorted { $0.lowerBound != $1.lowerBound ? $0.lowerBound < $1.lowerBound : $0.upperBound > $1.upperBound }
        var out = Data(capacity: data.count)
        var cursor = base
        for cut in sorted where cut.lowerBound >= cursor { // a cut inside an earlier cut is already gone
            out.append(data[(cursor - base) ..< (cut.lowerBound - base)])
            cursor = cut.upperBound
        }
        out.append(data[(cursor - base)...])
        return out
    }

    private func stageValue(_ spec: ManifestValueSpec) throws {
        let (kind, range) = try tokenizer.skipValue(depth: 1)
        let cuts = tokenizer.takeRemovals()
        if range.count > ManifestLimits.maxRootValueBytes { noteRootValueTooLarge(spec.name, range.count) }
        if kind == .null {
            if spec.isRequired { schemaFailed = true }
            try recordMember(spec.name, .null, kind, 0, range.count)
            return
        }
        if range.count > options.typedValueBudget { tokenizer.noteLimit("\(spec.name) of \(range.count) bytes exceeds the typed-decode budget") }
        if !abandoned {
            let data = firstWins(input.read(range), base: range.lowerBound, cuts: cuts)
            if let failure = input.failure { throw ManifestStreamError.io(failure) }
            if spec.decodes(decoder, data) {
                if spec.name == "version" { version = try? decoder.decode(Int.self, from: data) }
                try storeChunks(owner: spec.name, seq: 0, data: data)
            } else {
                schemaFailed = true
            }
        }
        try recordMember(spec.name, .present, kind, 1, range.count)
    }

    private func stageArray(_ spec: ManifestSectionSpec) throws {
        tokenizer.skipWhitespace()
        guard tokenizer.peek() == UInt8(ascii: "[") else {
            let (kind, range) = try tokenizer.skipValue(depth: 1)
            _ = tokenizer.takeRemovals()
            if range.count > ManifestLimits.maxRootValueBytes { noteRootValueTooLarge(spec.name, range.count) } // wrong kind: a bounded value
            let shape: ManifestPresence = kind == .null ? .null : .wrongKind
            if shape == .null ? spec.policy == .required : spec.policy != .lossy { schemaFailed = true }
            try recordMember(spec.name, shape, kind, 0, range.count)
            return
        }
        let start = tokenizer.pos
        tokenizer.pos += 1
        var count = 0
        tokenizer.skipWhitespace()
        if tokenizer.peek() == UInt8(ascii: "]") {
            tokenizer.pos += 1
        } else {
            elements: while true {
                let (_, range) = try tokenizer.skipValue(depth: 2)
                try stageElement(spec, seq: count, range: range, cuts: tokenizer.takeRemovals())
                count += 1
                tokenizer.skipWhitespace()
                guard let c = tokenizer.peek() else { throw ManifestScanError.unexpectedEnd }
                tokenizer.pos += 1
                if c == UInt8(ascii: "]") { break elements }
                guard c == UInt8(ascii: ",") else { throw tokenizer.fail("array separator") }
                tokenizer.skipWhitespace()
                if tokenizer.peek() == UInt8(ascii: "]") { tokenizer.pos += 1; break elements } // trailing comma
            }
        }
        try recordMember(spec.name, .present, .array, count, tokenizer.pos - start)
    }

    private func stageElement(_ spec: ManifestSectionSpec, seq: Int, range: Range<Int>, cuts: [Range<Int>]) throws {
        // The budget is checked before anything else, so the outcome does not depend on member order or an earlier schema error.
        if range.count > options.typedRecordBudget, spec.policy != .lossy {
            // A strict record must decode with the production type, and an oversized one cannot be decoded within budget
            // (P4 may stream it field by field): never accepted, reported at EOF after a malformed or unreadable tail.
            tokenizer.noteLimit("\(spec.name) record of \(range.count) bytes exceeds the typed-decode budget")
            return
        }
        guard !abandoned else { return } // keep validating syntax, write nothing more
        if range.count > options.typedRecordBudget {
            // Lossy: deferred, kept out of matching (no natural keys) until a reader decodes or skips it.
            try insertRecord(spec, seq, .deferred, range.count, .init())
            try storeChunks(owner: spec.name, seq: seq, from: range)
            return
        }
        let data = firstWins(input.read(range), base: range.lowerBound, cuts: cuts)
        if let failure = input.failure { throw ManifestStreamError.io(failure) }
        if let (keys, canonical) = spec.decode(decoder, encoder, data) {
            let stored = canonical ?? data
            try insertRecord(spec, seq, .decoded, stored.count, keys)
            try storeChunks(owner: spec.name, seq: seq, data: stored)
        } else if spec.policy == .lossy {
            try insertRecord(spec, seq, .undecodable, range.count, .init())
        } else {
            schemaFailed = true
        }
    }

    // MARK: Writes

    private func createSchema() throws {
        var sql = """
        CREATE TABLE member (name TEXT PRIMARY KEY, ord INTEGER, known INTEGER, presence INTEGER, kind TEXT, count INTEGER, length INTEGER);
        CREATE TABLE payload (id INTEGER PRIMARY KEY, owner TEXT NOT NULL, seq INTEGER NOT NULL, off INTEGER NOT NULL, bytes BLOB NOT NULL);
        CREATE UNIQUE INDEX payload_key ON payload(owner, seq, off);
        """
        for spec in ManifestSectionSpec.all {
            sql += "CREATE TABLE \(spec.table) (seq INTEGER PRIMARY KEY, status INTEGER NOT NULL, length INTEGER NOT NULL, "
                + ManifestRecordKeys.columns.map { "\($0) \($0 == "k_ao3" ? "INTEGER" : $0 == "k_stamp" ? "REAL" : "TEXT")" }.joined(separator: ", ") + ");"
            // Built up front: incremental inserts stay inside the page cache, whereas a bulk build at the end (sorter) peaked above it.
            for column in spec.indexed { sql += "CREATE INDEX \(spec.table)_\(column) ON \(spec.table)(\(column));" }
        }
        try db.exec(sql)
    }

    private func recordMember(_ name: String, _ shape: ManifestPresence, _ kind: ManifestValueKind?, _ count: Int, _ length: Int,
                              known: Bool = true) throws {
        presence[name] = shape
        let kindName = kind.map { "\($0)" }
        try db.run("INSERT INTO member VALUES (?, ?, ?, ?, ?, ?, ?)", [
            .text(name), shape == .missing ? .null : .int(Int64(ord)), .int(known ? 1 : 0), .int(Int64(shape.rawValue)),
            kindName.map { .text($0) } ?? .null, .int(Int64(count)), .int(Int64(length)),
        ])
        try rowWritten()
    }

    private func insertRecord(_ spec: ManifestSectionSpec, _ seq: Int, _ status: ManifestRecordStatus, _ length: Int,
                              _ keys: ManifestRecordKeys) throws {
        let marks = Array(repeating: "?", count: 3 + ManifestRecordKeys.columns.count).joined(separator: ", ")
        try db.run("INSERT INTO \(spec.table) VALUES (\(marks))", [.int(Int64(seq)), .int(Int64(status.rawValue)), .int(Int64(length))] + keys.binds)
        try rowWritten()
    }

    private func insertChunk(_ owner: String, _ seq: Int, _ off: Int, _ data: Data) throws {
        if Task.isCancelled { throw ManifestScanError.cancelled }
        try data.withUnsafeBytes {
            try db.run("INSERT INTO payload (owner, seq, off, bytes) VALUES (?, ?, ?, ?)",
                       [.text(owner), .int(Int64(seq)), .int(Int64(off)), .blob($0)])
        }
        try rowWritten(bytes: data.count)
    }

    private func storeChunks(owner: String, seq: Int, data: Data) throws {
        var offset = 0
        repeat {
            let n = min(options.chunkSize, data.count - offset)
            try insertChunk(owner, seq, offset, data.subdata(in: offset ..< offset + n))
            offset += n
        } while offset < data.count
    }

    /// An oversized value: copied piece by piece, never held whole.
    private func storeChunks(owner: String, seq: Int, from range: Range<Int>) throws {
        var offset = 0
        try input.forEachChunk(of: range, size: options.chunkSize) { piece in
            try insertChunk(owner, seq, offset, piece)
            offset += piece.count
        }
        if let failure = input.failure { throw ManifestStreamError.io(failure) }
    }

    /// Commits in batches so the open transaction (and SQLite's cache) stays small however large the document is, and
    /// rechecks free space at each batch boundary.
    private func rowWritten(bytes: Int = 0) throws {
        pendingRows += 1
        pendingBytes += bytes
        guard pendingRows >= 2000 || pendingBytes >= 16 << 20 else { return }
        pendingRows = 0
        pendingBytes = 0
        try db.exec("COMMIT; BEGIN")
        try checkDisk(final: false)
    }

    /// Free space must cover the rest of the document at the measured staging rate, and the safety floor at the end.
    private func checkDisk(final: Bool) throws {
        let remaining = final ? 0 : max(0, input.length - tokenizer.pos)
        let needed = Int64(Double(remaining) * options.diskFactor) + options.diskFloor
        if let free = options.availableCapacity(db.directory.deletingLastPathComponent()), free < needed {
            throw ManifestStreamError.resourceExhausted("need \(needed) more bytes to finish staging, \(free) free")
        }
    }
}
