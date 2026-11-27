import Foundation

/// Where a new idea goes: the Ideas inbox, or one work's story notes.
nonisolated enum NewIdeaDestination: Hashable, Sendable {
    case inbox
    case work(UUID)

    /// `@AppStorage` key for the last destination the writer chose.
    static let lastChosenKey = "newIdeaLastDestination"

    var storageValue: String {
        switch self {
        case .inbox: "inbox"
        case let .work(id): id.uuidString
        }
    }

    /// The remembered destination, or the inbox when that work no longer exists.
    static func restore(_ stored: String, among works: [WritingWork]) -> NewIdeaDestination {
        guard let id = UUID(uuidString: stored), works.contains(where: { $0.id == id }) else { return .inbox }
        return .work(id)
    }
}

nonisolated enum NewIdeaNote {
    static let nameLimit = 60

    /// The first line of the idea, cut to 60 characters: the name of the story note it becomes.
    static func name(for text: String) -> String {
        let firstLine = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline).first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        return String(firstLine.prefix(nameLimit))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated enum NewIdeaError: Error, Equatable {
    case empty
}

/// Saves an idea. Nothing here touches AO3.
nonisolated struct NewIdeaSaver: Sendable {
    let store: WritingDocumentStore
    let inbox: IdeaInbox

    func save(_ text: String, to destination: NewIdeaDestination) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NewIdeaError.empty }
        switch destination {
        case .inbox:
            try await inbox.add(trimmed)
        case let .work(workID):
            try await addNote(trimmed, to: workID)
        }
    }

    /// Moves an inbox idea into a work's story notes. The idea leaves the inbox only after the
    /// note is written, so a failure keeps it.
    func move(_ idea: CapturedIdea, toWork workID: UUID) async throws {
        try await addNote(idea.text, to: workID)
        try await inbox.remove(id: idea.id)
    }

    private func addNote(_ text: String, to workID: UUID) async throws {
        _ = try await store.addStoryNote(
            workID: workID,
            kind: .other,
            name: NewIdeaNote.name(for: text),
            detail: text,
            pinned: false
        )
    }
}
