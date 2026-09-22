import Foundation
import Testing
@testable import Kudos

/// The account list's load task is a SwiftUI `.task`, so these tests cover the
/// decision the task applies, not the view lifecycle. Nothing here signs in.
struct AO3AccountWorksSessionReloadTests {
    private struct Screen {
        var boundGeneration: Int?
        var phaseIsIdle = true
        var unsubscribePaths: [Int: String] = [:]

        /// Mirrors the task body: clear on a new generation, then load only
        /// when signed in and idle. Returns whether that run would fetch.
        mutating func task(sessionGeneration: Int, isLoggedIn: Bool) -> Bool {
            if AO3AccountWorksSessionReload.shouldClear(
                boundGeneration: boundGeneration,
                sessionGeneration: sessionGeneration
            ) {
                boundGeneration = sessionGeneration
                phaseIsIdle = true
                unsubscribePaths = AO3AccountWorksSessionReload.cleared.unsubscribePaths
            }
            return isLoggedIn && phaseIsIdle
        }
    }

    @Test func theLoadIDChangesForANewGenerationAndForTheSignedInFlag() {
        let signedIn = AO3AccountWorksLoadID(sessionGeneration: 4, isLoggedIn: true)
        // verifySession bumps the generation and stays signed in.
        #expect(signedIn != AO3AccountWorksLoadID(sessionGeneration: 5, isLoggedIn: true))
        // finishAccepting sets signed-in without bumping again.
        #expect(signedIn != AO3AccountWorksLoadID(sessionGeneration: 4, isLoggedIn: false))
        #expect(signedIn == AO3AccountWorksLoadID(sessionGeneration: 4, isLoggedIn: true))
    }

    @Test func aClearedAccountKeepsNoRowsOrUnsubscribePath() {
        let cleared = AO3AccountWorksSessionReload.cleared
        #expect(cleared.works.isEmpty)
        #expect(cleared.currentPage == 1)
        #expect(cleared.totalPages == 1)
        #expect(cleared.readingEntries.isEmpty)
        #expect(cleared.bookmarkDetails.isEmpty)
        #expect(cleared.unsubscribePaths.isEmpty)
        #expect(cleared.enrichedSubscriptionSummaries.isEmpty)
        #expect(cleared.markedForLaterSeenThisVisit.isEmpty)
        #expect(cleared.lastSyncedAt == nil)
        #expect(cleared.confirmClearHistory == false)
        #expect(cleared.historyWriteError == nil)
        #expect(cleared.historyWriteInFlight == false)
        #expect(cleared.subscriptionWriteError == nil)
        #expect(cleared.subscriptionWriteInFlight == false)
    }

    /// Account A is on screen. Sign-out and the next login each bump the
    /// generation before status is signed-in, so those runs must drop A's
    /// unsubscribe path and must not fetch. The run that lands signed-in
    /// under the login's generation is the one that fetches, and it must
    /// not still be holding A's path. Coming back with that same generation
    /// must not wipe the page the fetch just stored.
    @Test func anAccountSwitchDropsThePreviousUnsubscribePathBeforeTheNextLoad() {
        var screen = Screen()
        screen.boundGeneration = 4
        screen.phaseIsIdle = false
        screen.unsubscribePaths = [4: "/users/alice/subscriptions/9"]

        let signedOut = screen.task(sessionGeneration: 5, isLoggedIn: false)
        #expect(signedOut == false)
        #expect(screen.unsubscribePaths.isEmpty)

        // accept() bumps again while status is still .signingIn.
        let stillSigningIn = screen.task(sessionGeneration: 6, isLoggedIn: false)
        #expect(stillSigningIn == false)
        #expect(screen.unsubscribePaths.isEmpty)

        let fetches = screen.task(sessionGeneration: 6, isLoggedIn: true)
        #expect(fetches)
        #expect(screen.unsubscribePaths.isEmpty)

        screen.phaseIsIdle = false
        screen.unsubscribePaths = [8: "/users/bob/subscriptions/3"]

        let reappear = screen.task(sessionGeneration: 6, isLoggedIn: true)
        #expect(reappear == false)
        #expect(screen.unsubscribePaths == [8: "/users/bob/subscriptions/3"])
    }

    /// `verifySession` bumps the generation without signing out. The rows
    /// were loaded under the old cookies, so this run fetches again and does
    /// not keep the previous path.
    @Test func aGenerationBumpWhileSignedInClearsBeforeFetching() {
        var screen = Screen()
        screen.boundGeneration = 6
        screen.phaseIsIdle = false
        screen.unsubscribePaths = [8: "/users/bob/subscriptions/3"]

        let fetches = screen.task(sessionGeneration: 7, isLoggedIn: true)
        #expect(fetches)
        #expect(screen.unsubscribePaths.isEmpty)
        #expect(screen.phaseIsIdle)
    }
}
