import Foundation

/// Artboard **1aj**'s quick-filter rail over Favorites' Works scope: All, Rereads,
/// Offline, WIP, single-select with All as the drawn default.
///
/// A value with its own rule rather than a `switch` inside the list view, matching
/// `LibraryHistoryGrouping` and `ReadingAffinities`: each case is a claim about
/// which works belong, two of the three are arguable (is "WIP" the work's posted
/// status or your progress? is one finish a reread?), and a rule you can hand
/// fixtures to is a rule you can check.
nonisolated enum FavoriteQuickFilter: String, CaseIterable, Hashable, Identifiable, Sendable {
    case all
    case rereads
    case offline
    case wip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .rereads: "Rereads"
        case .offline: "Offline"
        case .wip: "WIP"
        }
    }

    /// Narrows `works` to this filter.
    ///
    /// `finishCounts` maps a work id to the number of times it has been *finished*,
    /// which is the reread count — two sittings of one read-through are one read, so
    /// a reread is a second finish rather than a second visit. Only `.rereads` reads
    /// it; the caller need not compute it otherwise.
    @MainActor
    func apply(to works: [SavedWork], finishCounts: [UUID: Int]) -> [SavedWork] {
        switch self {
        case .all:
            works
        case .rereads:
            works.filter { (finishCounts[$0.id] ?? 0) > 1 }
        case .offline:
            works.filter(\.hasEPUB)
        case .wip:
            // AO3's posted status, not how far in you are. The chip sits beside
            // Rereads and Offline, which are both facts about the work itself, and
            // Library already has a separate reading-state axis.
            works.filter { !$0.isComplete }
        }
    }
}

/// Artboard **1ak**'s quick-filter rail over Favorites' Authors scope.
///
/// This deliberately owns the author rule rather than adding another case to
/// `FavoriteQuickFilter`: works and authors make different claims, and a row with
/// no registered account cannot honestly be checked for new AO3 work.
nonisolated enum FavoriteAuthorQuickFilter: String, CaseIterable, Hashable, Identifiable, Sendable {
    case all
    case withNewWork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .withNewWork: "With new work"
        }
    }

    /// Narrows author rows to accounts whose newest fetched work is not in the
    /// reader's opened-work set. Cache misses and rows without an account do not
    /// match: treating either as new would turn unknown data into a positive claim.
    func apply(
        to rows: [ReadingAffinities.Row],
        newestWorkForUsername: (String) -> AO3WorkSummary??,
        readWorkIDs: Set<Int>
    ) -> [ReadingAffinities.Row] {
        switch self {
        case .all:
            rows
        case .withNewWork:
            rows.filter { row in
                guard let username = row.username,
                      let cachedWork = newestWorkForUsername(username),
                      let newestWork = cachedWork
                else { return false }
                return !readWorkIDs.contains(newestWork.id)
            }
        }
    }
}
