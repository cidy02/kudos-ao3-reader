import Foundation

/// Parsed contents of AO3's `/tags/:id/feed.atom` Atom feed.
///
/// Built to match `otwarchive`'s `app/views/tags/feed.atom.builder` and Rails'
/// `atom_feed_helper.rb`: up to 25 revealed works ordered newest `created_at`
/// first, with creator names/URIs and blurb metadata serialized in each
/// `<summary type="html">`.
nonisolated struct AO3TagFeed: Equatable, Sendable {
    let feedID: String
    let title: String
    let updatedAt: Date?
    let entries: [AO3TagFeedEntry]
}

nonisolated struct AO3TagFeedEntry: Equatable, Hashable, Sendable {
    let id: String
    let workID: Int
    let title: String
    let authors: [String]
    let authorIdentities: [AO3AuthorIdentity]
    let publishedAt: Date
    let updatedAt: Date?
    let url: URL?
    let summary: String
    let words: Int
    let chapters: String
    let isComplete: Bool
    let language: String
    let rating: String?
    let warnings: [String]
    let categories: [String]
    let fandoms: [String]
    let characters: [String]
    let relationships: [String]
    let freeforms: [String]

    var isExplicit: Bool {
        rating?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Explicit") == .orderedSame
    }

    /// Applies the local switches from the Follow Tag sheet without touching AO3.
    func passesFilters(completeOnly: Bool, hideExplicit: Bool) -> Bool {
        if completeOnly, !isComplete { return false }
        if hideExplicit, isExplicit { return false }
        return true
    }

    /// Parses AO3's `posted/total` chapter count string (`"12/12"` -> complete,
    /// `"3/?"` or `"3/10"` -> incomplete).
    static func isCompleteChapters(_ chapters: String) -> Bool {
        let parts = chapters.split(separator: "/").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count == 2,
              let posted = Int(parts[0]),
              let total = Int(parts[1]),
              total > 0,
              posted >= total
        else { return false }
        return true
    }
}
