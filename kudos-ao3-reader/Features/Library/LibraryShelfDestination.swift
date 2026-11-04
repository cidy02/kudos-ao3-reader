import Foundation

/// Unified destination for opening a library shelf from its section header "See All"
/// or from its tile in the Shelves button grid.
enum LibraryShelfDestination {
    static func destination(for shelf: LibraryShelfID) -> AnyHashable {
        switch shelf {
        case .collections:
            return AllCollectionsDestination()
        case .queues:
            return AllReadingQueuesDestination(initialQueueID: nil)
        case .imported:
            return LibraryCatalogueDestination(kind: .imported)
        case .favourites:
            return LibrarySectionRoute(kind: .favorites, originKicker: "Library")
        case .downloaded:
            return LibrarySectionRoute(kind: .downloaded, originKicker: "Library")
        case .wantToRead:
            return LibrarySectionRoute(kind: .savedForLater, originKicker: "Library")
        case .readingNow:
            return LibrarySectionRoute(kind: .readingNow, originKicker: "Library")
        case .finished:
            return LibrarySectionRoute(kind: .finished, originKicker: "Library")
        case .history:
            return LibrarySectionRoute(kind: .history, originKicker: "Library")
        }
    }
}
