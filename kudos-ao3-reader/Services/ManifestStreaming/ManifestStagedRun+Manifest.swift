import Foundation

extension KudosBackupManifest {
    /// Assembles a manifest from decoded pieces exactly as `init(from:)` would: no memberwise-init normalisation
    /// (an empty `followedTags` stays `[]`), and `omittedKeys` as given.
    nonisolated init(
        version: Int, exportedAt: Date, works: [KudosBackupWork], bookmarks: [KudosBackupBookmark], fonts: [KudosBackupFont],
        collections: [KudosBackupCollection], readingQueues: [KudosBackupReadingQueue],
        readingQueueMemberships: [KudosBackupReadingQueueMembership], annotations: [KudosBackupAnnotation],
        savedSearches: [KudosBackupSavedSearch], readingSessions: [KudosBackupReadingSession]?,
        readingFavorites: [KudosBackupReadingFavorite]?, fandomReadWatermarks: [KudosBackupFandomReadWatermark]?,
        followedTags: [KudosBackupFollowedTag]?, tagAliases: [KudosBackupTagAlias]?, settings: KudosBackupSettings,
        pronunciations: KudosBackupPronunciations, tombstones: [KudosBackupTombstone],
        writingRecovery: [KudosBackupRecoveryCopy]?, documents: [KudosBackupDocument]?, omittedKeys: Set<String>
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.works = works
        self.bookmarks = bookmarks
        self.fonts = fonts
        self.collections = collections
        self.readingQueues = readingQueues
        self.readingQueueMemberships = readingQueueMemberships
        self.annotations = annotations
        self.savedSearches = savedSearches
        self.readingSessions = readingSessions
        self.readingFavorites = readingFavorites
        self.fandomReadWatermarks = fandomReadWatermarks
        self.followedTags = followedTags
        self.tagAliases = tagAliases
        self.settings = settings
        self.pronunciations = pronunciations
        self.tombstones = tombstones
        self.writingRecovery = writingRecovery
        self.documents = documents
        self.omittedKeys = omittedKeys
    }
}

/// What a section looked like in the document, for Replace-style decisions that treat absent, `null` and empty differently.
nonisolated enum ManifestSectionShape: Equatable {
    case missing, null, empty, nonEmpty(count: Int), wrongKind
}

nonisolated struct ManifestRecordMeta {
    let seq: Int
    let status: ManifestRecordStatus
    /// Stored payload bytes.
    let length: Int
    let keys: ManifestRecordKeys
}

/// Reading a staged run back. The consumption path is bounded: `forEachRecordMeta` pages row metadata by keyset and
/// `readPayload` streams any byte range of a record to a sink from indexed chunk offsets. `manifest()` is the whole-document
/// oracle used to prove staging lost nothing, and is not memory-bounded. Semantic validation (identity uniqueness, tombstone
/// matching, clocks) runs over the final metadata, after staging has finished and before any mutation or sweep.
extension ManifestStagedRun {
    func presence(of name: String) throws -> ManifestPresence {
        var shape = ManifestPresence.missing
        try db.query("SELECT presence FROM member WHERE name = ?", [.text(name)]) { shape = ManifestPresence(rawValue: $0.int(0)) ?? .missing }
        return shape
    }

    /// Present / missing / `null` / `[]` / wrong kind for a section, the presence-aware view an apply decision needs.
    func shape(of name: String) throws -> ManifestSectionShape {
        var out = ManifestSectionShape.missing
        try db.query("SELECT presence, count FROM member WHERE name = ?", [.text(name)]) { r in
            switch ManifestPresence(rawValue: r.int(0)) ?? .missing {
            case .missing: out = .missing
            case .null: out = .null
            case .wrongKind: out = .wrongKind
            case .present: out = r.int(1) == 0 ? .empty : .nonEmpty(count: r.int(1))
            }
        }
        return out
    }

    /// Member names in source order (known and unknown), first occurrence of each. Unknown names are bounded by the key limits.
    func memberNames() throws -> [String] {
        var names: [String] = []
        try db.query("SELECT name FROM member WHERE ord IS NOT NULL ORDER BY ord") { names.append($0.text(0)) }
        return names
    }

    /// One page of row metadata in source order, after `seq` (keyset: no OFFSET, no whole-section array).
    func recordPage(of section: String, after seq: Int = -1, limit: Int = 1000) throws -> [ManifestRecordMeta] {
        guard let spec = ManifestSectionSpec.byName[section] else { return [] }
        var out: [ManifestRecordMeta] = []
        let columns = ManifestRecordKeys.columns.joined(separator: ", ")
        try db.query("SELECT seq, status, length, \(columns) FROM \(spec.table) WHERE seq > ? ORDER BY seq LIMIT ?", [.int(Int64(seq)), .int(Int64(limit))]) { r in
            var keys = ManifestRecordKeys()
            keys.id = r.isNull(3) ? nil : r.text(3)
            keys.work = r.isNull(4) ? nil : r.text(4)
            keys.ref = r.isNull(5) ? nil : r.text(5)
            keys.ao3 = r.isNull(6) ? nil : r.int(6)
            keys.url = r.isNull(7) ? nil : r.text(7)
            keys.name = r.isNull(8) ? nil : r.text(8)
            keys.text = r.isNull(9) ? nil : r.text(9)
            keys.text2 = r.isNull(10) ? nil : r.text(10)
            keys.stamp = r.isNull(11) ? nil : r.double(11)
            out.append(ManifestRecordMeta(seq: r.int(0), status: ManifestRecordStatus(rawValue: r.int(1)) ?? .decoded, length: r.int(2), keys: keys))
        }
        return out
    }

    /// Every row of a section, a page at a time.
    func forEachRecordMeta(of section: String, pageSize: Int = 1000, _ body: (ManifestRecordMeta) throws -> Void) throws {
        var last = -1
        while true {
            let page = try recordPage(of: section, after: last, limit: pageSize)
            for meta in page { try body(meta) }
            guard let end = page.last, page.count == pageSize else { return }
            last = end.seq
        }
    }

    /// Streams bytes `range` (all of it when nil) of one stored record to `sink`, in order, a stored chunk at a time (clipped to
    /// the range). Nothing larger than a chunk is ever held, so an oversized value is consumed without being assembled.
    func readPayload(of owner: String, seq: Int, range: Range<Int>? = nil, into sink: (Data) throws -> Void) throws {
        let lower = range?.lowerBound ?? 0, upper = range?.upperBound ?? Int.max
        try db.query("SELECT off, bytes FROM payload WHERE owner = ? AND seq = ? AND off < ? AND off + length(bytes) > ? ORDER BY off",
                     [.text(owner), .int(Int64(seq)), .int(Int64(min(upper, Int(Int64.max)))), .int(Int64(lower))]) { r in
            let off = r.int(0)
            let bytes = r.data(1)
            let from = max(lower - off, 0), to = min(upper - off, bytes.count)
            try sink(from == 0 && to == bytes.count ? bytes : bytes.subdata(in: from ..< to))
        }
    }

    /// The oracle form: one whole record at a time. For records within the typed budget (and for the whole-document rebuild).
    func forEachPayload(of owner: String, _ body: (_ seq: Int, _ bytes: Data) throws -> Void) throws {
        var current = -1
        var buffer = Data()
        try db.query("SELECT seq, bytes FROM payload WHERE owner = ? ORDER BY seq, off", [.text(owner)]) { r in
            if r.int(0) != current {
                if current >= 0 { try body(current, buffer) }
                current = r.int(0)
                buffer = Data()
            }
            buffer.append(r.data(1))
        }
        if current >= 0 { try body(current, buffer) }
    }

    /// Rebuilds the `KudosBackupManifest` that `KudosBackupContents.decodeManifest` returns for the staged bytes.
    func manifest() throws -> KudosBackupManifest {
        let decoder = KudosBackupContents.makeDecoder()
        func value<T: Decodable>(_ name: String, _: T.Type) throws -> T? {
            var out: T?
            try forEachPayload(of: name) { _, bytes in out = try decoder.decode(T.self, from: bytes) }
            return out
        }
        func array<T: Decodable>(_ name: String, _: T.Type) throws -> [T]? {
            guard try presence(of: name) == .present else { return nil }
            let lossy = ManifestSectionSpec.byName[name]?.policy == .lossy
            var out: [T] = []
            try forEachPayload(of: name) { _, bytes in
                if lossy { if let v = try? decoder.decode(T.self, from: bytes) { out.append(v) } } else { out.append(try decoder.decode(T.self, from: bytes)) }
            }
            return out
        }
        guard let exportedAt = try value("exportedAt", Date.self), let settings = try value("settings", KudosBackupSettings.self),
              let works = try array("works", KudosBackupWork.self), let bookmarks = try array("bookmarks", KudosBackupBookmark.self),
              let fonts = try array("fonts", KudosBackupFont.self)
        else { throw ManifestStreamError.invalidDocument(.schema) }
        let omitted = try ["collections", "readingQueues", "annotations", "savedSearches"].filter { try presence(of: $0) != .present }
        return KudosBackupManifest(
            version: version, exportedAt: exportedAt, works: works, bookmarks: bookmarks, fonts: fonts,
            collections: try array("collections", KudosBackupCollection.self) ?? [],
            readingQueues: try array("readingQueues", KudosBackupReadingQueue.self) ?? [],
            readingQueueMemberships: try array("readingQueueMemberships", KudosBackupReadingQueueMembership.self) ?? [],
            annotations: try array("annotations", KudosBackupAnnotation.self) ?? [],
            savedSearches: try array("savedSearches", KudosBackupSavedSearch.self) ?? [],
            readingSessions: try array("readingSessions", KudosBackupReadingSession.self),
            readingFavorites: try array("readingFavorites", KudosBackupReadingFavorite.self),
            fandomReadWatermarks: try array("fandomReadWatermarks", KudosBackupFandomReadWatermark.self),
            followedTags: try array("followedTags", KudosBackupFollowedTag.self),
            tagAliases: try array("tagAliases", KudosBackupTagAlias.self),
            settings: settings, pronunciations: try value("pronunciations", KudosBackupPronunciations.self) ?? .empty,
            tombstones: try array("tombstones", KudosBackupTombstone.self) ?? [],
            writingRecovery: try array("writingRecovery", KudosBackupRecoveryCopy.self),
            documents: try array("documents", KudosBackupDocument.self), omittedKeys: Set(omitted)
        )
    }
}
