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
            let defaults = decoder.userInfo[KudosBackupContents.stagingDefaultsKey] as? ManifestDefaultMarker
            defaults?.used = false
            defaults?.fields.removeAll(keepingCapacity: true)
            guard let value = try? decoder.decode(T.self, from: data) else { return nil }
            guard generatesDefaults, defaults?.used == true else { return (keys(value), nil) }
            // Keep the source's compact shape while materialising defaults. The input has passed the tokenizer and
            // typed decoder; the splice also removes accepted trailing commas, including inside ignored values.
            if let fields = defaults?.fields, let compact = Self.spliceDefaults(fields, into: data) {
                return (keys(value), compact)
            }
            return (keys(value), try? encoder.encode(value))
        }
    }

    /// Replaces present `null` defaults and appends absent ones without expanding a minimal record to every Codable field.
    /// Key strings are decoded only at the object's first level, so escapes in values and nested keys cannot hide a field.
    private static func spliceDefaults(_ fields: [(String, Data)], into data: Data) -> Data? {
        guard !fields.isEmpty, data.first == UInt8(ascii: "{"), data.last == UInt8(ascii: "}") else { return nil }
        let generated = Dictionary(fields, uniquingKeysWith: { first, _ in first })
        var missing = Set(generated.keys)
        var out = Data(capacity: data.count + fields.reduce(0) { $0 + $1.0.utf8.count + $1.1.count + 4 })
        var start = 0
        var depth = 0
        var members = 0
        var expectsKey = false
        var rootKey: String?
        var i = 0
        while i < data.count {
            let byte = data[i]
            if byte == UInt8(ascii: "\"") {
                let opening = i
                i += 1
                while i < data.count {
                    if data[i] == UInt8(ascii: "\\") { i += 2; continue }
                    if data[i] == UInt8(ascii: "\"") { break }
                    i += 1
                }
                guard i < data.count else { return nil }
                if depth == 1 && expectsKey {
                    let inner = data[(opening + 1) ..< i]
                    if inner.contains(UInt8(ascii: "\\")) {
                        rootKey = try? JSONDecoder().decode(String.self, from: Data(data[opening ... i]))
                    } else {
                        rootKey = String(decoding: inner, as: UTF8.self)
                    }
                    expectsKey = false
                }
            } else if byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[") {
                depth += 1
                if depth == 1 { expectsKey = true }
            } else if byte == UInt8(ascii: "}") || byte == UInt8(ascii: "]") {
                depth -= 1
            } else if byte == UInt8(ascii: ":") && depth == 1 {
                members += 1
                if let rootKey, let replacement = generated[rootKey] {
                    var valueStart = i + 1
                    while valueStart < data.count && isJSONWhitespace(data[valueStart]) { valueStart += 1 }
                    guard valueStart + 4 <= data.count, data[valueStart ..< valueStart + 4].elementsEqual("null".utf8) else {
                        return nil // a generated field can be present only as null
                    }
                    out.append(data[start ..< valueStart])
                    out.append(replacement)
                    start = valueStart + 4
                    i = start - 1
                    missing.remove(rootKey)
                }
            } else if byte == UInt8(ascii: ",") {
                var next = i + 1
                while next < data.count && isJSONWhitespace(data[next]) { next += 1 }
                let closesContainer = next < data.count
                    && (data[next] == UInt8(ascii: "}") || data[next] == UInt8(ascii: "]"))
                if closesContainer {
                    out.append(data[start ..< i])
                    start = i + 1
                } else if depth == 1 {
                    expectsKey = true
                    rootKey = nil
                }
            }
            i += 1
        }
        out.append(data[start ..< data.count - 1]) // the final brace is inserted after missing fields
        for field in fields where missing.contains(field.0) {
            if members > 0 { out.append(UInt8(ascii: ",")) }
            out.append(contentsOf: Data("\"\(field.0)\":".utf8))
            out.append(field.1)
            members += 1
        }
        out.append(UInt8(ascii: "}"))
        return out
    }

    private static func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
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
