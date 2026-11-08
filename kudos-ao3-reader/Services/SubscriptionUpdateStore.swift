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

struct SubscriptionUpdateState: Codable, Equatable, Sendable {
    static let limit = 500

    var updates: [SubscriptionUpdate] = []
    var counts = MailImportCounts()
    var since: Date?
    var lastRefreshAt: Date?

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
