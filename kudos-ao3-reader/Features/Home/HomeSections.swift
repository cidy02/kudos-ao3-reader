import Foundation

/// The local (library-backed) sections of the Home dashboard. `title` drives both
/// the carousel header and the pushed "See all" page; `works(from:visible:)` is the
/// single source of each section's filter + ordering, so the carousel and the
/// full list never drift. (Network sections — Subscriptions, Recently Updated —
/// are handled separately in `HomeView`.)
enum HomeSectionKind: String, Identifiable, Hashable, CaseIterable {
    case readingNow
    case recentlyUpdated

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .readingNow: "Reading Now"
        case .recentlyUpdated: "Recently Updated"
        }
    }

    /// How the section is ordered, in the reader's own words — printed under the
    /// hero on the pushed page (spec 1ad: "4 works · most recently read first").
    /// It sits beside `works(from:visible:)` deliberately: the sentence and the
    /// `sorted` call it describes are two halves of one fact, and separating them
    /// is how a page ends up claiming an order it does not have.
    var orderDescription: String {
        switch self {
        case .readingNow: "most recently read first"
        case .recentlyUpdated: "newest check first"
        }
    }

    /// Per-section empty-state copy (from the layout spec).
    var emptyMessage: String {
        switch self {
        case .readingNow:
            "You're not reading anything right now. Start exploring in Browse or open something from your Library."
        case .recentlyUpdated:
            // Built from works saved in the library (`WorkUpdateChecker`), not from
            // AO3 subscriptions, so the copy must not name them. Android's wording,
            // per docs/iOS_Issues_Found_While_Porting.md §1.
            "No recent updates from your library works yet."
        }
    }

    /// The label over the rows themselves, which is the *state* they are in
    /// rather than the section's name — 1ad heads its list "IN PROGRESS" and 1ae
    /// heads its grid "NEW CHAPTERS", where the page title above already says
    /// Reading Now / Recently Updated. Repeating the title inside the page said
    /// the same thing twice and named the shelf instead of the condition.
    var groupTitle: String {
        switch self {
        case .readingNow: "In progress"
        case .recentlyUpdated: "New chapters"
        }
    }

    var emptyIcon: String {
        switch self {
        case .readingNow: "book"
        case .recentlyUpdated: "sparkles"
        }
    }

    /// The works for this section — filtered + ordered, uncapped. `visible` is the
    /// privacy predicate (callers pass `passesPrivacy`); carousels cap the result.
    func works(from works: [SavedWork], visible: (SavedWork) -> Bool) -> [SavedWork] {
        switch self {
        case .readingNow:
            // In-progress (started, not finished, file present) — most recently read first.
            works
                .filter { $0.isInProgress && !$0.isQueueOnlyWork && visible($0) }
                .sorted { recency($0) > recency($1) }
        case .recentlyUpdated:
            // Works AO3 has added chapters to since the user last saw them.
            works
                .filter { $0.hasUpdate && !$0.isQueueOnlyWork && visible($0) }
                .sorted { ($0.lastUpdateCheck ?? .distantPast) > ($1.lastUpdateCheck ?? .distantPast) }
        }
    }

    private func recency(_ work: SavedWork) -> Date {
        work.lastReadDate ?? work.dateAdded
    }
}

/// The count beside Home's Subscriptions header. Home loads only page 1, and AO3
/// pages subscriptions `ITEMS_PER_PAGE` (25) at a time, so the number of cards is
/// the reader's total only when that page was the whole list. The page's own
/// pagination, recorded in `AO3AccountListCountsCache`, is what says so: an exact
/// count means one page. Otherwise the header shows no number, as
/// `WorkCarouselSection` asks, rather than printing 25 for a reader with 45.
enum HomeSubscriptionsCount {
    static func itemCount(shown: Int, recorded: AO3AccountListCount?) -> Int? {
        recorded?.exact == nil ? nil : shown
    }
}

/// The Subscriptions section's empty-state copy. A failed first load is not an
/// empty list: saying "not subscribed" there tells a reader with fifty
/// subscriptions that they have none.
enum HomeSubscriptionsCopy {
    static func emptyMessage(isLoggedIn: Bool, loadFailed: Bool) -> String {
        guard isLoggedIn else {
            return "Log in to AO3 to see the works and series you subscribe to."
        }
        return loadFailed
            ? "Couldn't load your subscriptions. Pull down to try again."
            : "You're not subscribed to anything yet. Subscribe to works or series to see updates here."
    }
}
