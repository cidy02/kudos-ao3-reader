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

/// Reading a staged run back. Consumers (P4) stream `forEachPayload`; `manifest()` is the whole-document form used to
/// prove staging lost nothing, and is not memory-bounded.
extension ManifestStagedRun {
    func presence(of name: String) throws -> ManifestPresence {
        var shape = ManifestPresence.missing
        try db.query("SELECT presence FROM member WHERE name = ?", [.text(name)]) { shape = ManifestPresence(rawValue: $0.int(0)) ?? .missing }
        return shape
    }

    /// Member names in source order (known and unknown), first occurrence of each.
    func memberNames() throws -> [String] {
        var names: [String] = []
        try db.query("SELECT name FROM member WHERE ord IS NOT NULL ORDER BY ord") { names.append($0.text(0)) }
        return names
    }

    /// Rows of one section in source order, with their status and natural keys.
    func records(of section: String) throws -> [(seq: Int, status: ManifestRecordStatus, length: Int, keys: ManifestRecordKeys)] {
        guard let spec = ManifestSectionSpec.byName[section] else { return [] }
        var out: [(Int, ManifestRecordStatus, Int, ManifestRecordKeys)] = []
        let columns = ManifestRecordKeys.columns.joined(separator: ", ")
        try db.query("SELECT seq, status, length, \(columns) FROM \(spec.table) ORDER BY seq") { r in
            var keys = ManifestRecordKeys()
            keys.id = r.isNull(3) ? nil : r.text(3)
            keys.work = r.isNull(4) ? nil : r.text(4)
            keys.ref = r.isNull(5) ? nil : r.text(5)
            keys.ao3 = r.isNull(6) ? nil : r.int(6)
            keys.url = r.isNull(7) ? nil : r.text(7)
            keys.name = r.isNull(8) ? nil : r.text(8)
            keys.text = r.isNull(9) ? nil : r.text(9)
            keys.stamp = r.isNull(10) ? nil : r.double(10)
            out.append((r.int(0), ManifestRecordStatus(rawValue: r.int(1)) ?? .decoded, r.int(2), keys))
        }
        return out
    }

    /// The payload of every stored record of `owner` (a section or single-value member), in source order. A record
    /// is handed over whole, so use it for records within the typed budget; `forEachChunk` is the bounded form.
    func forEachPayload(of owner: String, _ body: (_ seq: Int, _ bytes: Data) throws -> Void) throws {
        var current = -1
        var buffer = Data()
        try db.query("SELECT seq, bytes FROM payload WHERE owner = ? ORDER BY seq, chunk", [.text(owner)]) { r in
            if r.int(0) != current {
                if current >= 0 { try body(current, buffer) }
                current = r.int(0)
                buffer = Data()
            }
            buffer.append(r.data(1))
        }
        if current >= 0 { try body(current, buffer) }
    }

    /// Bounded form: each stored chunk of one record, in order.
    func forEachChunk(of owner: String, seq: Int, _ body: (Data) throws -> Void) throws {
        try db.query("SELECT bytes FROM payload WHERE owner = ? AND seq = ? ORDER BY chunk", [.text(owner), .int(Int64(seq))]) { try body($0.data(0)) }
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
