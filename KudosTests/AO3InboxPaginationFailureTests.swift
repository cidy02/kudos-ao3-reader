import Foundation
import Testing
@testable import Kudos

/// T91-RF8: a failed later-page request must not hide the already-loaded
/// page's items, and `retry()` must target the page that actually failed —
/// not whatever page is still on screen. Uses the same `Signal`-gated
/// `AO3InboxModel(pageLoader:)` harness as `AO3InboxAccountTransitionTests`.
@MainActor
struct AO3InboxPaginationFailureTests {
    private static func makeAuthService() -> AO3AuthService {
        AO3AuthService(
            vault: MemoryAO3SessionVault(),
            validator: InboxTestSessionValidator(),
            loginPerformer: DynamicInboxTestLoginPerformer(),
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )
    }

    /// One real, parseable item plus the heading's total — unlike a
    /// recognized-*empty* page, this keeps `model.items` non-empty after a
    /// successful load, which is what makes a *later* page's failure take the
    /// non-destructive `.paginationFailed` branch instead of `.failed` (that
    /// branch only exists to distinguish "content already on screen" from
    /// "nothing to preserve").
    private static func inboxHTML(total: Int) -> String {
        """
        <html><body>
        <h2 class="heading">My Inbox (\(total) comments, \(total) unread)</h2>
        <ol class="comment index group">
          <li class="unread comment group even" role="article" id="feedback_comment_9001">
            <h4 class="heading byline">
              <a href="/users/reader1/pseuds/ReaderOne">ReaderOne</a> on
              <a href="/works/123456/comments/9001">My Great Fic</a>
              <span class="posted datetime">3 days ago</span>
            </h4>
            <div class="icon"></div>
            <blockquote class="userstuff"><p>Nice!</p></blockquote>
          </li>
        </ol>
        </body></html>
        """
    }

    private static func page(_ html: String) -> AO3AuthorProfileFetcher.Page {
        AO3AuthorProfileFetcher.Page(html: html, isStale: false)
    }

    @Test func failedPage2RequestPreservesPage1ItemsAndReportsAPage2Error() async throws {
        let auth = Self.makeAuthService()
        await auth.login(username: "alice", password: "password")

        let model = AO3InboxModel(pageLoader: { url, _, _, _, _ in
            if url.query?.contains("page=2") == true {
                throw AO3Error.network("Connection lost.")
            }
            return Self.page(Self.inboxHTML(total: 5))
        })

        model.syncAuthenticationContext(auth: auth)
        let page1 = Task { await model.refresh(auth: auth) }
        await page1.value
        #expect(model.phase == .loaded)
        #expect(model.totalComments == 5)
        #expect(model.currentPage == 1)
        let page1Items = model.items

        model.goToPage(2, auth: auth)
        // `goToPage` launches an unstructured task; wait for the failure to land.
        let deadline = ContinuousClock.now + Duration.seconds(2)
        while model.phase == .loaded, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }

        guard case let .paginationFailed(requestedPage, message) = model.phase else {
            Issue.record("Expected .paginationFailed, got \(model.phase)")
            return
        }
        #expect(requestedPage == 2)
        #expect(message == "Connection lost.")
        // Page 1's items/currentPage/totals must still be exactly what they were —
        // the failed page 2 request must not blow away retained content.
        #expect(model.items.map(\.id) == page1Items.map(\.id))
        #expect(model.currentPage == 1)
        #expect(model.totalComments == 5)
    }

    @Test func retryAfterAFailedPage2RequestTargetsPage2NotPage1() async throws {
        let auth = Self.makeAuthService()
        await auth.login(username: "alice", password: "password")

        var requestedPages: [String] = []
        var failPage2 = true
        let model = AO3InboxModel(pageLoader: { url, _, _, _, _ in
            let query = url.query ?? ""
            requestedPages.append(query)
            if query.contains("page=2"), failPage2 {
                throw AO3Error.network("Connection lost.")
            }
            let total = query.contains("page=2") ? 20 : 5
            return Self.page(Self.inboxHTML(total: total))
        })

        model.syncAuthenticationContext(auth: auth)
        let page1 = Task { await model.refresh(auth: auth) }
        await page1.value

        model.goToPage(2, auth: auth)
        let failDeadline = ContinuousClock.now + Duration.seconds(2)
        while model.phase == .loaded, ContinuousClock.now < failDeadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        guard case .paginationFailed = model.phase else {
            Issue.record("Expected .paginationFailed before retrying, got \(model.phase)")
            return
        }

        failPage2 = false
        model.retry(auth: auth)
        let retryDeadline = ContinuousClock.now + Duration.seconds(2)
        while model.phase != .loaded, ContinuousClock.now < retryDeadline {
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(model.phase == .loaded)
        // Retry must have re-requested page 2 (not page 1, which is what
        // `currentPage` was still pinned to while the failure was showing).
        #expect(requestedPages.last?.contains("page=2") == true)
        #expect(model.currentPage == 2)
        #expect(model.totalComments == 20)
    }
}
