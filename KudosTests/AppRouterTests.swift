import Foundation
import Testing
@testable import Kudos

@MainActor
struct AppRouterTests {
    @Test func unmungesTagSlug() {
        #expect(AppRouter.unmungeTag("Kara%20Danvers*s*Lena%20Luthor") == "Kara Danvers/Lena Luthor")
        #expect(AppRouter.unmungeTag("Fluff") == "Fluff")
        #expect(AppRouter.unmungeTag("Tony*a*Pepper") == "Tony&Pepper")
    }

    @Test func tagLinkRoutesToNativeTagWorks() {
        let router = AppRouter()
        router.openAO3Link(URL(string: "https://archiveofourown.org/tags/Fluff/works")!)
        #expect(router.pendingTagWorks?.title == "Fluff")
        #expect(router.selection == .browse)
        #expect(router.pendingURL == nil)
    }

    /// A lookalike host that merely *contains* "archiveofourown.org" must not
    /// qualify for the native tag-works path — that would hand the attacker's
    /// own host straight to `AO3Client.worksPage(at:)`. Same host gate as
    /// `open(_:)` (`isAO3URL`), not a looser inline check.
    @Test func lookalikeTagHostFallsBackToOpenInsteadOfNativeTagWorks() {
        let router = AppRouter()
        let lookalike = URL(string: "https://archiveofourown.org.evil.example/tags/Fluff/works")!
        router.openAO3Link(lookalike)
        #expect(router.pendingTagWorks == nil, "Lookalike host was routed to native tag works")
    }

    @Test func userLinkRoutesToNativeAuthorWithoutChangingTabs() {
        let router = AppRouter()
        router.openAO3Link(URL(string: "https://archiveofourown.org/users/someone")!)

        #expect(router.pendingAuthorProfile == AO3AuthorRoute(username: "someone"))
        #expect(router.authorProfileNavigationEpoch == 1)
        #expect(router.pendingTagWorks == nil)
        #expect(router.pendingURL == nil)
        #expect(router.selection == .home)
    }

    @Test func openAuthorProfileBumpsEpochEvenForSameRoute() throws {
        let router = AppRouter()
        let route = try #require(AO3AuthorRoute(username: "someone"))

        router.openAuthorProfile(route)
        #expect(router.authorProfileNavigationEpoch == 1)
        #expect(router.pendingAuthorProfile == route)
        #expect(router.cardNavigationSuppressed)
        #expect(router.shouldSuppressCardNavigation)

        // Same route again — Optional equality would skip onChange; epoch must advance.
        router.openAuthorProfile(route)
        #expect(router.authorProfileNavigationEpoch == 2)
        #expect(router.pendingAuthorProfile == route)

        #expect(router.consumePendingAuthorProfile() == route)
        #expect(router.pendingAuthorProfile == nil)
        #expect(router.consumePendingAuthorProfile() == nil)
    }

    @Test func percentEncodedPseudLinkRoutesToExactNativePseud() throws {
        let router = AppRouter()
        let url = try #require(URL(
            string: "https://archiveofourown.org/users/Avery_Archive/pseuds/Avery%20Writes"
        ))

        router.openAO3Link(url)

        let route = try #require(router.pendingAuthorProfile)
        #expect(route.username == "Avery_Archive")
        #expect(route.pseud == "Avery Writes")
    }

    @Test func nonAuthorUserPageFallsBackToWebWithoutChangingTabs() {
        let router = AppRouter()
        let url = URL(string: "https://archiveofourown.org/users/someone/readings")!
        router.openAO3Link(url)

        #expect(router.pendingAuthorProfile == nil)
        #expect(router.pendingURL == url)
        // Website sheet is root-hosted — do not steal focus into Browse.
        #expect(router.isPresentingWebBrowser)
        #expect(router.selection == .home)
    }

    @Test func openWebsitePresentsSheetWithoutRequiringPendingURL() {
        let router = AppRouter()
        router.openWebsite()
        #expect(router.isPresentingWebBrowser)
        #expect(router.pendingURL == nil)
        #expect(router.selection == .home)
    }

    // MARK: - Deferred author push (T-139 / UI-8)
    //
    // The queue replaces the per-view `isOpening…` booleans the 350ms sleeps used to
    // reset, so these cover the states those guards used to hold: one push per tap,
    // no double-push, no latch, no stale route surviving into a later presentation.

    @Test func queuedAuthorRouteOpensOnceWhenTheDismissCompletes() throws {
        let router = AppRouter()
        let route = try #require(AO3AuthorRoute(username: "someone"))

        #expect(router.requestAuthorProfileAfterDismiss(route))
        // Queuing must not push on its own — the modal is still dismissing.
        #expect(router.pendingAuthorProfile == nil)
        #expect(router.authorProfileNavigationEpoch == 0)

        router.openPendingAuthorProfileAfterDismiss()
        #expect(router.pendingAuthorProfile == route)
        #expect(router.authorProfileNavigationEpoch == 1)

        // Every presenter in a nested chain drains, so a second drain must no-op
        // rather than push a duplicate.
        router.openPendingAuthorProfileAfterDismiss()
        #expect(router.authorProfileNavigationEpoch == 1)
    }

    @Test func secondTapMidDismissIsRefusedRatherThanOverwritingTheFirst() throws {
        let router = AppRouter()
        let first = try #require(AO3AuthorRoute(username: "first"))
        let second = try #require(AO3AuthorRoute(username: "second"))

        #expect(router.requestAuthorProfileAfterDismiss(first))
        // First tap wins: the caller is told it did not queue, and must leave its
        // own presentation alone instead of dismissing a second time.
        #expect(router.requestAuthorProfileAfterDismiss(second) == false)

        router.openPendingAuthorProfileAfterDismiss()
        #expect(router.pendingAuthorProfile == first)
        #expect(router.authorProfileNavigationEpoch == 1)
    }

    @Test func drainingClearsTheQueueSoLaterTapsStillWork() throws {
        let router = AppRouter()
        let first = try #require(AO3AuthorRoute(username: "first"))
        let second = try #require(AO3AuthorRoute(username: "second"))

        #expect(router.requestAuthorProfileAfterDismiss(first))
        router.openPendingAuthorProfileAfterDismiss()
        _ = router.consumePendingAuthorProfile()

        // The guard must not latch — a later, unrelated byline tap has to queue.
        #expect(router.requestAuthorProfileAfterDismiss(second))
        router.openPendingAuthorProfileAfterDismiss()
        #expect(router.pendingAuthorProfile == second)
        #expect(router.authorProfileNavigationEpoch == 2)
    }

    @Test func cancellingDropsAStrandedRouteInsteadOfPushingItLater() throws {
        let router = AppRouter()
        let route = try #require(AO3AuthorRoute(username: "someone"))

        #expect(router.requestAuthorProfileAfterDismiss(route))
        // A Comments presentation opening clears whatever was left behind, so simply
        // closing that presentation cannot push a profile the user never asked for.
        router.cancelPendingAuthorProfileAfterDismiss()

        router.openPendingAuthorProfileAfterDismiss()
        #expect(router.pendingAuthorProfile == nil)
        #expect(router.authorProfileNavigationEpoch == 0)
        // Cancelling also releases the guard.
        #expect(router.requestAuthorProfileAfterDismiss(route))
    }

    @Test func lookalikeHostIsNotRoutedAsANativeTagPage() {
        let router = AppRouter()
        let bait = URL(string: "https://archiveofourown.org.evil.com/tags/Fluff/works")!
        router.openAO3Link(bait)
        #expect(router.pendingTagWorks == nil)
        #expect(router.pendingURL == bait)
        #expect(router.isPresentingWebBrowser)
        #expect(router.selection == .home)
    }

    @Test func httpAO3TagLinkIsNotTreatedAsTrusted() {
        let router = AppRouter()
        let url = URL(string: "http://archiveofourown.org/tags/Fluff/works")!
        router.openAO3Link(url)
        #expect(router.pendingTagWorks == nil)
        #expect(router.pendingURL == url)
    }

    @Test func malformedAndNonAO3UserURLsAreNotAuthorRoutes() {
        #expect(AppRouter.authorRoute(
            for: URL(string: "https://archiveofourown.org/users/login")!
        ) == nil)
        #expect(AppRouter.authorRoute(
            for: URL(string: "https://example.com/users/someone")!
        ) == nil)
    }

    /// M19: `open()` is the unguarded sink `openAO3Link` falls through to.
    /// Rejects must leave both `pendingURL` and the sheet flag untouched;
    /// a normal https AO3 URL must set both, or the rejects could pass
    /// against a no-op `open()`.
    @Test func openRejectsNonHTTPSchemes() throws {
        let router = AppRouter()

        let javascript = try #require(URL(string: "javascript:alert(1)"))
        #expect(javascript.scheme?.lowercased() == "javascript")
        router.open(javascript)
        #expect(router.pendingURL == nil)
        #expect(router.isPresentingWebBrowser == false)

        let data = try #require(URL(string: "data:text/html,hello"))
        #expect(data.scheme?.lowercased() == "data")
        router.open(data)
        #expect(router.pendingURL == nil)
        #expect(router.isPresentingWebBrowser == false)

        let file = try #require(URL(string: "file:///tmp/index.html"))
        #expect(file.scheme?.lowercased() == "file")
        router.open(file)
        #expect(router.pendingURL == nil)
        #expect(router.isPresentingWebBrowser == false)

        let https = try #require(URL(string: "https://archiveofourown.org/works/1"))
        #expect(https.scheme?.lowercased() == "https")
        router.open(https)
        #expect(router.pendingURL == https)
        #expect(router.isPresentingWebBrowser == true)
    }
}
