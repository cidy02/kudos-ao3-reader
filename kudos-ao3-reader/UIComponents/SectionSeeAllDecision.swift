import Foundation

/// Pure logic decision for See All and "+N more" / "N more" closers across content shelves and lists (T-483).
///
/// Rule: A section shows See All only when something is hidden; it then says how many
/// (a count beside the title, "+N more" closing a shelf, "N more" closing a list), and
/// See All and the "more" both open that category's own page. When everything fits, the link
/// names what it does instead (e.g. "Organise").
struct SectionSeeAllDecision: Equatable, Sendable {
    let totalCount: Int
    let visibleCount: Int
    let actionTitleWhenFitting: String?

    init(totalCount: Int, visibleCount: Int, actionTitleWhenFitting: String? = nil) {
        self.totalCount = max(0, totalCount)
        self.visibleCount = max(0, visibleCount)
        self.actionTitleWhenFitting = actionTitleWhenFitting
    }

    /// True only when there are items beyond the ones currently visible.
    var isSomethingHidden: Bool {
        totalCount > visibleCount && totalCount > 0
    }

    /// The number of items remaining hidden.
    var hiddenCount: Int {
        max(0, totalCount - visibleCount)
    }

    /// Header trailing action link: "See All" when items are hidden;
    /// `actionTitleWhenFitting` when all items fit; `nil` when empty or no action specified.
    var headerLinkLabel: String? {
        guard totalCount > 0 else { return nil }
        if isSomethingHidden {
            return "See All"
        }
        return actionTitleWhenFitting
    }

    /// Whether a carousel should render a "+N more" tile at its trailing end.
    var showsCarouselMoreTile: Bool {
        isSomethingHidden && hiddenCount > 0
    }

    /// Whether a list should render an "N more" row at its end.
    var showsListMoreRow: Bool {
        isSomethingHidden && hiddenCount > 0
    }
}
