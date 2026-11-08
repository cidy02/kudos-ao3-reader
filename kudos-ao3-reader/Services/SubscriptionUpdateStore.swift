import Foundation

struct MailCursor: Codable, Equatable, Sendable {
    let uidValidity: UInt32
    let lastUID: UInt32
}

struct MailImportCounts: Codable, Equatable, Sendable {
    var refused: UInt64 = 0
    var otherAO3Mail: UInt64 = 0
    var tooLarge: UInt64 = 0
    var swiftRefused: UInt64 = 0

    var unverified: UInt64 {
        [refused, otherAO3Mail, tooLarge, swiftRefused].reduce(0) { total, value in
            let (sum, overflow) = total.addingReportingOverflow(value)
            return overflow ? .max : sum
        }
    }
}

/// A New to you choice. `Next` is not one of these: it only hides the card
/// until the next launch.
struct SubscriptionDecision: Codable, Equatable, Sendable {
    enum Action: String, Codable, Equatable, Sendable {
        case saved
        case notForMe
    }

    var workID: UInt64
    var action: Action
}

struct SubscriptionUpdateState: Codable, Equatable, Sendable {
    static let limit = 500

    var updates: [SubscriptionUpdate] = []
    var counts = MailImportCounts()
    var since: Date?
    var lastRefreshAt: Date?
    /// Newest last. Capped with the updates. A missing key is an older file.
    var decisions: [SubscriptionDecision] = []

    init(
        updates: [SubscriptionUpdate] = [],
        counts: MailImportCounts = .init(),
        since: Date? = nil,
        lastRefreshAt: Date? = nil,
        decisions: [SubscriptionDecision] = []
    ) {
        self.updates = updates
        self.counts = counts
        self.since = since
        self.lastRefreshAt = lastRefreshAt
        self.decisions = decisions
    }

    private enum CodingKeys: String, CodingKey {
        case updates, counts, since, lastRefreshAt, decisions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updates = try container.decode([SubscriptionUpdate].self, forKey: .updates)
        counts = try container.decode(MailImportCounts.self, forKey: .counts)
        since = try container.decodeIfPresent(Date.self, forKey: .since)
        lastRefreshAt = try container.decodeIfPresent(Date.self, forKey: .lastRefreshAt)
        decisions = try container.decodeIfPresent([SubscriptionDecision].self, forKey: .decisions) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(updates, forKey: .updates)
        try container.encode(counts, forKey: .counts)
        try container.encodeIfPresent(since, forKey: .since)
        try container.encodeIfPresent(lastRefreshAt, forKey: .lastRefreshAt)
        try container.encode(decisions, forKey: .decisions)
    }

    func capped() -> Self {
        var seen = Set<UInt32>()
        var copy = self
        copy.updates = updates
            .sorted { left, right in
                left.at == right.at ? left.uid > right.uid : left.at > right.at
            }
            .filter { seen.insert($0.uid).inserted }
            .prefix(Self.limit)
            .map { $0 }
        // shortcut: the oldest decisions fall off at `limit`, same as updates;
        // raise it if a busy account dismisses more works than that and sees them return.
        var seenWorks = Set<UInt64>()
        var kept: [SubscriptionDecision] = []
        for decision in decisions.reversed() where seenWorks.insert(decision.workID).inserted {
            kept.append(decision)
            if kept.count == Self.limit { break }
        }
        copy.decisions = Array(kept.reversed())
        return copy
    }
}

protocol SubscriptionUpdateStoring {
    func loadState() throws -> SubscriptionUpdateState
    func saveState(_ state: SubscriptionUpdateState) throws
    func loadCursor() throws -> MailCursor?
    func saveCursor(_ cursor: MailCursor?) throws
    func delete() throws
}

/// Derived mail state in Application Support, excluded from device backups and
/// deliberately outside SwiftData, folder sync, and `.kudosbackup` exports.
struct FileSubscriptionUpdateStore: SubscriptionUpdateStoring {
    private let directoryURL: URL
    private var stateURL: URL { directoryURL.appendingPathComponent("updates.json") }
    private var cursorURL: URL { directoryURL.appendingPathComponent("cursor.json") }

    nonisolated init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            self.directoryURL = support.appendingPathComponent("KudosMail", isDirectory: true)
        }
    }

    func loadState() throws -> SubscriptionUpdateState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return .init() }
        return try JSONDecoder().decode(
            SubscriptionUpdateState.self,
            from: Data(contentsOf: stateURL)
        ).capped()
    }

    func saveState(_ state: SubscriptionUpdateState) throws {
        try prepareDirectory()
        try write(JSONEncoder().encode(state.capped()), to: stateURL)
    }

    func loadCursor() throws -> MailCursor? {
        guard FileManager.default.fileExists(atPath: cursorURL.path) else { return nil }
        return try JSONDecoder().decode(MailCursor.self, from: Data(contentsOf: cursorURL))
    }

    func saveCursor(_ cursor: MailCursor?) throws {
        guard let cursor else {
            if FileManager.default.fileExists(atPath: cursorURL.path) {
                try FileManager.default.removeItem(at: cursorURL)
            }
            return
        }
        try prepareDirectory()
        try write(JSONEncoder().encode(cursor), to: cursorURL)
    }

    func delete() throws {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        try FileManager.default.removeItem(at: directoryURL)
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = directoryURL
        try directory.setResourceValues(values)
    }

    private func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
