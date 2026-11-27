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
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try WritingDocumentIO.readJSON(IdeaInboxFile.self, from: url).ideas
    }

    @discardableResult
    func add(_ text: String) throws -> CapturedIdea {
        let idea = CapturedIdea(id: UUID(), text: text, createdAt: now())
        try write([idea] + list())
        return idea
    }

    func remove(id: UUID) throws {
        let ideas = try list()
        guard ideas.contains(where: { $0.id == id }) else { return }
        try write(ideas.filter { $0.id != id })
    }

    private func write(_ ideas: [CapturedIdea]) throws {
        try WritingDocumentIO.writeJSON(IdeaInboxFile(ideas: ideas), to: url)
    }
}
