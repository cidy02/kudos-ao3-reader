import Foundation

/// What restarts Collection Items. The collections list uses
/// `AO3AccountWorksLoadID` for the same session pair. The tab is part of
/// this id; the page is not. A page change must not look like a new session,
/// and it must not drop staged item edits.
struct AO3CollectionItemsLoadID: Equatable, Sendable {
    var sessionGeneration: Int
    var isLoggedIn: Bool
    var tab: AO3CollectionItemTab
}

/// Rows and drafts the collections screens drop when the AO3 session changes.
///
/// The decision to drop them is `AO3AccountWorksSessionReload.shouldClear`.
/// The decision to keep a finished load or submit is
/// `shouldApplyCapturedGeneration`. Filters are not in here: they are a
/// client-side choice, and a new session must not reset them. Staging is
/// in here because a draft is an edit of one account's items.
enum AO3CollectionSessionReload {
    struct ClearedList: Equatable {
        var collections: [AO3Collection] = []
        var currentPage = 1
        var totalPages = 1
    }

    struct ClearedItems: Equatable {
        var items: [AO3CollectionItem] = []
        var currentPage = 1
        var totalPages = 1
        var staging = AO3CollectionItemStaging()
        var submitError: String?
    }

    static let clearedList = ClearedList()
    static let clearedItems = ClearedItems()

    /// Idle and loading both draw a spinner while the item list is empty.
    /// Signed out has to be this failure, or that spinner never ends.
    static let signedOutItemsMessage = "Log in to AO3 to manage collection items."

    struct ListTask: Equatable {
        var clearAccountState: Bool
        var loadPageOne: Bool
    }

    struct ItemsTask: Equatable {
        var clearAccountState: Bool
        /// Page 1 of the current tab. False for a same-session reappearance
        /// of a page that already settled, and false while signed out.
        var loadPageOne: Bool
    }

    /// The only phases that change the items task. A failure and a submit
    /// are both settled: one has finished, and the other must not be reloaded
    /// out from under the write.
    enum ItemsPhase: Equatable {
        case idle, loading, settled
    }

    /// True when the stored rows belong to this generation. Nil has no owner,
    /// so the first run does not draw whatever the arrays start as.
    static func ownsScreen(boundGeneration: Int?, sessionGeneration: Int) -> Bool {
        !AO3AccountWorksSessionReload.shouldClear(
            boundGeneration: boundGeneration,
            sessionGeneration: sessionGeneration
        )
    }

    /// Retires every load that already captured `current`. The caller does
    /// this synchronously, before its next await, on a new generation.
    static func nextLoadGeneration(_ current: Int) -> Int {
        current + 1
    }

    /// The load-result fence already on both screens. A matching pair may
    /// write the page. Anything else must leave the screen alone.
    static func shouldApplyLoad(
        capturedLoadGeneration: Int,
        loadGeneration: Int,
        capturedSessionGeneration: Int,
        sessionGeneration: Int
    ) -> Bool {
        capturedLoadGeneration == loadGeneration
            && AO3AccountWorksSessionReload.shouldApplyCapturedGeneration(
                capturedSessionGeneration,
                sessionGeneration: sessionGeneration
            )
    }

    static func listTask(
        boundGeneration: Int?,
        phaseIsIdle: Bool,
        sessionGeneration: Int,
        isLoggedIn: Bool
    ) -> ListTask {
        let clear = AO3AccountWorksSessionReload.shouldClear(
            boundGeneration: boundGeneration,
            sessionGeneration: sessionGeneration
        )
        // Clearing makes the screen idle. A same-generation run whose phase
        // is already idle is `finishAccepting`: the generation moved earlier,
        // while status was still signing in, and this run is the one that
        // fetches. A loaded page at this generation is a reappearance.
        let load = isLoggedIn && (clear || phaseIsIdle)
        return ListTask(clearAccountState: clear, loadPageOne: load)
    }

    static func itemsTask(
        boundGeneration: Int?,
        loadedTab: AO3CollectionItemTab?,
        phase: ItemsPhase,
        session: AO3AccountWorksLoadID,
        tab: AO3CollectionItemTab
    ) -> ItemsTask {
        let clear = AO3AccountWorksSessionReload.shouldClear(
            boundGeneration: boundGeneration,
            sessionGeneration: session.sessionGeneration
        )
        // `.loading` at the start of a task is a fetch the previous task
        // already lost: SwiftUI cancelled it by starting this one. A settled
        // failure is not that, and neither is a submit still in flight.
        // A tab change is, even when the previous tab had finished.
        let load = session.isLoggedIn && (
            clear || phase == .idle || phase == .loading || loadedTab != tab
        )
        return ItemsTask(clearAccountState: clear, loadPageOne: load)
    }
}
