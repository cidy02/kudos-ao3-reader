import Foundation
import Testing
@testable import Kudos

/// The collections screens' load tasks are SwiftUI `.task`s. These tests cover
/// the decisions those tasks apply, not the view lifecycle. Nothing signs in
/// or talks to AO3.
struct AO3CollectionSessionReloadTests {
    private struct ListScreen {
        var boundGeneration: Int?
        var sessionGeneration = 0
        var isLoggedIn = false
        var loadGeneration = 0
        var rowNames: [String] = []
        var currentPage = 1
        var totalPages = 1
        var phaseIsIdle = true
        var filters = AO3CollectionsFilter()
        var didStartPageOne = false

        var ownsScreen: Bool {
            AO3CollectionSessionReload.ownsScreen(
                boundGeneration: boundGeneration,
                sessionGeneration: sessionGeneration
            )
        }

        var presentedRowNames: [String] {
            ownsScreen ? rowNames : []
        }

        mutating func task(sessionGeneration: Int, isLoggedIn: Bool) -> Bool {
            self.sessionGeneration = sessionGeneration
            self.isLoggedIn = isLoggedIn
            let decision = AO3CollectionSessionReload.listTask(
                boundGeneration: boundGeneration,
                phaseIsIdle: phaseIsIdle,
                sessionGeneration: sessionGeneration,
                isLoggedIn: isLoggedIn
            )
            if decision.clearAccountState {
                loadGeneration = AO3CollectionSessionReload.nextLoadGeneration(loadGeneration)
                let cleared = AO3CollectionSessionReload.clearedList
                rowNames = cleared.collections.map(\.name)
                currentPage = cleared.currentPage
                totalPages = cleared.totalPages
                phaseIsIdle = true
                boundGeneration = sessionGeneration
            }
            didStartPageOne = decision.loadPageOne
            if decision.loadPageOne {
                loadGeneration = AO3CollectionSessionReload.nextLoadGeneration(loadGeneration)
                phaseIsIdle = false
            }
            return decision.loadPageOne
        }
    }

    private struct ItemsScreen {
        enum Phase: Equatable {
            case idle, loading, loaded, submitting, failed(String)
        }

        var boundGeneration: Int?
        var sessionGeneration = 0
        var isLoggedIn = false
        var loadGeneration = 0
        var tab: AO3CollectionItemTab = .invited
        var loadedTab: AO3CollectionItemTab?
        var rowIDs: [Int] = []
        var currentPage = 1
        var totalPages = 1
        var staging = AO3CollectionItemStaging()
        var submitError: String?
        var phase: Phase = .idle
        var didStartPageOne = false

        var ownsScreen: Bool {
            AO3CollectionSessionReload.ownsScreen(
                boundGeneration: boundGeneration,
                sessionGeneration: sessionGeneration
            )
        }

        var presentedRowIDs: [Int] {
            ownsScreen ? rowIDs : []
        }

        /// Signed out draws the login failure. Idle and loading are the
        /// spinner, and neither is used while signed out.
        var itemsPhase: AO3CollectionSessionReload.ItemsPhase {
            switch phase {
            case .idle: .idle
            case .loading: .loading
            case .loaded, .submitting: .settled
            case .failed: .settled
            }
        }

        var showsLoginFailure: Bool { !isLoggedIn }
        var showsSpinner: Bool {
            guard isLoggedIn else { return false }
            if !ownsScreen { return true }
            switch phase {
            case .idle, .loading: return rowIDs.isEmpty
            case .loaded, .submitting, .failed: return false
            }
        }

        mutating func task(sessionGeneration: Int, isLoggedIn: Bool, tab: AO3CollectionItemTab) -> Bool {
            self.sessionGeneration = sessionGeneration
            self.isLoggedIn = isLoggedIn
            let decision = AO3CollectionSessionReload.itemsTask(
                boundGeneration: boundGeneration,
                loadedTab: loadedTab,
                phase: itemsPhase,
                session: AO3AccountWorksLoadID(
                    sessionGeneration: sessionGeneration,
                    isLoggedIn: isLoggedIn
                ),
                tab: tab
            )
            self.tab = tab
            if decision.clearAccountState {
                loadGeneration = AO3CollectionSessionReload.nextLoadGeneration(loadGeneration)
                let cleared = AO3CollectionSessionReload.clearedItems
                rowIDs = cleared.items.map(\.id)
                currentPage = cleared.currentPage
                totalPages = cleared.totalPages
                staging = cleared.staging
                submitError = cleared.submitError
                loadedTab = nil
                phase = .idle
                boundGeneration = sessionGeneration
            }
            didStartPageOne = decision.loadPageOne
            if decision.loadPageOne {
                loadedTab = tab
                loadGeneration = AO3CollectionSessionReload.nextLoadGeneration(loadGeneration)
                rowIDs = []
                currentPage = 1
                totalPages = 1
                phase = .loading
            }
            return decision.loadPageOne
        }

        /// Pagination. Not the load task: the page is not part of the task id,
        /// and this does not drop drafts.
        mutating func changePage(to page: Int) {
            loadGeneration = AO3CollectionSessionReload.nextLoadGeneration(loadGeneration)
            currentPage = page
            phase = .loading
        }

        mutating func finishSubmit(captured: Int, clearIDs: [Int], failure: String?) -> Bool {
            guard AO3AccountWorksSessionReload.shouldApplyCapturedGeneration(
                captured,
                sessionGeneration: sessionGeneration
            ) else { return false }
            if let failure {
                submitError = failure
                phase = .loaded
            } else {
                staging.clear(itemIDs: clearIDs)
            }
            return true
        }

        mutating func applyLoad(capturedLoad: Int, capturedSession: Int, rows: [Int]) -> Bool {
            guard AO3CollectionSessionReload.shouldApplyLoad(
                capturedLoadGeneration: capturedLoad,
                loadGeneration: loadGeneration,
                capturedSessionGeneration: capturedSession,
                sessionGeneration: sessionGeneration
            ) else { return false }
            rowIDs = rows
            phase = .loaded
            return true
        }
    }

    private func item(_ id: Int) -> AO3CollectionItem {
        AO3CollectionItem(
            id: id,
            collectionSlug: "tidewrack",
            collectionTitle: "Tidewrack",
            workTitle: "The Weight of Water",
            userApprovalField: "u",
            collectionApprovalField: "c",
            unrevealedField: "un",
            anonymousField: "an",
            removeField: "rm"
        )
    }

    @Test func theListLoadIDChangesForANewGenerationAndForTheSignedInFlag() {
        let signedIn = AO3AccountWorksLoadID(sessionGeneration: 4, isLoggedIn: true)
        #expect(signedIn != AO3AccountWorksLoadID(sessionGeneration: 5, isLoggedIn: true))
        #expect(signedIn != AO3AccountWorksLoadID(sessionGeneration: 4, isLoggedIn: false))
        #expect(signedIn == AO3AccountWorksLoadID(sessionGeneration: 4, isLoggedIn: true))
    }

    @Test func theItemsLoadIDAlsoChangesWhenTheTabChangesAndIgnoresThePage() {
        let invited = AO3CollectionItemsLoadID(sessionGeneration: 4, isLoggedIn: true, tab: .invited)
        #expect(invited != AO3CollectionItemsLoadID(sessionGeneration: 5, isLoggedIn: true, tab: .invited))
        #expect(invited != AO3CollectionItemsLoadID(sessionGeneration: 4, isLoggedIn: false, tab: .invited))
        #expect(invited != AO3CollectionItemsLoadID(sessionGeneration: 4, isLoggedIn: true, tab: .approved))
        // A page change has no field on the id, so it cannot restart the task.
        #expect(invited == AO3CollectionItemsLoadID(sessionGeneration: 4, isLoggedIn: true, tab: .invited))
    }

    @Test func aClearedSessionKeepsNoRowsDraftsOrSubmitError() {
        let list = AO3CollectionSessionReload.clearedList
        #expect(list.collections.isEmpty)
        #expect(list.currentPage == 1)
        #expect(list.totalPages == 1)

        let items = AO3CollectionSessionReload.clearedItems
        #expect(items.items.isEmpty)
        #expect(items.currentPage == 1)
        #expect(items.totalPages == 1)
        #expect(items.staging == AO3CollectionItemStaging())
        #expect(items.submitError == nil)
        #expect(AO3CollectionSessionReload.signedOutItemsMessage == "Log in to AO3 to manage collection items.")
    }

    @Test func ownsScreenIsFalseUntilTheBoundGenerationIsCurrent() {
        #expect(!AO3CollectionSessionReload.ownsScreen(boundGeneration: nil, sessionGeneration: 4))
        #expect(!AO3CollectionSessionReload.ownsScreen(boundGeneration: 4, sessionGeneration: 5))
        #expect(AO3CollectionSessionReload.ownsScreen(boundGeneration: 5, sessionGeneration: 5))
    }

    @Test func aLoadResultAppliesOnlyForItsOwnLoadAndSession() {
        #expect(AO3CollectionSessionReload.shouldApplyLoad(
            capturedLoadGeneration: 3, loadGeneration: 3,
            capturedSessionGeneration: 4, sessionGeneration: 4
        ))
        #expect(!AO3CollectionSessionReload.shouldApplyLoad(
            capturedLoadGeneration: 3, loadGeneration: 4,
            capturedSessionGeneration: 4, sessionGeneration: 4
        ))
        #expect(!AO3CollectionSessionReload.shouldApplyLoad(
            capturedLoadGeneration: 3, loadGeneration: 3,
            capturedSessionGeneration: 4, sessionGeneration: 5
        ))
        let retired = AO3CollectionSessionReload.nextLoadGeneration(3)
        #expect(retired == 4)
        #expect(!AO3CollectionSessionReload.shouldApplyLoad(
            capturedLoadGeneration: 3, loadGeneration: retired,
            capturedSessionGeneration: 4, sessionGeneration: 4
        ))
    }

    /// Account A is on screen. Sign-out and the next login each bump the
    /// generation before status is signed-in, so those runs drop A's rows and
    /// must not fetch. The open-only filter is a client-side choice and stays.
    /// Coming back at the signed-in generation must not wipe the page just stored.
    @Test func anAccountSwitchDropsThePreviousCollectionsBeforeTheNextLoad() {
        var screen = ListScreen()
        screen.boundGeneration = 4
        screen.sessionGeneration = 4
        screen.isLoggedIn = true
        screen.phaseIsIdle = false
        screen.rowNames = ["alice-fest"]
        screen.currentPage = 2
        screen.totalPages = 3
        screen.filters.showsOpenOnly = true
        screen.loadGeneration = 2

        screen.sessionGeneration = 5
        #expect(!screen.ownsScreen)
        #expect(screen.presentedRowNames.isEmpty)
        #expect(screen.rowNames == ["alice-fest"])

        let signedOut = screen.task(sessionGeneration: 5, isLoggedIn: false)
        #expect(!signedOut)
        #expect(screen.rowNames.isEmpty)
        #expect(screen.currentPage == 1)
        #expect(screen.totalPages == 1)
        #expect(screen.filters.showsOpenOnly)
        #expect(screen.loadGeneration == 3)

        let stillSigningIn = screen.task(sessionGeneration: 6, isLoggedIn: false)
        #expect(!stillSigningIn)
        #expect(screen.rowNames.isEmpty)

        let fetches = screen.task(sessionGeneration: 6, isLoggedIn: true)
        #expect(fetches)
        #expect(screen.rowNames.isEmpty)
        #expect(screen.filters.showsOpenOnly)

        screen.rowNames = ["bob-fest"]
        screen.currentPage = 1
        screen.totalPages = 1
        screen.phaseIsIdle = false
        let reappear = screen.task(sessionGeneration: 6, isLoggedIn: true)
        #expect(!reappear)
        #expect(screen.rowNames == ["bob-fest"])
        #expect(screen.filters.showsOpenOnly)
    }

    @Test func aGenerationBumpWhileSignedInClearsCollectionsBeforeFetching() {
        var screen = ListScreen()
        screen.boundGeneration = 6
        screen.sessionGeneration = 6
        screen.phaseIsIdle = false
        screen.rowNames = ["bob-fest"]
        screen.filters.showsOpenOnly = true
        screen.loadGeneration = 4

        let fetches = screen.task(sessionGeneration: 7, isLoggedIn: true)
        #expect(fetches)
        #expect(screen.rowNames.isEmpty)
        #expect(screen.phaseIsIdle == false)
        #expect(screen.filters.showsOpenOnly)
        #expect(!AO3CollectionSessionReload.shouldApplyLoad(
            capturedLoadGeneration: 4,
            loadGeneration: screen.loadGeneration,
            capturedSessionGeneration: 6,
            sessionGeneration: screen.sessionGeneration
        ))
    }

    /// Signed out is the login failure, including the signing-in generation
    /// that has not reached `.signedIn` yet. The run that lands signed in
    /// fetches page 1 and is not still holding the previous drafts.
    @Test func aSignedOutItemsScreenAsksForLoginAndDoesNotSpinOrFetch() {
        var screen = ItemsScreen()
        screen.boundGeneration = 4
        screen.sessionGeneration = 4
        screen.isLoggedIn = true
        screen.phase = .loaded
        screen.loadedTab = .invited
        screen.rowIDs = [3]
        screen.currentPage = 2
        screen.totalPages = 4
        screen.submitError = "Earlier failure"
        screen.staging.setRemoved(true, for: item(3))
        screen.loadGeneration = 2

        screen.sessionGeneration = 5
        screen.isLoggedIn = false
        #expect(!screen.ownsScreen)
        #expect(screen.presentedRowIDs.isEmpty)
        #expect(screen.showsLoginFailure)
        #expect(!screen.showsSpinner)

        let signedOut = screen.task(sessionGeneration: 5, isLoggedIn: false, tab: .invited)
        #expect(!signedOut)
        #expect(screen.showsLoginFailure)
        #expect(!screen.showsSpinner)
        #expect(screen.rowIDs.isEmpty)
        #expect(screen.staging == AO3CollectionItemStaging())
        #expect(screen.submitError == nil)
        #expect(screen.currentPage == 1)
        #expect(screen.phase == .idle)
        #expect(screen.loadGeneration == 3)

        let stillSigningIn = screen.task(sessionGeneration: 6, isLoggedIn: false, tab: .invited)
        #expect(!stillSigningIn)
        #expect(screen.showsLoginFailure)
        #expect(!screen.showsSpinner)

        let fetches = screen.task(sessionGeneration: 6, isLoggedIn: true, tab: .invited)
        #expect(fetches)
        #expect(!screen.showsLoginFailure)
        #expect(screen.showsSpinner)
        #expect(screen.rowIDs.isEmpty)
        #expect(screen.staging == AO3CollectionItemStaging())
        #expect(screen.loadedTab == .invited)
    }

    @Test func aTabOrPageChangeKeepsStagingAndASettledReappearanceDoesNotReload() {
        var screen = ItemsScreen()
        screen.boundGeneration = 6
        screen.sessionGeneration = 6
        screen.isLoggedIn = true
        screen.phase = .loaded
        screen.loadedTab = .invited
        screen.tab = .invited
        screen.rowIDs = [8, 9]
        screen.currentPage = 2
        screen.totalPages = 3
        screen.submitError = "Keep this"
        screen.staging.setRemoved(true, for: item(8))
        let staged = screen.staging

        let reappear = screen.task(sessionGeneration: 6, isLoggedIn: true, tab: .invited)
        #expect(!reappear)
        #expect(screen.staging == staged)
        #expect(screen.rowIDs == [8, 9])
        #expect(screen.currentPage == 2)
        #expect(screen.submitError == "Keep this")

        let tabChange = screen.task(sessionGeneration: 6, isLoggedIn: true, tab: .approved)
        #expect(tabChange)
        #expect(screen.staging == staged)
        #expect(screen.submitError == "Keep this")
        #expect(screen.rowIDs.isEmpty)
        #expect(screen.currentPage == 1)
        #expect(screen.boundGeneration == 6)

        screen.phase = .loaded
        screen.rowIDs = [4]
        screen.currentPage = 1
        screen.changePage(to: 3)
        #expect(screen.staging == staged)
        #expect(screen.submitError == "Keep this")
        #expect(screen.rowIDs == [4])
        #expect(screen.currentPage == 3)
        #expect(screen.boundGeneration == 6)
        #expect(screen.phase == .loading)
    }

    @Test func aCancelledItemsLoadRestartsWithoutDroppingSameSessionDrafts() {
        var screen = ItemsScreen()
        screen.boundGeneration = 6
        screen.sessionGeneration = 6
        screen.isLoggedIn = true
        screen.phase = .loading
        screen.loadedTab = .invited
        screen.rowIDs = [8]
        screen.staging.setRemoved(true, for: item(8))
        let staged = screen.staging

        let restarted = screen.task(sessionGeneration: 6, isLoggedIn: true, tab: .invited)
        #expect(restarted)
        #expect(screen.staging == staged)
        #expect(screen.boundGeneration == 6)

        screen.phase = .failed("AO3 didn't answer.")
        screen.loadedTab = .invited
        screen.rowIDs = []
        let settledFailure = screen.task(sessionGeneration: 6, isLoggedIn: true, tab: .invited)
        #expect(!settledFailure)
        #expect(screen.phase == .failed("AO3 didn't answer."))

        screen.phase = .submitting
        screen.staging = staged
        let duringSubmit = screen.task(sessionGeneration: 6, isLoggedIn: true, tab: .invited)
        #expect(!duringSubmit)
        #expect(screen.phase == .submitting)
        #expect(screen.staging == staged)
    }

    /// Account A is mid-submit. The switch clears A's drafts. B stages a new
    /// one and starts a submit. A's success and A's failure must not clear B's
    /// draft, paint A's error, or change B's phase or rows.
    @Test func aStaleSubmitFinishLeavesTheNextAccountsItemsAlone() {
        var screen = ItemsScreen()
        screen.boundGeneration = 1
        screen.sessionGeneration = 1
        screen.isLoggedIn = true
        screen.phase = .submitting
        screen.loadedTab = .invited
        screen.rowIDs = [9]
        screen.staging.setRemoved(true, for: item(9))
        let captured = 1

        let switched = screen.task(sessionGeneration: 2, isLoggedIn: true, tab: .invited)
        #expect(switched)
        #expect(screen.staging == AO3CollectionItemStaging())
        screen.phase = .submitting
        screen.rowIDs = [4]
        screen.staging.setRemoved(true, for: item(4))
        screen.submitError = nil
        let bobsDraft = screen.staging

        let staleFailure = screen.finishSubmit(
            captured: captured, clearIDs: [4], failure: "Couldn't send."
        )
        #expect(!staleFailure)
        #expect(screen.phase == .submitting)
        #expect(screen.submitError == nil)
        #expect(screen.rowIDs == [4])
        #expect(screen.staging == bobsDraft)

        let staleSuccess = screen.finishSubmit(captured: captured, clearIDs: [4], failure: nil)
        #expect(!staleSuccess)
        #expect(screen.phase == .submitting)
        #expect(screen.rowIDs == [4])
        #expect(screen.staging == bobsDraft)

        let currentSuccess = screen.finishSubmit(captured: 2, clearIDs: [4], failure: nil)
        #expect(currentSuccess)
        #expect(screen.staging.pendingCount(for: [item(4)]) == 0)
        #expect(screen.rowIDs == [4])

        screen.staging.setRemoved(true, for: item(4))
        let currentFailure = screen.finishSubmit(captured: 2, clearIDs: [], failure: "AO3 refused.")
        #expect(currentFailure)
        #expect(screen.submitError == "AO3 refused.")
        #expect(screen.phase == .loaded)
        #expect(screen.rowIDs == [4])
        #expect(screen.staging.pendingCount(for: [item(4)]) == 1)
    }

    @Test func aStaleItemsLoadDoesNotReplaceTheGenerationNowOnScreen() {
        var screen = ItemsScreen()
        screen.boundGeneration = 4
        screen.sessionGeneration = 4
        screen.isLoggedIn = true
        screen.phase = .loaded
        screen.rowIDs = [1]
        screen.loadGeneration = 3

        let fetches = screen.task(sessionGeneration: 5, isLoggedIn: true, tab: .approved)
        #expect(fetches)
        #expect(screen.rowIDs.isEmpty)
        let staleLoad = screen.applyLoad(capturedLoad: 3, capturedSession: 4, rows: [1])
        #expect(!staleLoad)
        #expect(screen.rowIDs.isEmpty)
        #expect(screen.phase == .loading)
        let currentLoad = screen.applyLoad(
            capturedLoad: screen.loadGeneration,
            capturedSession: 5,
            rows: [7]
        )
        #expect(currentLoad)
        #expect(screen.rowIDs == [7])
        #expect(screen.phase == .loaded)
    }
}
