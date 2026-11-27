import Foundation

/// A thought saved to the Ideas inbox, not yet attached to a work.
nonisolated struct CapturedIdea: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var text: String
    var createdAt: Date
}

private nonisolated struct IdeaInboxFile: Codable {
    var ideas: [CapturedIdea]
}

/// The Ideas inbox: one small JSON file in Application Support (`Ideas/ideas.json`), newest first.
/// Device-only, never sent anywhere, and not part of the library backup. A file that exists but
/// can't be read throws instead of being overwritten, so a bad write never costs the writer ideas.
actor IdeaInbox {
    nonisolated static let shared = IdeaInbox()
    nonisolated private static let ioLock = NSLock()

    nonisolated static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ideas", isDirectory: true)
            .appendingPathComponent("ideas.json")
    }

    private let url: URL
    private let now: @Sendable () -> Date

    init(url: URL = IdeaInbox.defaultURL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.url = url
        self.now = now
    }

    func list() throws -> [CapturedIdea] {
        try withLock { try readUnlocked() }
    }

    @discardableResult
    func add(_ text: String) throws -> CapturedIdea {
        try withLock {
            let idea = CapturedIdea(id: UUID(), text: text, createdAt: now())
            try writeUnlocked([idea] + readUnlocked())
            return idea
        }
    }

    func remove(id: UUID) throws {
        try withLock {
            let ideas = try readUnlocked()
            guard ideas.contains(where: { $0.id == id }) else { return }
            try writeUnlocked(ideas.filter { $0.id != id })
        }
    }

    private func readUnlocked() throws -> [CapturedIdea] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try WritingDocumentIO.readJSON(IdeaInboxFile.self, from: url).ideas
    }

    private func writeUnlocked(_ ideas: [CapturedIdea]) throws {
        try WritingDocumentIO.writeJSON(IdeaInboxFile(ideas: ideas), to: url)
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        Self.ioLock.lock()
        defer { Self.ioLock.unlock() }
        return try body()
    }
}
