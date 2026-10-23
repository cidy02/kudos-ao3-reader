import Foundation
import Testing
@testable import Kudos

/// A kept comments page is labelled after any failed read, not only offline
/// (A74, 2026-10-22: after a timeout the old page showed as if it were today's).
@MainActor
struct CommentsKeptCopyNoticeTests {
    @MainActor private final class Loader {
        var failure: Error?
        func load(_ number: Int) throws -> AO3CommentsPage {
            if let failure { throw failure }
            return AO3CommentsPage(
                comments: [AO3Comment(id: number, author: "Root", isGuest: false)],
                currentPage: number, totalPages: 2
            )
        }
    }

    private func makeModel(_ loader: Loader) -> (CommentsModel, AO3AuthService) {
        let model = CommentsModel(
            workID: 95_003,
            workContext: AO3CommentsWorkContext(title: "Fixture", authors: ["Creator"]),
            initialFocusesChapter: false,
            initialComposes: false,
            pageLoader: { _, _, number, _ in try loader.load(number) },
            chapterLoader: { _, _ in [] },
            pageCache: CommentsPageCache()
        )
        let auth = AO3AuthService(
            vault: MemoryAO3SessionVault(),
            validator: InboxTestSessionValidator(),
            loginPerformer: DynamicInboxTestLoginPerformer(),
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )
        return (model, auth)
    }

    private func notice(after failure: URLError.Code) async -> String? {
        let loader = Loader()
        let (model, auth) = makeModel(loader)
        await model.loadInitial(auth: auth)
        #expect(model.keptCopyNotice == nil, "AO3's own page carries no notice")
        loader.failure = URLError(failure)
        await model.loadPage(1, auth: auth, forceRefresh: true)
        #expect(model.phase == .loaded, "the kept copy is still shown")
        return model.keptCopyNotice
    }

    @Test func aTimeoutSaysAO3CouldNotBeReached() async {
        let notice = await notice(after: .timedOut)
        #expect(notice?.hasPrefix("AO3 couldn't be reached. These comments are from ") == true)
    }

    @Test func noConnectionSaysOffline() async {
        let notice = await notice(after: .notConnectedToInternet)
        #expect(notice?.hasPrefix("You're offline. These comments are from ") == true)
    }

    /// Cellular data off for Kudos is offline, as on every other screen (`UserFacingError`).
    @Test func cellularDataOffIsOfflineToo() async {
        for code: URLError.Code in [.dataNotAllowed, .internationalRoamingOff] {
            let loader = Loader()
            let (model, auth) = makeModel(loader)
            await model.loadInitial(auth: auth)
            loader.failure = URLError(code)
            await model.loadPage(1, auth: auth, forceRefresh: true)
            #expect(model.keptCopyNotice?.hasPrefix("You're offline. These comments are from ") == true, "\(code)")
            #expect(model.isOffline, "Reply and the composer are dimmed: \(code)")
        }
    }

    @Test func aColdFailureWithCellularDataOffSaysOffline() {
        for code: URLError.Code in [.notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff] {
            #expect(CommentsModel.message(for: URLError(code))
                == "You're offline. Comments will load when you're back online.", "\(code)")
        }
    }

    @Test func aLostConnectionOrHostSaysAO3CouldNotBeReached() async {
        for code: URLError.Code in [.networkConnectionLost, .cannotFindHost] {
            let notice = await notice(after: code)
            #expect(notice?.hasPrefix("AO3 couldn't be reached. These comments are from ") == true, "\(code)")
        }
    }

    /// A page served from this session's cache is AO3's recent answer: the notice
    /// belongs to the kept copy it replaces, not to the screen.
    @Test func aFreshCachedPageAfterAKeptOneHasNoNotice() async {
        let loader = Loader()
        let (model, auth) = makeModel(loader)
        await model.loadInitial(auth: auth)
        await model.loadPage(2, auth: auth)
        loader.failure = URLError(.timedOut)
        await model.loadPage(1, auth: auth, forceRefresh: true)
        #expect(model.keptCopyNotice != nil, "page 1 is the kept copy")
        await model.loadPage(2, auth: auth)
        #expect(model.currentPageNumber == 2, "page 2 came from the cache, not the failing loader")
        #expect(model.keptCopyNotice == nil)
    }
}
