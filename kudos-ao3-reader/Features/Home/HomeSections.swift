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

    /// Per-section empty-state copy (from the layout spec).
    var emptyMessage: String {
        switch self {
        case .readingNow:
            "You're not reading anything right now. Start exploring in Browse or open something from your Library."
        case .recentlyUpdated:
            "No recent updates from your subscriptions yet."
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
