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
