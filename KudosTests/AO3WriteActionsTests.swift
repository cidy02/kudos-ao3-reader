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
