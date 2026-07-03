import Foundation

/// The local (library-backed) sections of the Library dashboard, mirroring the Home
/// dashboard's `HomeSectionKind`. Order matches the layout spec: Reading Now, Saved
/// for Later, Finished, Collections, Downloaded. `works(from:visible:)` is the single
/// source of each section's filter + ordering, so the carousel and the full "See all"
/// list never drift. (Saved for Later also merges in the user's AO3 "Marked for
/// Later" list; Collections is a placeholder with no backing model yet — both are
/// handled in the views.)
enum LibrarySectionKind: String, Identifiable, Hashable, CaseIterable {
    case readingNow
    case savedForLater
    case finished
    case collections
    case downloaded

    var id: String {
        rawValue
    }

    /// Collections has no backing model yet — it always shows its placeholder state.
    var isPlaceholder: Bool {
        self == .collections
    }

    var title: String {
        switch self {
        case .readingNow: "Reading Now"
        case .savedForLater: "Saved for Later"
        case .finished: "Finished"
        case .collections: "Collections"
        case .downloaded: "Downloaded"
        }
    }

    /// Per-section empty-state copy.
    var emptyMessage: String {
        switch self {
        case .readingNow:
            "You're not reading anything right now. Open something below or find a new work in Browse."
        case .savedForLater:
            "Nothing saved for later yet. Save works here, or mark them for later on AO3."
        case .finished:
            "No finished works yet. Works you complete show up here."
        case .collections:
            "Collections are coming soon — a place to group your works into shelves."
        case .downloaded:
            "No downloads yet. Download a work as EPUB to read it offline."
        }
    }

    var emptyIcon: String {
        switch self {
        case .readingNow: "book"
        case .savedForLater: "bookmark"
        case .finished: "checkmark.circle"
        case .collections: "square.stack"
        case .downloaded: "arrow.down.circle"
        }
    }

    /// The local works for this kind — filtered + ordered, uncapped. `visible` is the
    /// privacy predicate (callers pass `passesPrivacy`); callers also apply
    /// `LibraryFilters` and cap the result for the carousel.
    func works(from works: [SavedWork], visible: (SavedWork) -> Bool) -> [SavedWork] {
        switch self {
        case .readingNow:
            // In-progress (started, not finished, file present) — most recently read first.
            works
                .filter { $0.isInProgress && !$0.isQueueOnlyWork && visible($0) }
                .sorted { recency($0) > recency($1) }
        case .savedForLater:
            // Native Saved for Later queue members plus legacy "saved" works that
            // predate queues. Queue-only works intentionally live here, not in the
            // normal downloaded/finished shelves.
            works
                .filter { ($0.isInSavedForLaterQueue || ($0.isSaved && !$0.isQueuedForLater)) && visible($0) }
                .sorted { recency($0) > recency($1) }
        case .finished:
            works
                .filter { $0.isFinished && !$0.isQueueOnlyWork && visible($0) }
                .sorted { ($0.lastReadDate ?? .distantPast) > ($1.lastReadDate ?? .distantPast) }
        case .collections:
            []
        case .downloaded:
            // Everything with its EPUB on disk — the full offline shelf, newest first.
            works
                .filter { $0.hasEPUB && !$0.isQueueOnlyWork && visible($0) }
                .sorted { $0.dateAdded > $1.dateAdded }
        }
    }

    private func recency(_ work: SavedWork) -> Date {
        work.lastReadDate ?? work.dateAdded
    }
}
