import Foundation
import Testing
@testable import Kudos

/// Covers the pure, offline pieces of the native AO3 write actions: CSRF / pseud /
/// error parsing and form-body encoding. The actual POST endpoints can only be
/// confirmed against a live signed-in AO3 session.
struct AO3WriteActionsTests {
    @Test func parsesCSRFTokenFromMetaTag() {
        let html = """
        <html><head>
        <meta name="csrf-param" content="authenticity_token">
        <meta name="csrf-token" content="aB3/dEf+gh==">
        </head><body></body></html>
        """
        #expect(AO3Client.parseCSRFToken(from: html) == "aB3/dEf+gh==")
    }

    @Test func missingCSRFTokenReturnsNil() {
        #expect(AO3Client.parseCSRFToken(from: "<html><head></head></html>") == nil)
    }

    @Test func parsesSelectedDefaultPseud() {
        let html = """
        <form>
          <select name="comment[pseud_id]" id="comment_pseud_id">
            <option value="11">altpseud</option>
            <option value="22" selected="selected">mainpseud</option>
          </select>
        </form>
        """
        #expect(AO3Client.parseDefaultPseudID(from: html) == "22")
    }

    @Test func pseudFallsBackToFirstOptionWhenNoneSelected() {
        let html = """
        <select name="comment[pseud_id]">
          <option value="7">only</option>
        </select>
        """
        #expect(AO3Client.parseDefaultPseudID(from: html) == "7")
    }

    @Test func readsRenderedErrorList() {
        let html = """
        <html><body>
        <ul class="errorlist"><li>Comment content can't be blank</li></ul>
        </body></html>
        """
        #expect(AO3Client.writeErrorMessage(in: html) == "Comment content can't be blank")
        #expect(AO3Client.writeErrorMessage(in: "<html><body>fine</body></html>") == nil)
    }

    @Test func detectsSubscribedStateAndUnsubscribePath() {
        let subscribed = """
        <form action="/users/me/subscriptions/789" method="post">
          <input type="hidden" name="_method" value="delete">
          <input type="submit" value="Unsubscribe">
        </form>
        """
        let result = AO3Client.parseSubscription(from: subscribed)
        #expect(result.isSubscribed)
        #expect(result.unsubscribePath == "/users/me/subscriptions/789")
    }

    @Test func detectsNotSubscribedState() {
        let notSubscribed = """
        <form action="/users/me/subscriptions" method="post">
          <input type="hidden" name="subscription[subscribable_type]" value="Work">
          <input type="submit" value="Subscribe">
        </form>
        """
        let result = AO3Client.parseSubscription(from: notSubscribed)
        #expect(!result.isSubscribed)
        #expect(result.unsubscribePath == nil)
    }

    /// The state that makes `unsubscribe` and `toggleSubscribe` diverge, and the
    /// reason the Following list must not use the toggle.
    ///
    /// `toggleSubscribe` reads the work page and SUBSCRIBES whenever it finds no
    /// subscription — correct for a toggle on a work page. A row in the Following
    /// list can be stale (unsubscribed on the website, or from another device), and
    /// then the work page looks exactly like the fixture below: a plain subscribe
    /// form, no `_method=delete`. Routed through the toggle, a tap labelled
    /// "Unfollow" would subscribe the user instead. `unsubscribe` guards on this
    /// same parse and returns without writing.
    @Test("A stale Following row parses as not-subscribed, which is why Unfollow cannot use the toggle")
    func notSubscribedIsTheStaleRowState() {
        let staleRow = """
        <form action="/users/me/subscriptions" method="post">
          <input type="hidden" name="subscription[subscribable_type]" value="Work">
          <input type="submit" value="Subscribe">
        </form>
        """
        let state = AO3Client.parseSubscription(from: staleRow)
        #expect(!state.isSubscribed, "the toggle would branch to subscribe here")
        #expect(state.unsubscribePath == nil, "and there is no delete path to POST")
    }

    /// The failure these two states are easy to confuse, and the reason
    /// `unsubscribe` checks the session before reporting "not following".
    ///
    /// A work page is PUBLIC, so an expired session does not redirect to
    /// /users/login and `authenticatedPageHTML` does not throw — it returns a
    /// valid logged-out page. That page has no subscription controls at all, so
    /// `parseSubscription` reports not-subscribed exactly as it does for a work
    /// the user genuinely does not follow. Without the session check the list
    /// would quietly drop a row the user still follows.
    @Test("A logged-out work page is not evidence that the user stopped following")
    func loggedOutPageIsNotProofOfNoSubscription() {
        let loggedOut = """
        <html><body class="works-show">
          <div id="header"><a href="/users/login">Log In</a></div>
          <div id="main"><h2 class="title">A Quiet Harbour</h2></div>
        </body></html>
        """
        let signedIn = """
        <html><body class="works-show logged-in">
          <div id="header"><a href="/users/logout">Log Out</a></div>
          <form action="/users/me/subscriptions" method="post">
            <input type="submit" value="Subscribe">
          </form>
        </body></html>
        """

        // Indistinguishable on the subscription parse alone.
        #expect(!AO3Client.parseSubscription(from: loggedOut).isSubscribed)
        #expect(!AO3Client.parseSubscription(from: signedIn).isSubscribed)

        // Separable on the session, which is what `unsubscribe` branches on.
        #expect(!LiveAO3SessionValidator.isLoggedIn(html: loggedOut))
        #expect(LiveAO3SessionValidator.isLoggedIn(html: signedIn))
    }

    @Test func parsesCollectionsIndex() throws {
        let html = """
        <html><body>
        <ul class="collection index group">
          <li class="collection picture blurb group">
            <div class="header module group">
              <h4 class="heading">
                <a href="/collections/cool_fics">Cool Fics</a> by
                <a class="owner" href="/users/OwnerAccount">Owner Pseud</a> and
                <a class="mod" href="/users/ModAccount">Mod Pseud</a>
              </h4>
            </div>
          </li>
          <li class="collection blurb group">
            <h4 class="heading"><a href="/collections/another_one/profile">Another One</a></h4>
          </li>
        </ul>
        </body></html>
        """
        let collections = try AO3Client.parseCollections(from: html)
        #expect(collections.count == 2)
        #expect(collections.map(\.name) == ["cool_fics", "another_one"])
        #expect(collections.first?.title == "Cool Fics")
        #expect(collections.first?.maintainerNames == ["Owner Pseud", "Mod Pseud"])
        #expect(collections.first?.maintainerIdentities.map(\.route?.username)
            == ["OwnerAccount", "ModAccount"])
    }

    @Test func parsesBookmarkPseudField() {
        let html = """
        <select name="bookmark[pseud_id]">
          <option value="5" selected>me</option>
        </select>
        """
        #expect(AO3Client.parseDefaultPseudID(from: html, field: "bookmark[pseud_id]") == "5")
    }

    @MainActor
    @Test func formEncodingPercentEncodesKeysAndValues() {
        let body = AO3AuthService.formEncoded([
            ("authenticity_token", "a b/c"),
            ("kudo[commentable_id]", "12345"),
            ("kudo[commentable_type]", "Work"),
        ])
        let string = String(decoding: body, as: UTF8.self)
        #expect(string ==
            "authenticity_token=a%20b%2Fc&kudo%5Bcommentable_id%5D=12345&kudo%5Bcommentable_type%5D=Work")
    }
}
