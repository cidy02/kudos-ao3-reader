import Foundation

/// When each synced setting last changed on this device (T-541).
///
/// Settings travel in a backup and in the Library Sync Folder as bare values. Until this
/// existed a restore assigned every one of them, so each sync-down put the folder's copy over
/// whatever had been changed here since: an older state replacing a newer one, on every sync
/// that followed another device's write. `UserDefaults` keeps no change dates, so this keeps
/// the last value it saw for each key and stamps the key when the value has moved. The stamp
/// is the moment the change was noticed (the next export or restore): at or after the change
/// itself, and always before the value leaves the device.
nonisolated enum SyncedSettingsClock {
    private static let stampsKey = "sync.settings.stamps"
    private static let baselineKey = "sync.settings.baseline"

    static func stamps(in defaults: UserDefaults) -> [String: Date] {
        ((defaults.dictionary(forKey: stampsKey) as? [String: Double]) ?? [:])
            .mapValues { Date(timeIntervalSince1970: $0) }
    }

    /// Stamps every key whose value differs from the one last seen, and returns all stamps.
    /// A key seen for the first time gets no stamp: nobody is known to have changed it.
    @discardableResult
    static func noteLocalChanges(
        keys: [String], in defaults: UserDefaults, now: Date = Date()
    ) -> [String: Date] {
        var baseline = (defaults.dictionary(forKey: baselineKey) as? [String: String]) ?? [:]
        var stamps = (defaults.dictionary(forKey: stampsKey) as? [String: Double]) ?? [:]
        var baselineMoved = false
        var stamped = false
        for key in keys {
            let current = fingerprint(of: key, in: defaults)
            guard baseline[key] != current else { continue }
            if baseline[key] != nil {
                stamps[key] = now.timeIntervalSince1970
                stamped = true
            }
            baseline[key] = current
            baselineMoved = true
        }
        // Nothing written when nothing moved: this runs on every `UserDefaults` change, and
        // writing here would announce another change.
        if baselineMoved { defaults.set(baseline, forKey: baselineKey) }
        if stamped { defaults.set(stamps, forKey: stampsKey) }
        return stamps.mapValues { Date(timeIntervalSince1970: $0) }
    }

    /// The same check, for the observer that runs as settings change: true when a setting
    /// was stamped, so the caller can schedule an upload.
    static func stampChanges(keys: [String], in defaults: UserDefaults, now: Date = Date()) -> Bool {
        let before = defaults.dictionary(forKey: stampsKey) as? [String: Double] ?? [:]
        noteLocalChanges(keys: keys, in: defaults, now: now)
        return (defaults.dictionary(forKey: stampsKey) as? [String: Double] ?? [:]) != before
    }

    /// Whether a value that arrived from elsewhere may replace the one here.
    ///
    /// A restore the reader asked for takes the file's settings, as it always did. A sync
    /// takes a setting only when it is newer than the local change. The caller passes the
    /// value's own stamp, or for a copy written by an older build or Android, which has none,
    /// the time that copy was exported: so the newest of several stampless copies wins, and an
    /// old conflict copy cannot replace what a newer manifest just set.
    static func incomingWins(localStamp: Date?, incomingStamp: Date?, fromSync: Bool) -> Bool {
        guard fromSync else { return true }
        guard let incomingStamp else { return localStamp == nil }
        guard let localStamp else { return true }
        return incomingStamp > localStamp
    }

    /// Records that `key` now holds a value that came from elsewhere, so the next
    /// `noteLocalChanges` does not mistake it for a change made here.
    static func adopt(key: String, stamp: Date?, in defaults: UserDefaults) {
        var baseline = (defaults.dictionary(forKey: baselineKey) as? [String: String]) ?? [:]
        var stamps = (defaults.dictionary(forKey: stampsKey) as? [String: Double]) ?? [:]
        baseline[key] = fingerprint(of: key, in: defaults)
        if let stamp { stamps[key] = stamp.timeIntervalSince1970 }
        defaults.set(baseline, forKey: baselineKey)
        defaults.set(stamps, forKey: stampsKey)
    }

    private static func fingerprint(of key: String, in defaults: UserDefaults) -> String {
        defaults.object(forKey: key).map { String(describing: $0) } ?? "\u{0}unset"
    }
}

/// One setting carried outside `KudosBackupSettings`' named fields (T-541): a switch, a
/// number or a short text. Only keys on `KudosBackupSettings.extraKeys` are read or written,
/// so an archive cannot set an arbitrary preference.
nonisolated enum KudosBackupSettingValue: Codable, Equatable, Sendable {
    enum Kind: Sendable { case bool, number, string }

    case bool(Bool)
    case number(Double)
    case string(String)

    var kind: Kind {
        switch self {
        case .bool: .bool
        case .number: .number
        case .string: .string
        }
    }

    var object: Any {
        switch self {
        case .bool(let value): value
        case .number(let value): value
        case .string(let value): value
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
        }
    }

    init(from decoder: Decoder) throws {
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
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}
