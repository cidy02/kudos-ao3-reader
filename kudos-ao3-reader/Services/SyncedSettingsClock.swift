import CryptoKit
import Foundation

/// When each synced setting last changed on this device (T-541).
///
/// Settings travel in a backup and in the Library Sync Folder as bare values. Until this
/// existed a restore assigned every one of them, so each sync-down put the folder's copy over
/// whatever had been changed here since: an older state replacing a newer one, on every sync
/// that followed another device's write. `UserDefaults` keeps no change dates, so this keeps
/// the last value it saw for each setting and stamps the setting when the value moves.
/// `FolderSyncObserver` checks as settings change, so a stamp is the moment of the change to
/// within a second; capture and restore check too, for anything that changed while no
/// observer ran.
///
/// A setting whose value is a map (comment drafts, Posting As) is tracked entry by entry, so
/// two devices changing different entries both keep their change.
nonisolated enum SyncedSettingsClock {
    /// When a value was set, and whether that date is real.
    struct Stamp: Equatable, Sendable {
        var date: Date
        /// True when the date is only when the copy carrying the value was exported: copies
        /// from an older build or Android carry no stamps of their own.
        var inferred: Bool
    }

    private static let stampsKey = "sync.settings.stamps"
    private static let inferredKey = "sync.settings.inferred"
    private static let baselineKey = "sync.settings.baseline"
    private static let unset = "\u{0}unset"
    /// Present in the baseline once this device has looked at its settings at least once.
    /// After that, a setting or an entry appearing for the first time is an edit made here.
    private static let watchingMarker = "\u{0}watching"

    /// The stamps this device sends: real edit times only. A value that arrived with an
    /// inferred date leaves here unstamped, so the next device infers again rather than
    /// mistaking an export time for an edit.
    static func stamps(in defaults: UserDefaults) -> [String: Date] {
        dates(defaults, stampsKey)
    }

    /// Every setting or entry this device has stamped, learned from a copy, or looked at:
    /// what a later removal has to be measured against.
    static func knownIDs(in defaults: UserDefaults) -> [String] {
        let baseline = (defaults.dictionary(forKey: baselineKey) as? [String: String]) ?? [:]
        return Array(Set(baseline.keys).union(dates(defaults, stampsKey).keys).union(dates(defaults, inferredKey).keys))
    }

    static func localStamps(in defaults: UserDefaults) -> [String: Stamp] {
        var all = dates(defaults, inferredKey).mapValues { Stamp(date: $0, inferred: true) }
        for (id, date) in dates(defaults, stampsKey) { all[id] = Stamp(date: date, inferred: false) }
        return all
    }

    /// One entry of a map-valued setting, as an identifier that cannot collide with a plain
    /// key (a key never starts with `[`) and that reads back whatever the entry's name holds.
    static func entryID(_ key: String, _ entry: String) -> String {
        guard let data = try? JSONEncoder().encode([key, entry]) else { return key }
        return String(decoding: data, as: UTF8.self)
    }

    static func entry(from id: String) -> (key: String, entry: String)? {
        guard id.hasPrefix("["),
              let parts = try? JSONDecoder().decode([String].self, from: Data(id.utf8)),
              parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    /// Stamps every setting (and every entry of a map setting) whose value differs from the
    /// one last seen, and returns all local stamps. On the very first look nothing is stamped:
    /// nobody is known to have changed anything. From then on a setting that was absent and
    /// now has a value is an edit like any other (Codex's third T-541 review: the reader's
    /// first choice for an untouched setting was never stamped, so it was never uploaded and
    /// an older stamped copy could replace it). Writes nothing when nothing moved, since this
    /// runs on every `UserDefaults` change and a write would announce another.
    @discardableResult
    static func noteLocalChanges(
        keys: [String], mapKeys: Set<String> = [], in defaults: UserDefaults, now: Date = Date()
    ) -> [String: Stamp] {
        var baseline = (defaults.dictionary(forKey: baselineKey) as? [String: String]) ?? [:]
        var stamps = (defaults.dictionary(forKey: stampsKey) as? [String: Double]) ?? [:]
        var inferred = (defaults.dictionary(forKey: inferredKey) as? [String: Double]) ?? [:]
        let watching = baseline[watchingMarker] != nil
        var baselineMoved = false
        var stamped = false

        func check(_ id: String, _ current: String) {
            guard baseline[id] != current else { return }
            let known = baseline[id] != nil
            // Absent before and absent now is no change, only a baseline worth keeping.
            if known || (watching && current != unset) {
                stamps[id] = now.timeIntervalSince1970
                inferred[id] = nil
                stamped = true
            }
            baseline[id] = current
            baselineMoved = true
        }

        for key in keys where !mapKeys.contains(key) {
            check(key, fingerprint(defaults.object(forKey: key)))
        }
        for key in mapKeys {
            let current = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
            let seen = baseline.keys.compactMap { entry(from: $0) }.filter { $0.key == key }.map(\.entry)
            for name in Set(current.keys).union(seen) {
                check(entryID(key, name), current[name].map { fingerprint($0) } ?? unset)
            }
        }
        if !watching {
            baseline[watchingMarker] = "1"
            baselineMoved = true
        }
        if baselineMoved { defaults.set(baseline, forKey: baselineKey) }
        if stamped {
            defaults.set(stamps, forKey: stampsKey)
            defaults.set(inferred, forKey: inferredKey)
        }
        return localStamps(in: defaults)
    }

    /// The same check, for the observer that runs as settings change: true when something
    /// was stamped, so the caller can schedule an upload.
    static func stampChanges(
        keys: [String], mapKeys: Set<String> = [], in defaults: UserDefaults, now: Date = Date()
    ) -> Bool {
        let before = dates(defaults, stampsKey)
        noteLocalChanges(keys: keys, mapKeys: mapKeys, in: defaults, now: now)
        return dates(defaults, stampsKey) != before
    }

    /// Whether a value that arrived from elsewhere may replace the one here.
    ///
    /// A restore the reader asked for takes the file's values, as it always did. A sync takes
    /// a value only when it is newer than this device's, with one asymmetry: a date inferred
    /// from an export never beats a real edit made here. An older build or Android can export
    /// an unchanged, stale value after this device changed it; letting that export time win
    /// would undo the change. The cost, until every writer stamps, is that a change made on
    /// such a device does not replace a setting this device changed itself.
    static func incomingWins(local: Stamp?, incoming: Stamp?, fromSync: Bool) -> Bool {
        guard fromSync else { return true }
        guard let incoming else { return local == nil }
        guard let local else { return true }
        if local.inferred != incoming.inferred { return local.inferred }
        return incoming.date > local.date
    }

    /// Records that a setting now holds a value that came from elsewhere, so the next check
    /// does not mistake it for a change made here.
    static func adopt(key: String, stamp: Stamp?, in defaults: UserDefaults) {
        adopt(id: key, fingerprint: fingerprint(defaults.object(forKey: key)), stamp: stamp, in: defaults)
    }

    static func adopt(key: String, entry: String, value: String?, stamp: Stamp?, in defaults: UserDefaults) {
        adopt(id: entryID(key, entry), fingerprint: value.map { fingerprint($0) } ?? unset, stamp: stamp, in: defaults)
    }

    private static func adopt(id: String, fingerprint: String, stamp: Stamp?, in defaults: UserDefaults) {
        var baseline = (defaults.dictionary(forKey: baselineKey) as? [String: String]) ?? [:]
        baseline[id] = fingerprint
        defaults.set(baseline, forKey: baselineKey)
        guard let stamp else { return }
        var stamps = (defaults.dictionary(forKey: stampsKey) as? [String: Double]) ?? [:]
        var inferred = (defaults.dictionary(forKey: inferredKey) as? [String: Double]) ?? [:]
        if stamp.inferred {
            inferred[id] = stamp.date.timeIntervalSince1970
            stamps[id] = nil
        } else {
            stamps[id] = stamp.date.timeIntervalSince1970
            inferred[id] = nil
        }
        defaults.set(stamps, forKey: stampsKey)
        defaults.set(inferred, forKey: inferredKey)
    }

    private static func dates(_ defaults: UserDefaults, _ key: String) -> [String: Date] {
        ((defaults.dictionary(forKey: key) as? [String: Double]) ?? [:])
            .mapValues { Date(timeIntervalSince1970: $0) }
    }

    /// Stable across launches and exact: `String(describing:)` prints only a `Data`'s length
    /// and does not promise an order for a dictionary.
    private static func fingerprint(_ value: Any?) -> String {
        switch value {
        case nil:
            return unset
        case let data as Data:
            return "d:" + digest(data)
        case let text as String:
            return "s:" + text
        case let number as NSNumber:
            return "n:" + number.stringValue
        default:
            if let value, JSONSerialization.isValidJSONObject(value),
               let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
                return "j:" + digest(data)
            }
            return "o:" + String(describing: value!)
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// One setting carried outside `KudosBackupSettings`' named fields (T-541). Only keys that
/// `KudosBackupSettings.extraKind(for:)` names are read or written, and only with the kind it
/// names, so an archive cannot set an arbitrary preference or a wrong type.
nonisolated enum KudosBackupSettingValue: Codable, Equatable, Sendable {
    enum Kind: Sendable { case bool, number, string, data, stringMap }

    case bool(Bool)
    case number(Double)
    case string(String)
    /// A setting stored as encoded bytes (watermarks, recent tags).
    case data(Data)
    /// A setting stored as a string-to-string dictionary (comment drafts, Posting As).
    case stringMap([String: String])

    var kind: Kind {
        switch self {
        case .bool: .bool
        case .number: .number
        case .string: .string
        case .data: .data
        case .stringMap: .stringMap
        }
    }

    var object: Any {
        switch self {
        case .bool(let value): value
        case .number(let value): value
        case .string(let value): value
        case .data(let value): value
        case .stringMap(let value): value
        }
    }

    /// The stored choice, or nil when nothing is stored: a device that never chose must not
    /// export its default as if it were a choice.
    static func stored(_ key: String, kind: Kind, in defaults: UserDefaults) -> Self? {
        guard defaults.object(forKey: key) != nil else { return nil }
        switch kind {
        case .bool: return .bool(defaults.bool(forKey: key))
        case .number: return .number(defaults.double(forKey: key))
        case .string: return defaults.string(forKey: key).map(Self.string)
        case .data: return defaults.data(forKey: key).map(Self.data)
        case .stringMap: return (defaults.dictionary(forKey: key) as? [String: String]).map(Self.stringMap)
        }
    }

    private enum Wrapped: String, CodingKey { case data, map }

    init(from decoder: Decoder) throws {
        if let wrapped = try? decoder.container(keyedBy: Wrapped.self) {
            if let value = try? wrapped.decode(Data.self, forKey: .data) {
                self = .data(value)
                return
            }
            if let value = try? wrapped.decode([String: String].self, forKey: .map) {
                self = .stringMap(value)
                return
            }
        }
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .number(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .data(let value):
            var container = encoder.container(keyedBy: Wrapped.self)
            try container.encode(value, forKey: .data)
        case .stringMap(let value):
            var container = encoder.container(keyedBy: Wrapped.self)
            try container.encode(value, forKey: .map)
        }
    }
}

/// Decodes a `[String: T]` entry by entry, keeping every entry that decodes and reporting
/// whether any did not (T-541). A malformed entry must not look like an absent map: absence
/// can mean a reset, malformed cannot.
/// An array decoded element by element (T-541, Codex's third review): one malformed entry is
/// skipped and counted instead of turning every writing draft or data file in the archive into
/// nothing.
nonisolated struct LossyArray<Element: Decodable>: Decodable {
    var values: [Element] = []
    var skipped = 0

    /// Decodes anything, so the container steps past an element `Element` refused.
    private struct Skip: Decodable {
        init(from decoder: Decoder) {}
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            if let value = try? container.decode(Element.self) {
                values.append(value)
            } else {
                // Step past the bad element; a container that cannot advance ends the read.
                guard (try? container.decode(Skip.self)) != nil else { break }
                skipped += 1
            }
        }
    }
}

nonisolated struct LossyMap<Value: Decodable>: Decodable {
    var values: [String: Value] = [:]
    var hadFailures = false

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        for key in container.allKeys {
            if let value = try? container.decode(Value.self, forKey: key) {
                values[key.stringValue] = value
            } else {
                hadFailures = true
            }
        }
    }
}
