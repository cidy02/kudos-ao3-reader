import Foundation

/// The local (library-backed) sections of the Library dashboard, mirroring the Home
/// dashboard's `HomeSectionKind`. Order matches the layout spec: Reading Now, Saved
/// for Later, Finished, Collections, Downloaded, History, Favorites.
/// `works(from:visible:)` is the single source of each section's filter + ordering,
/// so the carousel and the full "See all" list never drift. Saved for Later is
/// local; AO3 Marked for Later is a separate Account destination. Collections
/// use their own destination rather than this work-list enum.
enum LibrarySectionKind: String, Identifiable, Hashable, CaseIterable {
    case readingNow
    case savedForLater
    case finished
    case collections
    case downloaded
    case history
    case favorites

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
        case .history: "Reading History"
        case .favorites: "Favorites"
        }
    }

    /// The label over the rows themselves, which names the state they are in
    /// rather than the shelf — 1ad heads Reading Now's list "IN PROGRESS", as
    /// `HomeSectionKind.groupTitle` already does. The other sections have no
    /// board of their own for this and keep their title.
    var groupTitle: String {
        switch self {
        case .readingNow: "In progress"
        default: title
        }
    }

    /// How the section is ordered, in the reader's own words — the tally under the
    /// hero ends with it (spec 1ad: "4 works · most recently read first"). Each
    /// phrase describes the `sorted` call for the same case in
    /// `works(from:visible:)`; change one and the other goes with it. Empty for
    /// Collections, which lists no works here.
    var orderDescription: String {
        switch self {
        case .readingNow, .finished, .history: "most recently read first"
        case .savedForLater: "most recently read or added first"
        case .downloaded, .favorites: "newest first"
        case .collections: ""
        }
    }

    /// Per-section empty-state copy.
    var emptyMessage: String {
        switch self {
        case .readingNow:
            "You're not reading anything right now. Open something below or find a new work in Browse."
        case .savedForLater:
            "Nothing saved for later yet. Add works to your local Saved for Later queue."
        case .finished:
            "No finished works yet. Works you complete show up here."
        case .collections:
            "Collections are coming soon — a place to group your works into shelves."
        case .downloaded:
            "No downloads yet. Download a work as EPUB to read it offline."
        case .history:
            "Nothing read yet. Works you open land here with the time you spent on "
                + "them, how often you have reread them, and whether they changed since."
        case .favorites:
            "Swipe a work in your Library, or tap the star on its page, to favorite it."
        }
    }

    var emptyIcon: String {
        switch self {
        case .readingNow: "book"
        case .savedForLater: WorkActionLabels.savedForLaterEmptySymbol
        case .finished: "checkmark.circle"
        case .collections: "square.stack"
        case .downloaded: "arrow.down.circle"
        case .history: "clock.arrow.circlepath"
        case .favorites: "star"
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
                .filter { $0.readingState == .inProgress && !$0.isQueueOnlyWork && visible($0) }
                .sorted { recency($0) > recency($1) }
        case .savedForLater:
            // Native Saved for Later queue members plus legacy "saved" works that
            // predate queues. Queue-only works intentionally live here, not in the
            // normal downloaded/finished shelves.
            works
                .filter { $0.isOnSavedForLaterShelf && visible($0) }
                .sorted { recency($0) > recency($1) }
        case .finished:
            works
                .filter { $0.readingState == .finished && !$0.isQueueOnlyWork && visible($0) }
                .sorted { ($0.lastReadDate ?? .distantPast) > ($1.lastReadDate ?? .distantPast) }
        case .collections:
            []
        case .downloaded:
            // Everything with its EPUB on disk — the full offline shelf, newest first.
            works
                .filter { $0.hasEPUB && !$0.isQueueOnlyWork && visible($0) }
                .sorted { $0.dateAdded > $1.dateAdded }
        case .history:
            // Works you have actually read — artboard 1ah's "the local one, not
            // AO3's". This was `!hasEPUB` (downloads freed after finishing), which
            // was the only reading record the app had before the local reading log
            // landed. That partition cannot hold 1ah's own content: hours spent,
            // reread count and changed-since are all zero for a work freed without
            // ever being opened, and 1ai's Abandoned section — mid-way and untouched
            // — could never populate at all, because being mid-way needs the EPUB
            // that `!hasEPUB` excludes.
            //
            // Reading evidence rather than file state, so a freed work you did read
            // stays and a queue-only work you never opened never arrives; the
            // `!isQueuedForLater` guard that kept those out is no longer what does
            // the work. Ordered most-recently-read, which is the order
            // `LibraryHistoryGrouping` buckets assume.
            works
                .filter { ($0.hasStartedReading || $0.isFinished) && visible($0) }
                .sorted { recency($0) > recency($1) }
        case .favorites:
            works
                .filter { $0.isFavorite && visible($0) }
                .sorted { $0.dateAdded > $1.dateAdded }
        }
    }

    private func recency(_ work: SavedWork) -> Date {
        work.lastReadDate ?? work.dateAdded
    }
}

/// A Library section opened from somewhere that is not Library.
///
/// The plain `LibrarySectionKind` destination stays for Library's own chevrons,
/// which are already in the right tab and need no anchor of their own; this
/// carries the origin for deep-links, per 1c's shared-destination rule.
nonisolated struct LibrarySectionRoute: Hashable, Sendable {
    let kind: LibrarySectionKind
    let originKicker: String
}
