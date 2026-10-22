import Foundation
import Testing
@testable import Kudos

/// A kept comments page is labelled after any failed read, not only offline
/// (A74, 2026-10-22: after a timeout the old page showed as if it were today's).
@MainActor
struct CommentsKeptCopyNoticeTests {
    @MainActor private final class Loader {
        var failure: Error?
        let page = AO3CommentsPage(comments: [AO3Comment(id: 1, author: "Root", isGuest: false)])
        func load() throws -> AO3CommentsPage {
            if let failure { throw failure }
            return page
        }
    }

    private func notice(after failure: URLError.Code) async -> String? {
        let loader = Loader()
        let model = CommentsModel(
            workID: 95_003,
            workContext: AO3CommentsWorkContext(title: "Fixture", authors: ["Creator"]),
            initialFocusesChapter: false,
            initialComposes: false,
            pageLoader: { _, _, _, _ in try loader.load() },
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
}
