import Foundation

/// Which layout a surface draws. The reader does not pick a card mode: Home,
/// Library and Writing are fixed, search-family lists are detailed rows, the
/// work lists are ledger rows, and Updates, Reading History and Inbox keep the
/// rows they already had.
///
/// `allWorks` is the policy for the All Works header T-472 owns. This task does
/// not build that screen.
nonisolated enum WorkSurface: String, CaseIterable, Sendable {
    case home
    case library
    case writing
    case searchResults
    case browse
    case fandomWorks
    case tagWorks
    case authorLists
    case series
    case allWorks
    case shelf
    case queue
    case collection
    case markedForLater
    case bookmarks
    case ao3History
    case yourWorks
    case updates
    case readingHistory
    case inbox

    enum Kind: String, Equatable, Sendable {
        /// The dashboard draws what it draws. No layout control.
        case fixed
        /// Symbols, title, byline, stats, summary and tags. Show Summaries in •••.
        case detailed
        /// Symbols, fandom, title, byline, the full stat line and progress.
        /// List / Grid in •••.
        case ledger
        /// The surface's own rows. No card-mode switch.
        case ownRows
    }

    var kind: Kind {
        switch self {
        case .home, .library, .writing:
            .fixed
        case .searchResults, .browse, .fandomWorks, .tagWorks, .authorLists, .series:
            .detailed
        case .allWorks, .shelf, .queue, .collection, .markedForLater, .bookmarks, .ao3History, .yourWorks:
            .ledger
        case .updates, .readingHistory, .inbox:
            .ownRows
        }
    }

    /// Remembered per detailed surface. Nil everywhere else: a ledger list has
    /// no summary on the row, and a fixed page has no switch. Browse's work
    /// list is the fandom works screen, so the two share one key.
    var showSummariesKey: String? {
        switch self {
        case .searchResults: WorkListKeys.searchShowSummaries
        case .browse, .fandomWorks: WorkListKeys.fandomWorksShowSummaries
        case .tagWorks: WorkListKeys.tagWorksShowSummaries
        case .authorLists: WorkListKeys.authorListsShowSummaries
        case .series: WorkListKeys.seriesShowSummaries
        default: nil
        }
    }
}

/// List or Grid for a ledger list. String raw values so `@AppStorage` can store
/// them. Grid is the old Compact cover layout; List is the ledger row.
nonisolated enum WorkListArrangement: String, CaseIterable, Sendable {
    case list
    case grid

    var title: String {
        switch self {
        case .list: "List"
        case .grid: "Grid"
        }
    }

    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.2x2"
        }
    }
}

/// UserDefaults keys for the layout migration. Legacy display-mode keys stay
/// where they are; the new arrangement is written beside them, once.
enum WorkListKeys {
    static let accountDisplayMode = "account.displayMode"
    static let authorProfileDisplayMode = "authorProfile.displayMode"
    static let collectionDisplayMode = "collection.displayMode"
    /// Ignored. Left in UserDefaults. Never passed through the display-mode mapper.
    static let libraryDashboardLayout = "library.dashboard.layout"

    static let searchShowSummaries = "search.showSummaries"
    static let fandomWorksShowSummaries = "browse.fandomWorks.showSummaries"
    static let tagWorksShowSummaries = "browse.tagWorks.showSummaries"
    static let authorListsShowSummaries = "author.lists.showSummaries"
    static let seriesShowSummaries = "series.showSummaries"

    static let markedForLaterArrangement = "account.markedForLater.arrangement"
    static let bookmarksArrangement = "account.bookmarks.arrangement"
    static let ao3HistoryArrangement = "account.ao3History.arrangement"
    static let yourWorksArrangement = "account.yourWorks.arrangement"
    static let allWorksArrangement = "library.allWorks.arrangement"
    static let importedArrangement = "library.imported.arrangement"

    static func libraryShelfArrangement(_ kind: String) -> String {
        "library.\(kind).arrangement"
    }

    static func libraryShelfDisplayMode(_ kind: String) -> String {
        "library.\(kind).displayMode"
    }

    static func homeShelfArrangement(_ kind: String) -> String {
        "home.\(kind).arrangement"
    }

    static func homeShelfDisplayMode(_ kind: String) -> String {
        "home.\(kind).displayMode"
    }

    static func queueArrangement(_ id: UUID) -> String {
        "library.readingQueueBrowser.arrangement.\(id.uuidString)"
    }

    static func queueDisplayMode(_ id: UUID) -> String {
        "library.readingQueueBrowser.displayMode.\(id.uuidString)"
    }

    static func collectionArrangement(_ id: UUID) -> String {
        "collection.\(id.uuidString).arrangement"
    }

    static func ao3CollectionArrangement(_ name: String) -> String {
        "account.ao3Collection.\(name).arrangement"
    }
}

/// One-time, lossless move from Detailed / Ledger / Compact onto List / Grid.
/// Never deletes a stored key. A dashboard Shelves/Ledger value is not a
/// display mode and does not map.
enum WorkListLayoutMigration {
    /// Compact becomes Grid, so a reader who had covers keeps covers. Detailed
    /// or Ledger becomes List. "shelves" is the dashboard's word, not a display
    /// mode, and returns nil. "ledger" maps only when it is a display-mode
    /// value; do not pass `library.dashboard.layout` through here.
    static func arrangement(fromStoredDisplayMode raw: String?) -> WorkListArrangement? {
        switch raw {
        case "compact": .grid
        case "detailed", "ledger": .list
        default: nil
        }
    }

    /// The arrangement to draw. A value already stored under `arrangementKey`
    /// wins, including a later change away from the migrated one. Otherwise a
    /// legacy display-mode value is copied onto the new key and returned.
    /// Nothing stored returns `fallback` and writes nothing.
    static func resolve(
        defaults: UserDefaults = .standard,
        arrangementKey: String,
        legacyDisplayModeKey: String?,
        fallback: WorkListArrangement = .list
    ) -> WorkListArrangement {
        if let stored = defaults.string(forKey: arrangementKey),
           let arrangement = WorkListArrangement(rawValue: stored) {
            return arrangement
        }
        if let legacyDisplayModeKey,
           let mapped = arrangement(fromStoredDisplayMode: defaults.string(forKey: legacyDisplayModeKey)) {
            defaults.set(mapped.rawValue, forKey: arrangementKey)
            return mapped
        }
        return fallback
    }
}

/// What a long-press preview may say. Pure so the blur rule is testable: a
/// hidden work has a title and nothing else.
struct WorkLongPressFacts: Equatable, Sendable {
    var title: String
    var summary: String
    var tags: [String]

    static let hiddenTitle = "Hidden work"

    static func hidden() -> Self {
        Self(title: hiddenTitle, summary: "", tags: [])
    }

    /// Summary is stripped of HTML. Tag groups are fandoms, then warnings,
    /// relationships, characters and freeforms. Names are trimmed, empties
    /// drop, and the first spelling of a repeated name wins.
    static func visible(title: String, summaryHTML: String, tagGroups: [[String]]) -> Self {
        Self(
            title: title,
            summary: summaryHTML.strippingHTML().trimmingCharacters(in: .whitespacesAndNewlines),
            tags: tags(groups: tagGroups)
        )
    }

    static func tags(groups: [[String]]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in groups.joined() {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
}
