import Foundation

/// The local (library-backed) sections of the Home dashboard. `title` drives both
/// the carousel header and the pushed "See all" page; `works(from:visible:)` is the
/// single source of each section's filter + ordering, so the carousel and the
/// full list never drift. (Network sections — Subscriptions, Recently Updated —
/// are handled separately in `HomeView`.)
enum HomeSectionKind: String, Identifiable, Hashable, CaseIterable {
    case readingNow
    case favorites
    case recentlyOpened

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readingNow: "Reading Now"
        case .favorites: "Favorites"
        case .recentlyOpened: "Recently Opened"
        }
    }

    /// The works for this section — filtered + ordered, uncapped. `visible` is the
    /// privacy predicate (callers pass `passesPrivacy`); carousels cap the result.
    func works(from works: [SavedWork], visible: (SavedWork) -> Bool) -> [SavedWork] {
        switch self {
        case .readingNow:
            // In-progress: has its EPUB, started, not finished — most recently read first.
            return works
                .filter {
                    $0.hasEPUB && !$0.isFinished
                        && ($0.lastSpineIndex > 0 || $0.lastScrollFraction > 0)
                        && visible($0)
                }
                .sorted { recency($0) > recency($1) }
        case .favorites:
            return works
                .filter { $0.isFavorite && visible($0) }
                .sorted { recency($0) > recency($1) }
        case .recentlyOpened:
            // Anything actually opened (has a read date), newest first.
            return works
                .filter { $0.lastReadDate != nil && visible($0) }
                .sorted { ($0.lastReadDate ?? .distantPast) > ($1.lastReadDate ?? .distantPast) }
        }
    }

    private func recency(_ work: SavedWork) -> Date { work.lastReadDate ?? work.dateAdded }
}
