import SwiftUI

/// 1bk's "Show on Home adds a shelf above Recently Updated" (T-276): each local
/// collection flagged `showsOnHome` is a Home carousel after Reading Queues.
enum HomeCollectionShelves {
    /// The flagged collections, not in Recently Deleted, in the Library's order
    /// (the reader's `sortOrder`, then name).
    static func shelves(_ collections: [WorkCollection]) -> [WorkCollection] {
        collections
            .filter { $0.showsOnHome && !$0.isPendingDeletion }
            .sorted { lhs, rhs in
                switch (lhs.sortOrder, rhs.sortOrder) {
                case let (left?, right?) where left != right: return left < right
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
    }

    /// A shelf's works: the collection's own order, without works in Recently
    /// Deleted or hidden by the privacy gate.
    static func works(in collection: WorkCollection, visible: (SavedWork) -> Bool) -> [SavedWork] {
        collection.inReadingOrder(collection.works.filter { !$0.isPendingDeletion && visible($0) })
    }
}

/// One collection's Home shelf, built from Home's own carousel and cards.
struct HomeCollectionShelf: View {
    let collection: WorkCollection
    let works: [SavedWork]
    let onSeeAll: () -> Void

    var body: some View {
        WorkCarouselSection(
            title: collection.name,
            collapseKey: "home.collection.\(collection.id.uuidString)",
            hasItems: !works.isEmpty,
            itemCount: works.isEmpty ? nil : works.count,
            onSeeAll: onSeeAll
        ) {
            ForEach(works.prefix(12)) { work in
                NavigationLink(value: LocalWorkDestination.reader(work)) {
                    SensitiveWorkCoverCard(work: work, progress: work.readingProgress)
                }
                .buttonStyle(.plain)
                .localWorkContextMenu(work: work)
            }
        } emptyState: {
            SectionEmptyState(message: "No works in this collection yet.", systemImage: "square.stack")
        }
    }
}
