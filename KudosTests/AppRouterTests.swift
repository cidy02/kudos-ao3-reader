import Foundation
import Testing
@testable import Kudos

@MainActor
struct AppRouterTests {
    @Test func mainTabsFollowTheWritingTabRule() {
        let router = AppRouter()
        #expect(router.mainTabs == [.home, .library, .browse])
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
        let unseenReader = WritingTabRule(
            isSignedIn: true,
            workCount: 0,
            seriesCount: 0,
            draftCount: 0,
            hasLocalDrafts: false,
            lastKnownWrites: false,
            alreadyShownThisRun: false
        )
        #expect(unseenReader.showsWritingTab == false)

        let formerWriterWithAllZeroCounts = WritingTabRule(
            isSignedIn: true,
            workCount: 0,
            seriesCount: 0,
            draftCount: 0,
            hasLocalDrafts: false,
            lastKnownWrites: true,
            alreadyShownThisRun: false
        )
        #expect(formerWriterWithAllZeroCounts.showsWritingTab == false)
    }

    @Test func writingTabRulePartialZeroCountsKeepLastKnownAnswer() throws {
        // Only a subset of counts is 0 (e.g. Works = 0 while Drafts and Series
        // are still nil/unloaded): must fall back to `lastKnownWrites` rather
        // than hiding or overwriting stored `true` with `false`.
        let partialWriter = WritingTabRule(
            isSignedIn: true,
            workCount: 0,
            seriesCount: nil,
            draftCount: nil,
            hasLocalDrafts: false,
            lastKnownWrites: true,
            alreadyShownThisRun: false
        )
        #expect(partialWriter.showsWritingTab == true)

        let twoZeroCountsStillMissingDrafts = WritingTabRule(
            isSignedIn: true,
            workCount: 0,
            seriesCount: 0,
            draftCount: nil,
            hasLocalDrafts: false,
            lastKnownWrites: true,
            alreadyShownThisRun: false
        )
        #expect(twoZeroCountsStillMissingDrafts.showsWritingTab == true)

        let partialUnseenReader = WritingTabRule(
            isSignedIn: true,
            workCount: 0,
            seriesCount: nil,
            draftCount: nil,
            hasLocalDrafts: false,
            lastKnownWrites: false,
            alreadyShownThisRun: false
        )
        #expect(partialUnseenReader.showsWritingTab == false)

        let suiteName = "AppRouterTests.partialCounts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WritingTabStateStore(defaults: defaults)
        store.setLastKnownWrites(true, for: "draftonlywriter")

        let router = AppRouter(writingStateStore: store)
        router.evaluateWritingTab(
            isSignedIn: true,
            username: "draftonlywriter",
            workCount: 0,
            seriesCount: 0,
            draftCount: nil,
            hasLocalDrafts: false
        )
        #expect(router.showsWritingTab == true)
        #expect(store.lastKnownWrites(for: "draftonlywriter") == true)

        // Weak list-count lower bounds (0 without exact) and uncounted author headers
        // are unknown (`nil`), never zero.
        #expect(AO3AccountListCount(itemsOnPage: 0, totalPages: 2).knownCount == nil)
        #expect(AO3AccountListCount(itemsOnPage: 20, totalPages: 2).knownCount == 20)
        #expect(AO3AccountListCount(exact: 0).knownCount == 0)

        let route = try #require(AO3AuthorRoute(username: "draftonlywriter"))
        let uncountedHeader = AO3AuthorHeader(
            identity: AO3AuthorIdentity(route: route),
            pseuds: [],
            fandoms: [],
            subscriptionForm: nil,
            actions: [
                AO3AuthorWebAction(
                    label: "Works",
                    url: route.contentURL(.works),
                    kind: .works
                )
            ],
            recentWorks: [],
            recentSeries: []
        )
        let headerRouter = AppRouter(writingStateStore: store)
        headerRouter.evaluateWritingTab(
            from: uncountedHeader,
            route: route,
            username: "draftonlywriter",
            isSignedIn: true
        )
        #expect(headerRouter.showsWritingTab == true)
        #expect(store.lastKnownWrites(for: "draftonlywriter") == true)
    }

    @Test func headerWithARecentWorkButNoCountShowsWriting() throws {
        let suiteName = "AppRouterTests.recentWork.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WritingTabStateStore(defaults: defaults)
        let route = try #require(AO3AuthorRoute(username: "latestonly"))
        let recent = AO3WorkSummary(
            id: 1, title: "Latest", authors: [], authorIdentities: [], fandoms: [], rating: "",
            warnings: [], categories: [], isComplete: true, dateUpdated: "", tags: [], summary: "",
            language: "English", words: 1_000, chapters: "1/1", comments: 0, kudos: 1, bookmarks: 0,
            hits: 10, seriesTitle: nil, seriesURL: nil, seriesPosition: nil
        )
        func header(_ works: [AO3WorkSummary]) -> AO3AuthorHeader {
            AO3AuthorHeader(identity: AO3AuthorIdentity(route: route), pseuds: [], fandoms: [],
                            subscriptionForm: nil, actions: [], recentWorks: works, recentSeries: [])
        }
        // No count and nothing listed: unknown, so a first-seen account stays a reader.
        let reader = AppRouter(writingStateStore: store)
        reader.evaluateWritingTab(from: header([]), route: route, username: "latestonly", isSignedIn: true)
        #expect(reader.showsWritingTab == false)
        // No count but a work under "Your Latest": the account writes.
        let writer = AppRouter(writingStateStore: store)
        writer.evaluateWritingTab(from: header([recent]), route: route, username: "latestonly", isSignedIn: true)
        #expect(writer.showsWritingTab == true)
        #expect(store.lastKnownWrites(for: "latestonly") == true)
    }

    @Test func accountSwitchWithoutSignedOutStepReEvaluatesAndMovesSelectionOffWriting() {
        let suiteName = "AppRouterTests.accountSwitch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WritingTabStateStore(defaults: defaults)
        let router = AppRouter(writingStateStore: store)

        router.evaluateWritingTab(isSignedIn: true, username: "alice", workCount: 2)
        router.selection = .writing
        #expect(router.showsWritingTab == true)
        #expect(router.selection == .writing)

        // Switch directly to a reader account without an intermediate signed-out step.
        router.evaluateWritingTab(
            isSignedIn: true,
            username: "bob",
            workCount: 0,
            seriesCount: 0,
            draftCount: 0,
            hasLocalDrafts: false
        )
        #expect(router.showsWritingTab == false)
        #expect(router.selection == .home)
        #expect(router.mainTabs == [.home, .library, .browse])
        #expect(router.mainTabs.contains(router.selection))
        #expect(store.lastKnownWrites(for: "bob") == false)
        #expect(store.lastKnownWrites(for: "alice") == true)
    }

    @Test func localDraftsAreScopedToTheSignedInAccount() throws {
        let suiteName = "AppRouterTests.scopedLocalDrafts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WritingTextRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let recovery = WritingTextRecovery(directory: tempDir)
        let copyURL = recovery.fileURL(account: "Alice_Writer", target: "work:new", field: "content")
        try recovery.save(
            text: "<p>Alice's local draft</p>",
            original: "",
            to: copyURL
        )

        #expect(recovery.hasLocalDrafts(for: "alice_writer") == true)
        #expect(recovery.hasLocalDrafts(for: "bob_reader") == false)
        #expect(recovery.hasLocalDrafts(for: nil) == false)

        let store = WritingTabStateStore(defaults: defaults)
        let router = AppRouter(writingStateStore: store, recoveryStore: recovery)

        router.evaluateWritingTab(
            isSignedIn: true,
            username: "bob_reader",
            workCount: 0,
            seriesCount: 0,
            draftCount: 0
        )
        #expect(router.showsWritingTab == false)
        #expect(store.lastKnownWrites(for: "bob_reader") == false)

        router.evaluateWritingTab(
            isSignedIn: true,
            username: "alice_writer",
            workCount: 0,
            seriesCount: 0,
            draftCount: 0
        )
        #expect(router.showsWritingTab == true)
        #expect(store.lastKnownWrites(for: "alice_writer") == true)
    }

    @Test func previewingDoesNotMarkAccountAsWriting() async throws {
        let suiteName = "AppRouterTests.previewNoPersist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WritingTabStateStore(defaults: defaults)
        let router = AppRouter(writingStateStore: store)
        router.evaluateWritingTab(
            isSignedIn: true,
            username: "alice",
            workCount: 0,
            seriesCount: 0,
            draftCount: 0,
            hasLocalDrafts: false
        )
        #expect(router.showsWritingTab == false)
        #expect(store.lastKnownWrites(for: "alice") == false)

        let auth = AO3AuthService(
            vault: MemoryAO3SessionVault(),
            validator: InboxTestSessionValidator(),
            loginPerformer: DynamicInboxTestLoginPerformer(),
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )
        await auth.login(username: "alice", password: "pw")

        let config = AO3Client.makeAnonymousSessionConfiguration()
        config.protocolClasses = [PreviewOnlyStubURLProtocol.self]
        let client = AO3Client(
            session: URLSession(configuration: config),
            nextAllowedRequestAt: .distantPast,
            paceSleep: { _ in }
        )

        let workForm = AO3WorkForm(
            kind: .new,
            workID: nil,
            actionURL: URL(string: "https://archiveofourown.org/works")!,
            httpMethodOverride: nil,
            csrfToken: "w==",
            isDraft: true,
            isPosted: false
        )
        _ = try await auth.previewWork(workForm, using: client)
        #expect(router.showsWritingTab == false)
        #expect(store.lastKnownWrites(for: "alice") == false)

        let chapterForm = AO3ChapterForm(
            workID: 424242,
            chapterID: nil,
            actionURL: AO3Client.chaptersURL(workID: 424242),
            httpMethodOverride: nil,
            csrfToken: "c==",
            content: "<p>Chapter preview</p>"
        )
        _ = try await auth.previewChapter(chapterForm, using: client)
        #expect(router.showsWritingTab == false)
        #expect(store.lastKnownWrites(for: "alice") == false)
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
        // Signed-out users never see Start Writing even though the Writing tab is hidden.
        #expect(AccountView.showsStartWritingRow(isSignedIn: false, showsWritingTab: false) == false)
        #expect(AccountView.startWritingRoute(isSignedIn: false, showsWritingTab: false) == nil)

        let suiteName = "AppRouterTests.startWriting.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WritingTabStateStore(defaults: defaults)
        let router = AppRouter(writingStateStore: store)
        router.evaluateWritingTab(
            isSignedIn: true,
            username: "newreader",
            workCount: 0,
            seriesCount: 0,
            draftCount: 0,
            hasLocalDrafts: false
        )
        #expect(router.showsWritingTab == false)
        #expect(AccountView.showsStartWritingRow(isSignedIn: true, showsWritingTab: router.showsWritingTab) == true)
        #expect(
            AccountView.startWritingRoute(isSignedIn: true, showsWritingTab: router.showsWritingTab) == .startWriting
        )

        // Saving the first draft from the editor reveals the Writing tab and hides Start Writing.
        router.noteDraftSaved(username: "newreader")
        #expect(router.showsWritingTab == true)
        #expect(router.mainTabs == [.home, .library, .writing, .browse])
        #expect(AccountView.showsStartWritingRow(isSignedIn: true, showsWritingTab: router.showsWritingTab) == false)
        #expect(AccountView.startWritingRoute(isSignedIn: true, showsWritingTab: router.showsWritingTab) == nil)
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

    @Test func revealWritingTabForSessionDoesNotPersistToDefaults() {
        let suiteName = "AppRouterTests.demoSessionOnly.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WritingTabStateStore(defaults: defaults)
        let router = AppRouter(writingStateStore: store)
        router.evaluateWritingTab(
            isSignedIn: true,
            username: "saltwindow",
            workCount: 0,
            seriesCount: 0,
            draftCount: 0,
            hasLocalDrafts: false
        )
        #expect(router.showsWritingTab == false)
        #expect(store.lastKnownWrites(for: "saltwindow") == false)

        router.revealWritingTabForSession()
        #expect(router.showsWritingTab == true)
        #expect(store.lastKnownWrites(for: "saltwindow") == false)
    }
}

private final class PreviewOnlyStubURLProtocol: URLProtocol, @unchecked Sendable {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let body: String
        if url.path.contains("/chapters") {
            body = WritingPreviewParsingTests.chapterPreview
        } else {
            body = """
            <html><head><meta name="csrf-token" content="w=="></head><body><div id="main">
            <div id="previewpane"><div class="draft work">
              <div id="work-skin" class="wrapper"><div id="workskin">
                <div class="preface group"><h2 class="title heading">Tide</h2></div>
                <div id="chapters"><div class="userstuff"><p>It rained.</p></div></div>
              </div></div>
            </div>
            <form class="edit_work" id="edit_work_77" action="/works/77" method="post">
              <input type="hidden" name="_method" value="patch">
              <fieldset><ul class="actions">
                <li><input type="submit" name="save_button" value="Save As Draft"></li>
                <li><input type="submit" name="edit_button" value="Edit"></li>
                <li><input type="submit" name="post_button" value="Post"></li>
              </ul></fieldset>
            </form></div>
            </div></body></html>
            """
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
