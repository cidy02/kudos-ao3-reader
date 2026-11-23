import Foundation

nonisolated struct ManifestStagingOptions {
    /// A record or value up to this many JSON bytes is decoded with the production `Codable` type while staging.
    /// A larger one is syntax-validated and stored in chunks only (`ManifestRecordStatus.deferred`). The supported
    /// ~20 MiB recovery copy decodes at about twice its size (P1), so the default keeps it typed and bounds the rest.
    var typedRecordBudget = 32 << 20
    /// Payloads are stored as rows of at most this many bytes.
    var chunkSize = 256 << 10
    /// Where the per-run directory is created. Default: the system temporary directory.
    var parentDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ManifestStaging", isDirectory: true)
    /// Free bytes on the volume of `parentDirectory`; nil when unknown (the preflight is then skipped).
    var availableCapacity: (URL) -> Int64? = { url in
        try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    }
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

    func discard() { db.destroy() }
    deinit { db.destroy() }
}

nonisolated enum ManifestStager {
    /// Reads the whole document (validating it to EOF), stages it, and only then returns. Every thrown error is a
    /// `ManifestStreamError`, and no staging directory is left behind by a throw. Synchronous: call it off the main
    /// actor, from a `Task` so cancellation reaches it (checked at least once per 1 MiB of input).
    static func stage(_ input: ManifestInput, options: ManifestStagingOptions = .init()) throws -> ManifestStagedRun {
        let directory = options.parentDirectory.appendingPathComponent("run-\(UUID().uuidString)", isDirectory: true)
        let needed = Int64(input.length) + Int64(input.length / 4) + (16 << 20)
        try? FileManager.default.createDirectory(at: options.parentDirectory, withIntermediateDirectories: true)
        if let free = options.availableCapacity(options.parentDirectory), free < needed {
            throw ManifestStreamError.resourceExhausted("need \(needed) bytes to stage, \(free) free")
        }
        var db: ManifestStagingDB?
        do {
            let opened = try ManifestStagingDB(directory: directory)
            db = opened
            let version = try ManifestStagingPass(input: input, db: opened, options: options).run()
            return ManifestStagedRun(db: opened, version: version, sourceLength: input.length)
        } catch {
            db?.destroy()
            try? FileManager.default.removeItem(at: directory)
            throw translate(error, input: input)
        }
    }

    private static func translate(_ error: Error, input: ManifestInput) -> ManifestStreamError {
        if let e = error as? ManifestStreamError { return e }
        if Task.isCancelled { return .cancelled }
        if let failure = input.failure { return .io(failure) }
        if let scan = error as? ManifestScanError { return scan == .cancelled ? .cancelled : .invalidDocument(.notJSON) }
        return .io(String(describing: error))
    }

    /// Deletes staging directories a crashed run left behind (call at launch, before any run starts).
    static func removeStale(in parent: URL = ManifestStagingOptions().parentDirectory, olderThan age: TimeInterval = 3600) {
        let urls = (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for url in urls where url.lastPathComponent.hasPrefix("run-") {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(modified) > age { try? FileManager.default.removeItem(at: url) }
        }
    }
}

/// One pass over the document: validates it and stages each record as it goes. Staging before the end is safe because
/// the database is private and thrown away on any failure.
nonisolated final class ManifestStagingPass {
    private let input: ManifestInput
    private let db: ManifestStagingDB
    private let options: ManifestStagingOptions
    private let decoder = KudosBackupContents.makeDecoder()
    private var tokenizer: ManifestTokenizer
    private var seen: Set<String> = []
    private var presence: [String: ManifestPresence] = [:]
    private var ord = 0
    private var schemaFailed = false
    private var version: Int?
    private var pendingRows = 0

    init(input: ManifestInput, db: ManifestStagingDB, options: ManifestStagingOptions) {
        self.input = input
        self.db = db
        self.options = options
        tokenizer = ManifestTokenizer(input: input)
    }

    /// Returns the manifest `version`; throws a `ManifestStreamError` or a `ManifestScanError`.
    func run() throws -> Int {
        try createSchema()
        try db.exec("BEGIN")
        tokenizer.skipBOM()
        tokenizer.skipWhitespace()
        guard tokenizer.peek() == UInt8(ascii: "{") else {
            let (kind, _) = try tokenizer.skipValue()
            try tokenizer.expectEnd()
            // `JSONSerialization` takes only an object or an array at the top level; an array is JSON but not a manifest.
            throw ManifestStreamError.invalidDocument(kind == .array ? .schema : .notJSON)
        }
        tokenizer.pos += 1
        try scanMembers()
        try tokenizer.expectEnd()
        if let failure = input.failure { throw ManifestStreamError.io(failure) }

        for spec in ManifestSectionSpec.all where presence[spec.name] == nil { try recordMember(spec.name, .missing, nil, 0, 0) }
        for spec in ManifestValueSpec.all where presence[spec.name] == nil { try recordMember(spec.name, .missing, nil, 0, 0) }
        for name in ["version", "exportedAt", "settings"] where presence[name] != .present { schemaFailed = true }
        for spec in ManifestSectionSpec.all where spec.policy == .required && presence[spec.name] != .present { schemaFailed = true }
        if schemaFailed { throw ManifestStreamError.invalidDocument(.schema) }
        guard let version else { throw ManifestStreamError.invalidDocument(.schema) }
        guard KudosBackupManifest.supportedVersions.contains(version) else { throw ManifestStreamError.unsupportedVersion(version) }
        try db.exec("COMMIT")
        try createIndexes()
        return version
    }

    // MARK: Walk

    private func scanMembers() throws {
        tokenizer.skipWhitespace()
        if tokenizer.peek() == UInt8(ascii: "}") { tokenizer.pos += 1; return }
        while true {
            tokenizer.skipWhitespace()
            guard tokenizer.peek() == UInt8(ascii: "\"") else { throw tokenizer.fail("object key") }
            let keyRange = try tokenizer.skipString()
            tokenizer.skipWhitespace()
            guard tokenizer.peek() == UInt8(ascii: ":") else { throw tokenizer.fail("colon") }
            tokenizer.pos += 1
            let key = decodeKey(keyRange)
            if !seen.insert(key).inserted {
                _ = try tokenizer.skipValue(depth: 1) // a duplicate key: the first value wins (validated, not staged)
            } else if let section = ManifestSectionSpec.byName[key] {
                try stageArray(section)
            } else if let value = ManifestValueSpec.byName[key] {
                try stageValue(value)
            } else {
                let (kind, range) = try tokenizer.skipValue(depth: 1)
                try recordMember(key, kind == .null ? .null : .present, kind, 0, range.count, known: false)
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

    private func decodeKey(_ range: Range<Int>) -> String {
        guard range.count <= 4096 else { return "\u{0}long" } // no key of ours is this long
        let bytes = input.read(range)
        if !bytes.contains(UInt8(ascii: "\\")) { return String(decoding: bytes.dropFirst().dropLast(), as: UTF8.self) }
        return (try? JSONSerialization.jsonObject(with: bytes, options: .fragmentsAllowed) as? String) ?? "\u{0}invalid"
    }

    private func stageValue(_ spec: ManifestValueSpec) throws {
        let (kind, range) = try tokenizer.skipValue(depth: 1)
        if kind == .null {
            if spec.isRequired { schemaFailed = true }
            try recordMember(spec.name, .null, kind, 0, range.count)
            return
        }
        if !schemaFailed {
            if range.count > options.typedRecordBudget {
                try storeChunks(owner: spec.name, seq: 0, from: range)
            } else {
                let data = input.read(range)
                if let failure = input.failure { throw ManifestStreamError.io(failure) }
                if spec.decodes(decoder, data) {
                    if spec.name == "version" { version = try? decoder.decode(Int.self, from: data) }
                    try storeChunks(owner: spec.name, seq: 0, data: data)
                } else {
                    schemaFailed = true
                }
            }
        }
        try recordMember(spec.name, .present, kind, 1, range.count)
    }

    private func stageArray(_ spec: ManifestSectionSpec) throws {
        tokenizer.skipWhitespace()
        guard tokenizer.peek() == UInt8(ascii: "[") else {
            let (kind, range) = try tokenizer.skipValue(depth: 1)
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
                try stageElement(spec, seq: count, range: range)
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

    private func stageElement(_ spec: ManifestSectionSpec, seq: Int, range: Range<Int>) throws {
        guard !schemaFailed else { return } // the document is already known to be a schema failure; keep validating syntax
        if range.count > options.typedRecordBudget {
            try insertRecord(spec, seq, .deferred, range.count, .init())
            try storeChunks(owner: spec.name, seq: seq, from: range)
            return
        }
        let data = input.read(range)
        if let failure = input.failure { throw ManifestStreamError.io(failure) }
        if let keys = spec.decode(decoder, data) {
            try insertRecord(spec, seq, .decoded, range.count, keys)
            try storeChunks(owner: spec.name, seq: seq, data: data)
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
        CREATE TABLE payload (id INTEGER PRIMARY KEY, owner TEXT NOT NULL, seq INTEGER NOT NULL, chunk INTEGER NOT NULL, bytes BLOB NOT NULL);
        """
        for spec in ManifestSectionSpec.all {
            sql += "CREATE TABLE \(spec.table) (seq INTEGER PRIMARY KEY, status INTEGER NOT NULL, length INTEGER NOT NULL, "
                + ManifestRecordKeys.columns.map { "\($0) \($0 == "k_ao3" ? "INTEGER" : $0 == "k_stamp" ? "REAL" : "TEXT")" }.joined(separator: ", ") + ");"
        }
        try db.exec(sql)
    }

    private func createIndexes() throws {
        var sql = "CREATE UNIQUE INDEX payload_key ON payload(owner, seq, chunk);"
        for spec in ManifestSectionSpec.all {
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
    }

    private func insertRecord(_ spec: ManifestSectionSpec, _ seq: Int, _ status: ManifestRecordStatus, _ length: Int,
                              _ keys: ManifestRecordKeys) throws {
        let marks = Array(repeating: "?", count: 3 + ManifestRecordKeys.columns.count).joined(separator: ", ")
        try db.run("INSERT INTO \(spec.table) VALUES (\(marks))", [.int(Int64(seq)), .int(Int64(status.rawValue)), .int(Int64(length))] + keys.binds)
        try rowWritten()
    }

    private func storeChunks(owner: String, seq: Int, data: Data) throws {
        var chunk = 0
        var offset = 0
        repeat {
            let n = min(options.chunkSize, data.count - offset)
            try data.withUnsafeBytes {
                try db.run("INSERT INTO payload (owner, seq, chunk, bytes) VALUES (?, ?, ?, ?)",
                           [.text(owner), .int(Int64(seq)), .int(Int64(chunk)), .blob(UnsafeRawBufferPointer(rebasing: $0[offset ..< offset + n]))])
            }
            chunk += 1
            offset += n
        } while offset < data.count
        try rowWritten()
    }

    /// An oversized value: copied window by window, never held whole.
    private func storeChunks(owner: String, seq: Int, from range: Range<Int>) throws {
        var chunk = 0
        try input.forEachChunk(of: range, size: options.chunkSize) { piece in
            try db.run("INSERT INTO payload (owner, seq, chunk, bytes) VALUES (?, ?, ?, ?)",
                       [.text(owner), .int(Int64(seq)), .int(Int64(chunk)), .blob(piece)])
            chunk += 1
            try rowWritten()
        }
        if let failure = input.failure { throw ManifestStreamError.io(failure) }
    }

    /// Commits in batches so the open transaction (and SQLite's cache) stays small however large the document is.
    private func rowWritten() throws {
        pendingRows += 1
        guard pendingRows >= 2000 else { return }
        pendingRows = 0
        try db.exec("COMMIT; BEGIN")
    }
}
