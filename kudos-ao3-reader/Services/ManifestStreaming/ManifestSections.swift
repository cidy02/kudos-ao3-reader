import Foundation

/// The natural keys the staging tables index (plan, Architecture 2). Which of them a section fills is in its spec.
nonisolated struct ManifestRecordKeys {
    var id: String?
    var work: String?
    var ref: String?
    var ao3: Int?
    var url: String?
    /// Case-folded where the platforms match case-insensitively (font name, fandom name, tag name).
    var name: String?
    var text: String?
    /// A second text key where the identity is a pair (favorites: kind + target), so no separator is needed.
    var text2: String?
    var stamp: Double?

    static let columns = ["k_id", "k_work", "k_ref", "k_ao3", "k_url", "k_name", "k_text", "k_text2", "k_stamp"]

    var binds: [ManifestStagingDB.Bind] {
        func s(_ v: String?) -> ManifestStagingDB.Bind { v.map { .text($0) } ?? .null }
        return [s(id), s(work), s(ref), ao3.map { .int(Int64($0)) } ?? .null, s(url), s(name), s(text), s(text2), stamp.map { .double($0) } ?? .null]
    }

    init(id: UUID? = nil, work: UUID? = nil, ref: UUID? = nil, ao3: Int? = nil, url: String? = nil, name: String? = nil,
         text: String? = nil, text2: String? = nil, stamp: Date? = nil) {
        self.id = id?.uuidString.lowercased()
        self.work = work?.uuidString.lowercased()
        self.ref = ref?.uuidString.lowercased()
        self.ao3 = ao3
        self.url = url
        self.name = name?.lowercased()
        self.text = text
        self.text2 = text2
        self.stamp = stamp?.timeIntervalSince1970
    }
}

/// One top-level array of the manifest and how an element is judged.
nonisolated struct ManifestSectionSpec {
    enum Policy {
        /// `container.decode`: missing, `null` and a wrong kind all fail the document; every element must decode.
        case required
        /// `decodeIfPresent`: missing and `null` are absent (nil / `[]`); a wrong kind or a bad element fails the document.
        case optional
        /// `LossyArray` under `try?`: a wrong kind is absent, a bad element is skipped, the document is unaffected.
        case lossy
    }

    let name: String
    let policy: Policy
    /// Names of the key columns this section fills (each is indexed).
    let indexed: [String]
    /// Decodes one element with the oracle decoder; nil when it does not decode. `canonical` is the record re-encoded from the
    /// decoded value, for types whose decoder generates defaults (a missing id or date): the default is materialised once, here,
    /// and every later reader decodes the stored bytes, so the index and the apply see the same value.
    let decode: (JSONDecoder, JSONEncoder, Data) -> (keys: ManifestRecordKeys, canonical: Data?)?

    var table: String { "rec_" + name }

    private static func make<T: Codable>(
        _ name: String, _ policy: Policy, _ indexed: [String], _: T.Type, generatesDefaults: Bool = false,
        _ keys: @escaping (T) -> ManifestRecordKeys
    ) -> ManifestSectionSpec {
        ManifestSectionSpec(name: name, policy: policy, indexed: indexed) { decoder, encoder, data in
            guard let value = try? decoder.decode(T.self, from: data) else { return nil }
            return (keys(value), generatesDefaults ? try? encoder.encode(value) : nil)
        }
    }

    // Order is the order of `KudosBackupManifest.init(from:)`.
    static let all: [ManifestSectionSpec] = [
        make("works", .required, ["k_id", "k_ao3", "k_url"], KudosBackupWork.self, generatesDefaults: true) {
            .init(id: $0.id, ao3: $0.ao3WorkID, url: $0.sourceURL)
        },
        make("bookmarks", .required, ["k_id", "k_url"], KudosBackupBookmark.self, generatesDefaults: true) { .init(id: $0.id, url: $0.urlString) },
        make("fonts", .required, ["k_name"], KudosBackupFont.self) { .init(name: $0.name, text: $0.fileName) },
        make("collections", .optional, ["k_id", "k_name"], KudosBackupCollection.self) { .init(id: $0.id, name: $0.name) },
        make("readingQueues", .optional, ["k_id", "k_name"], KudosBackupReadingQueue.self) { .init(id: $0.id, name: $0.name) },
        make("readingQueueMemberships", .optional, ["k_id", "k_work", "k_ref"], KudosBackupReadingQueueMembership.self) {
            .init(id: $0.id, work: $0.workID, ref: $0.queueID)
        },
        make("annotations", .optional, ["k_id", "k_work", "k_text"], KudosBackupAnnotation.self) {
            .init(id: $0.id, work: $0.workID, text: $0.locatorString)
        },
        make("savedSearches", .optional, ["k_id", "k_name"], KudosBackupSavedSearch.self) { .init(id: $0.id, name: $0.name) },
        make("readingSessions", .optional, ["k_id", "k_work", "k_ao3"], KudosBackupReadingSession.self, generatesDefaults: true) {
            .init(id: $0.id, work: $0.workID, ao3: $0.ao3WorkID, url: $0.sourceURL)
        },
        make("readingFavorites", .optional, ["k_id", "k_text", "k_text2"], KudosBackupReadingFavorite.self, generatesDefaults: true) {
            .init(id: $0.id, text: $0.kindRaw, text2: $0.targetKey)
        },
        make("fandomReadWatermarks", .optional, ["k_id", "k_name"], KudosBackupFandomReadWatermark.self, generatesDefaults: true) {
            .init(id: $0.id, name: $0.fandomName)
        },
        make("followedTags", .optional, ["k_id", "k_ao3", "k_name"], KudosBackupFollowedTag.self, generatesDefaults: true) {
            .init(id: $0.id, ao3: $0.ao3TagID, name: $0.name)
        },
        make("tagAliases", .optional, ["k_id", "k_name"], KudosBackupTagAlias.self, generatesDefaults: true) {
            .init(id: $0.id, name: $0.name, text: $0.canonicalName)
        },
        make("tombstones", .optional, ["k_id", "k_work", "k_ao3", "k_url"], KudosBackupTombstone.self) {
            .init(id: $0.id, work: $0.recordID, ao3: $0.ao3WorkID, url: $0.sourceURL, text: $0.recordTypeRaw, stamp: $0.lastModifiedAt)
        },
        make("writingRecovery", .lossy, ["k_name"], KudosBackupRecoveryCopy.self) { .init(name: $0.fileName) },
        make("documents", .lossy, ["k_name"], KudosBackupDocument.self) { .init(name: $0.name, stamp: $0.modifiedAt) },
    ]

    static let byName = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })
}

/// A single-value top-level member: `version`, `exportedAt`, `settings`, `pronunciations`.
nonisolated struct ManifestValueSpec {
    let name: String
    let isRequired: Bool
    let decodes: (JSONDecoder, Data) -> Bool

    private static func make<T: Decodable>(_ name: String, required: Bool, _: T.Type) -> ManifestValueSpec {
        ManifestValueSpec(name: name, isRequired: required) { decoder, data in (try? decoder.decode(T.self, from: data)) != nil }
    }

    static let all: [ManifestValueSpec] = [
        make("version", required: true, Int.self),
        make("exportedAt", required: true, Date.self),
        make("settings", required: true, KudosBackupSettings.self),
        make("pronunciations", required: false, KudosBackupPronunciations.self),
    ]

    static let byName = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })
}

/// Whether a known member was in the document and of what shape (the plan's missing / `null` / present).
nonisolated enum ManifestPresence: Int {
    case missing = 0, null = 1, present = 2, wrongKind = 3
}

/// Record status in a section table.
nonisolated enum ManifestRecordStatus: Int {
    /// Decoded with the production type while staging.
    case decoded = 0
    /// A `LossyArray` element that did not decode: kept as a row (source order, count), no payload.
    case undecodable = 1
    /// Larger than the typed-decode budget: syntax-validated and stored in chunks; decoded by whoever reads it.
    case deferred = 2
}
