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

    @Test func malformedAndNonAO3UserURLsAreNotAuthorRoutes() {
        #expect(AppRouter.authorRoute(
            for: URL(string: "https://archiveofourown.org/users/login")!
        ) == nil)
        #expect(AppRouter.authorRoute(
            for: URL(string: "https://example.com/users/someone")!
        ) == nil)
    }
}
