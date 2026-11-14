import Foundation
import Testing
@testable import Kudos

@MainActor
struct AppRouterTests {
    @Test func mainTabsFollowTheWritingTabRule() {
        #expect(AppTab.mainTabs == [.home, .library, .browse])
        #expect(AppTab.mainTabs(showsWriting: false) == [.home, .library, .browse])
        #expect(AppTab.mainTabs(showsWriting: true) == [.home, .library, .writing, .browse])
        #expect(!AppTab.mainTabs(showsWriting: false).contains(.account))
        #expect(!AppTab.mainTabs(showsWriting: true).contains(.account))
    }

    @Test func legacyAccountRoutesMapToTheirNewHomes() {
        #expect(LegacyAccountRoute.dashboard.destination == .account(.dashboard))
        #expect(LegacyAccountRoute.inbox.destination == .account(.inbox))
        #expect(LegacyAccountRoute.preferences.destination == .account(.preferences))
        #expect(LegacyAccountRoute.settings.destination == .account(.settings))
        #expect(LegacyAccountRoute.works.destination == .writing(.works))
        #expect(LegacyAccountRoute.drafts.destination == .writing(.drafts))
        #expect(LegacyAccountRoute.series.destination == .writing(.series))
        #expect(LegacyAccountRoute.collections.destination == .writing(.collectionsAndChallenges))
        #expect(LegacyAccountRoute.markedForLater.destination == .library(.markedForLater))
        #expect(LegacyAccountRoute.bookmarks.destination == .library(.bookmarks))
        #expect(LegacyAccountRoute.subscriptions.destination == .library(.subscriptions))
        #expect(LegacyAccountRoute.history.destination == .library(.history))
    }

    @Test func legacyMoreOnAO3RouteOpensTheDirectory() {
        #expect(LegacyAccountRoute.moreOnAO3.destination == .account(.moreOnAO3))
    }

    @Test func restoredAccountSelectionMovesToHomeAndPresentsAccount() {
        let restored = AppRouter.restoredSelection(from: AppTab.account.rawValue)
        #expect(restored == .init(tab: .home, presentsAccount: true))

        let router = AppRouter()
        router.restoreSelection(from: AppTab.account.rawValue)
        #expect(router.selection == .home)
        #expect(router.isPresentingAccount)
    }

    @Test func legacyRouteUpdatesTheOwningTabState() {
        let router = AppRouter()
        router.openLegacyAccountRoute(.drafts)
        #expect(router.selection == .home)
        #expect(router.consumePendingWritingRoute() == .drafts)

        router.evaluateWritingTab(isSignedIn: true, draftCount: 1)
        router.openLegacyAccountRoute(.drafts)
        #expect(router.selection == .writing)
        #expect(router.consumePendingWritingRoute() == .drafts)

        router.openLegacyAccountRoute(.history)
        #expect(router.selection == .library)
        #expect(router.consumePendingLibraryAO3Route() == .history)

        router.openLegacyAccountRoute(.inbox)
        #expect(router.selection == .home)
        #expect(router.isPresentingAccount)
        #expect(router.consumePendingAccountRoute() == .inbox)
    }

    // MARK: - T-513 Writing tab rule

    @Test func writingTabRuleSignedOut() {
        let rule = WritingTabRule(
            isSignedIn: false,
            workCount: 4,
            seriesCount: 2,
            draftCount: 1,
            hasLocalDrafts: true,
            lastKnownWrites: true,
            alreadyShownThisRun: false
        )
        #expect(rule.showsWritingTab == false)
    }

    @Test func writingTabRuleSignedInWithNothing() {
        let rule = WritingTabRule(
            isSignedIn: true,
            workCount: 0,
            seriesCount: 0,
            draftCount: 0,
            hasLocalDrafts: false,
            lastKnownWrites: true,
            alreadyShownThisRun: false
        )
        #expect(rule.showsWritingTab == false)
    }

    @Test func writingTabRuleWithWork() {
        let rule = WritingTabRule(
            isSignedIn: true,
            workCount: 1,
            seriesCount: 0,
            draftCount: 0,
            hasLocalDrafts: false,
            lastKnownWrites: false,
            alreadyShownThisRun: false
        )
        #expect(rule.showsWritingTab == true)
    }

    @Test func writingTabRuleWithSeries() {
        let rule = WritingTabRule(
            isSignedIn: true,
            workCount: 0,
            seriesCount: 1,
            draftCount: 0,
            hasLocalDrafts: false,
            lastKnownWrites: false,
            alreadyShownThisRun: false
        )
        #expect(rule.showsWritingTab == true)
    }

    @Test func writingTabRuleWithAO3Draft() {
        let rule = WritingTabRule(
            isSignedIn: true,
            workCount: 0,
            seriesCount: 0,
            draftCount: 1,
            hasLocalDrafts: false,
            lastKnownWrites: false,
            alreadyShownThisRun: false
        )
        #expect(rule.showsWritingTab == true)
    }

    @Test func writingTabRuleWithOnlyLocalDraft() {
        let rule = WritingTabRule(
            isSignedIn: true,
            workCount: 0,
            seriesCount: 0,
            draftCount: 0,
            hasLocalDrafts: true,
            lastKnownWrites: false,
            alreadyShownThisRun: false
        )
        #expect(rule.showsWritingTab == true)
    }

    @Test func writingTabRuleOfflineUsesLastKnownAnswer() {
        let offlineWriter = WritingTabRule(
            isSignedIn: true,
            workCount: nil,
            seriesCount: nil,
            draftCount: nil,
            hasLocalDrafts: false,
            lastKnownWrites: true,
            alreadyShownThisRun: false
        )
        #expect(offlineWriter.showsWritingTab == true)

        let offlineReader = WritingTabRule(
            isSignedIn: true,
            workCount: nil,
            seriesCount: nil,
            draftCount: nil,
            hasLocalDrafts: false,
            lastKnownWrites: false,
            alreadyShownThisRun: false
        )
        #expect(offlineReader.showsWritingTab == false)
    }

    @Test func writingTabRuleNeverRemovedWhileOpen() {
        let rule = WritingTabRule(
            isSignedIn: true,
            workCount: 0,
            seriesCount: 0,
            draftCount: 0,
            hasLocalDrafts: false,
            lastKnownWrites: false,
            alreadyShownThisRun: true
        )
        #expect(rule.showsWritingTab == true)

        let suiteName = "AppRouterTests.neverRemoved.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WritingTabStateStore(defaults: defaults)
        let router = AppRouter(writingStateStore: store)
        #expect(router.mainTabs == [.home, .library, .browse])

        router.evaluateWritingTab(isSignedIn: true, username: "saltwindow", workCount: 1)
        #expect(router.showsWritingTab == true)
        #expect(router.mainTabs == [.home, .library, .writing, .browse])
        #expect(store.lastKnownWrites(for: "saltwindow") == true)

        // Deleting the last work/draft while open keeps the tab for this run,
        // while updating the stored answer to false for the next launch.
        router.evaluateWritingTab(
            isSignedIn: true,
            username: "saltwindow",
            workCount: 0,
            seriesCount: 0,
            draftCount: 0,
            hasLocalDrafts: false
        )
        #expect(router.showsWritingTab == true)
        #expect(router.mainTabs == [.home, .library, .writing, .browse])
        #expect(store.lastKnownWrites(for: "saltwindow") == false)

        // Next launch offline uses the updated stored answer (false).
        let nextLaunchRouter = AppRouter(writingStateStore: store)
        nextLaunchRouter.evaluateWritingTab(isSignedIn: true, username: "saltwindow")
        #expect(nextLaunchRouter.showsWritingTab == false)
        #expect(nextLaunchRouter.mainTabs == [.home, .library, .browse])
    }

    @Test func restoredWritingSelectionFallsBackToHomeWithoutLosingRouteWhenHidden() {
        let hiddenRestored = AppRouter.restoredSelection(from: AppTab.writing.rawValue, showsWriting: false)
        #expect(hiddenRestored == .init(tab: .home, presentsAccount: false))

        let visibleRestored = AppRouter.restoredSelection(from: AppTab.writing.rawValue, showsWriting: true)
        #expect(visibleRestored == .init(tab: .writing, presentsAccount: false))

        let router = AppRouter()
        router.pendingWritingRoute = .drafts
        router.restoreSelection(from: AppTab.writing.rawValue)
        #expect(router.selection == .home)
        #expect(router.pendingWritingRoute == .drafts)

        // Once the account answers as a writer, the restored route lands on Writing
        // with its pending destination intact.
        router.evaluateWritingTab(isSignedIn: true, username: "saltwindow", workCount: 6)
        #expect(router.selection == .writing)
        #expect(router.consumePendingWritingRoute() == .drafts)
    }

    @Test func startWritingRowShowsOnlyWhileWritingTabIsHiddenAndOpensEditor() {
        let suiteName = "AppRouterTests.startWriting.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WritingTabStateStore(defaults: defaults)
        let router = AppRouter(writingStateStore: store)
        router.evaluateWritingTab(isSignedIn: true, username: "newreader", workCount: 0)
        #expect(router.showsWritingTab == false)
        #expect(AccountView.showsStartWritingRow(showsWritingTab: router.showsWritingTab) == true)
        #expect(AccountView.startWritingRoute(showsWritingTab: router.showsWritingTab) == .startWriting)

        // Saving the first draft from the editor reveals the Writing tab and hides Start Writing.
        router.noteDraftSaved(username: "newreader")
        #expect(router.showsWritingTab == true)
        #expect(router.mainTabs == [.home, .library, .writing, .browse])
        #expect(AccountView.showsStartWritingRow(showsWritingTab: router.showsWritingTab) == false)
        #expect(AccountView.startWritingRoute(showsWritingTab: router.showsWritingTab) == nil)
        #expect(store.lastKnownWrites(for: "newreader") == true)
    }

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

    @Test func openingAURLFromAccountWaitsForAccountDismissal() throws {
        let router = AppRouter()
        let url = try #require(URL(string: "https://archiveofourown.org/users/someone"))
        router.showAccount()

        router.open(url)

        #expect(router.isPresentingAccount == false)
        #expect(router.isPresentingWebBrowser == false)
        #expect(router.pendingURL == nil)

        router.accountDidDismiss()

        #expect(router.isPresentingWebBrowser)
        #expect(router.pendingURL == url)
    }

    @Test func authorNavigationTargetsTheAccountSheetWhileItIsPresented() {
        let router = AppRouter()
        #expect(router.authorNavigationTarget == .home)

        router.showAccount()
        #expect(router.authorNavigationTarget == .account)

        router.isPresentingAccount = false
        router.selection = .writing
        #expect(router.authorNavigationTarget == .writing)
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
        // The subject of this test is the native-tag gate, not the sheet.
        #expect(router.pendingTagWorks == nil)
        #expect(router.selection == .home)
        // A non-AO3 host must not reach the cookie-bearing in-app sheet at all.
        #expect(router.pendingURL == nil)
        #expect(router.isPresentingWebBrowser == false)
    }

    @Test func httpAO3TagLinkIsNotTreatedAsTrusted() {
        let router = AppRouter()
        router.openAO3Link(URL(string: "http://archiveofourown.org/tags/Fluff/works")!)
        #expect(router.pendingTagWorks == nil)
        #expect(router.pendingURL == nil)
        #expect(router.isPresentingWebBrowser == false)
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
