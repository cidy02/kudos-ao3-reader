import Foundation
import Testing
@testable import Kudos

/// The "Posting As" pseud pipeline: parsing a form's authorized pseud options,
/// resolving the id a submit should carry (stored preference vs. the form's own
/// default), and the per-account persistence of the preference.
struct AO3PostingPseudTests {
    private let formHTML = """
    <html><body>
    <form action="/works/1/comments" method="post">
      <select name="comment[pseud_id]">
        <option value="11">MainPseud</option>
        <option value="22" selected="selected">SecondPseud</option>
        <option value="33">Third Pseud</option>
      </select>
    </form>
    </body></html>
    """

    private let unselectedFormHTML = """
    <html><body>
    <select name="comment[pseud_id]">
      <option value="11">MainPseud</option>
      <option value="22">SecondPseud</option>
    </select>
    </body></html>
    """

    @Test func parsesOptionsWithSelectedDefault() {
        let options = AO3Client.parsePostingPseudOptions(from: formHTML)
        #expect(options.map(\.id) == ["11", "22", "33"])
        #expect(options.map(\.name) == ["MainPseud", "SecondPseud", "Third Pseud"])
        #expect(options.map(\.isDefault) == [false, true, false])
    }

    @Test func firstOptionIsDefaultWhenNoneSelected() {
        let options = AO3Client.parsePostingPseudOptions(from: unselectedFormHTML)
        #expect(options.map(\.isDefault) == [true, false])
    }

    @Test func missingSelectYieldsNoOptions() {
        let options = AO3Client.parsePostingPseudOptions(from: "<html><body><p>hi</p></body></html>")
        #expect(options.isEmpty)
    }

    @Test func preferredNameWinsCaseInsensitively() {
        let id = AO3AuthService.resolvePostingPseudID(in: formHTML, preferredName: "third pseud")
        #expect(id == "33")
    }

    @Test func unmatchedPreferenceFallsBackToFormDefault() {
        // A pseud renamed/deleted on AO3 no longer appears in the form — the
        // stale preference must never invent an id.
        let id = AO3AuthService.resolvePostingPseudID(in: formHTML, preferredName: "GonePseud")
        #expect(id == "22")
    }

    @Test func noPreferenceUsesFormDefault() {
        #expect(AO3AuthService.resolvePostingPseudID(in: formHTML, preferredName: nil) == "22")
        #expect(
            AO3AuthService.resolvePostingPseudID(in: unselectedFormHTML, preferredName: nil) == "11"
        )
    }

    @Test func storePersistsPerAccountAndNormalizesUsernames() throws {
        let suiteName = "AO3PostingPseudTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAO3PostingPseudStore(defaults: defaults)

        store.setPseudName("ArtPseud", for: "Tester")
        #expect(store.pseudName(for: "tester") == "ArtPseud")
        #expect(store.pseudName(for: "  TESTER  ") == "ArtPseud")
        #expect(store.pseudName(for: "otheruser") == nil)

        store.setPseudName("OtherPseud", for: "otheruser")
        #expect(store.pseudName(for: "tester") == "ArtPseud")

        // nil and whitespace-only both clear the preference.
        store.setPseudName(nil, for: "tester")
        #expect(store.pseudName(for: "tester") == nil)
        store.setPseudName("  ", for: "otheruser")
        #expect(store.pseudName(for: "otheruser") == nil)
    }
}
