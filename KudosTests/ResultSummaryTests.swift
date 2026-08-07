import Foundation
import Testing
@testable import Kudos

/// Pins AO3's result-count heading, the source of the hero card's total.
///
/// Every string below was copied from a live page on 2026-08-06 — the exact text
/// content of the heading element, not a tidied version — because the whole risk
/// here is that a tidied fixture hides what the real markup does.
struct ResultSummaryTests {
    @Test func aTagListReportsItsTotalAndItsTag() throws {
        // /tags/Naruto/works
        let summary = try #require(
            AO3Client.parseResultSummary("1 - 20 of 142,322 Works in Naruto (Anime & Manga)")
        )
        // 142,322, *not* 1 or 20: the total is the number attached to "Works", and
        // anchoring on the noun rather than on "the first number in the string" is
        // the entire reason the leading range can't be mistaken for it.
        #expect(summary.total == 142_322)
        #expect(summary.scope == "in Naruto (Anime & Manga)")
        // The heading names the subject with a preposition; the card uses it as a
        // title, where "in Naruto" would read oddly.
        #expect(summary.subject == "Naruto (Anime & Manga)")
        #expect(summary.range == 1 ... 20)
    }

    @Test func aUserListReportsItsTotalAndItsAuthor() throws {
        // /users/astolat/works
        let summary = try #require(AO3Client.parseResultSummary("1 - 20 of 535 Works by astolat"))
        #expect(summary.total == 535)
        #expect(summary.scope == "by astolat")
        #expect(summary.subject == "astolat")
        #expect(summary.range == 1 ... 20)
    }

    @Test func aSearchReportsItsTotalWithNoScope() throws {
        // /works/search — the heading is just a count, so the card says "found".
        let summary = try #require(AO3Client.parseResultSummary("92,495 Found"))
        #expect(summary.total == 92495)
        #expect(summary.scope == nil)
        #expect(summary.subject == nil)
        // No range at all on a search heading, so the card shows the count alone.
        #expect(summary.range == nil)
    }

    @Test func theSearchHelpLinkIsNotMistakenForAScope() throws {
        // The real heading is `92,495 Found <a class="help symbol question">…</a>`,
        // and its *text* — what SwiftSoup hands us — is "92,495 Found  ?". Taking
        // "everything after the noun" would make the scope "?" and the card would
        // read "92,495 works ?". Measured verbatim.
        let summary = try #require(AO3Client.parseResultSummary("92,495 Found  ?"))
        #expect(summary.total == 92495)
        #expect(summary.scope == nil)
    }

    @Test func headingsWithNoCountAreNotSummaries() {
        // A zero-result search renders only "Search Results" — AO3 omits the count
        // heading entirely, so nil here is the normal path, not a parse failure.
        #expect(AO3Client.parseResultSummary("Search Results") == nil)
        #expect(AO3Client.parseResultSummary("Works List") == nil)
        #expect(AO3Client.parseResultSummary("Navigation and Actions") == nil)
        #expect(AO3Client.parseResultSummary("") == nil)
    }

    @Test func aSingleResultKeepsItsCount() throws {
        let summary = try #require(AO3Client.parseResultSummary("1 - 1 of 1 Work in Some Tiny Tag"))
        #expect(summary.total == 1)
        #expect(summary.scope == "in Some Tiny Tag")
        #expect(summary.range == 1 ... 1)
    }

    @Test func aHeadingWithoutARangeStillParses() throws {
        // Not observed live, but the range is pagination chrome and AO3 has dropped
        // it before on single-page lists. The total must not depend on it.
        let summary = try #require(AO3Client.parseResultSummary("7 Works in Tiny Fandom"))
        #expect(summary.total == 7)
        #expect(summary.scope == "in Tiny Fandom")
        // No range in the heading means none on the card — never a guessed one.
        #expect(summary.range == nil)
    }

    @Test func lineBreaksInTheHeadingAreCollapsed() throws {
        // AO3's tag heading is spread over three source lines with the tag inside an
        // `<a>`, so the text arrives with newlines and runs of spaces in it.
        let summary = try #require(
            AO3Client.parseResultSummary("\n   1 - 20 of 142,322 Works in\n   Naruto (Anime & Manga)\n")
        )
        #expect(summary.total == 142_322)
        #expect(summary.scope == "in Naruto (Anime & Manga)")
        #expect(summary.range == 1 ... 20)
    }

    @Test func anUnfamiliarQualifierIsDroppedRatherThanShown() throws {
        // Better to show "12 works" than to render AO3 markup we don't understand
        // into a sentence that reads as nonsense.
        let summary = try #require(AO3Client.parseResultSummary("12 Works somewhere unexpected"))
        #expect(summary.total == 12)
        #expect(summary.scope == nil)
    }

    @Test func aCountWithNoSeparatorsParses() throws {
        #expect(AO3Client.parseResultSummary("842 Found")?.total == 842)
    }

    @Test func aLaterPagesRangeIsReadNotAssumedToStartAtOne() throws {
        // Page 50 of a big tag. The range is the only place AO3 says which works
        // this page holds, and it is what the card's right-hand figure shows.
        let summary = try #require(
            AO3Client.parseResultSummary("981 - 1,000 of 142,322 Works in Naruto (Anime & Manga)")
        )
        #expect(summary.range == 981 ... 1000)
        #expect(summary.total == 142_322)
    }

    @Test func aThousandsSeparatorInsideTheRangeIsParsed() throws {
        #expect(AO3Client.parseResultSummary("1,001 - 1,020 of 5,000 Works in X")?.range == 1001 ... 1020)
    }

    @Test func numbersElsewhereInTheHeadingAreNotReadAsARange() throws {
        // The range regex is anchored to the end of the text preceding the total,
        // so only a "<a> - <b> of" sitting immediately before the count can match.
        // A fandom name full of numbers must not produce one.
        let summary = try #require(AO3Client.parseResultSummary("12 Works in 5 - 10 Years Later"))
        #expect(summary.total == 12)
        #expect(summary.range == nil)
        #expect(summary.subject == "5 - 10 Years Later")
    }

    @Test func aFilteredTagListSaysWorksFoundIn() throws {
        // Verbatim from /tags/Naruto (Anime *a* Manga)/works with a query applied.
        // The moment `work_search[query]` is set, AO3 changes the wording from
        // "Works in <tag>" to "Works **found** in <tag>". Browse sends a query for
        // every excluded warning and category, so on that screen this is the normal
        // heading, not an edge case — and without handling it the card silently
        // loses its title exactly when a filter is active.
        let summary = try #require(
            AO3Client.parseResultSummary("1 - 20 of 88,698 Works found in Naruto (Anime & Manga)")
        )
        #expect(summary.total == 88698)
        #expect(summary.subject == "Naruto (Anime & Manga)")
        #expect(summary.scope == "in Naruto (Anime & Manga)")
        #expect(summary.range == 1 ... 20)
    }

    // MARK: Completing a search heading from what the screen already knows

    @Test func aFandomScreenNamesItselfWhenTheSearchHeadingDoesNot() throws {
        // What the screenshot showed: FandomWorksView runs a /works/search, whose
        // heading is a bare "142,327 Found" — so the card had a count and nothing
        // else. The screen *is* that fandom's works list, so it supplies both.
        let bare = try #require(AO3Client.parseResultSummary("142,327 Found  ?"))
        #expect(bare.subject == nil)
        #expect(bare.range == nil)

        let completed = bare.completing(subject: "Naruto (Anime & Manga)", page: 1, onPageCount: 20)
        #expect(completed.total == 142_327)
        #expect(completed.subject == "Naruto (Anime & Manga)")
        #expect(completed.scope == "in Naruto (Anime & Manga)")
        #expect(completed.range == 1 ... 20)
    }

    @Test func whatAO3ActuallySaidAlwaysWins() throws {
        // A tag heading already names its tag and range. Completing must never
        // overwrite either — the screen's own idea of its title can be a display
        // string ("Naruto") where AO3's is canonical ("Naruto (Anime & Manga)").
        let stated = try #require(
            AO3Client.parseResultSummary("41 - 60 of 142,322 Works in Naruto (Anime & Manga)")
        )
        let completed = stated.completing(subject: "Something Else", page: 99, onPageCount: 3)
        #expect(completed.subject == "Naruto (Anime & Manga)")
        #expect(completed.range == 41 ... 60)
    }

    @Test func aDerivedRangeFollowsThePageYouAreOn() throws {
        let bare = try #require(AO3Client.parseResultSummary("142,327 Found"))
        #expect(bare.completing(subject: nil, page: 1, onPageCount: 20).range == 1 ... 20)
        #expect(bare.completing(subject: nil, page: 2, onPageCount: 20).range == 21 ... 40)
        #expect(bare.completing(subject: nil, page: 50, onPageCount: 20).range == 981 ... 1000)
    }

    @Test func aShortLastPageEndsWhereItActuallyEnds() throws {
        // 3 works came back, so the range is 3 long — this is why the count of works
        // on the page is passed in rather than assuming a full page.
        let bare = try #require(AO3Client.parseResultSummary("43 Found"))
        #expect(bare.completing(subject: nil, page: 3, onPageCount: 3).range == 41 ... 43)
    }

    @Test func anEmptyPageDerivesNoRange() throws {
        // Zero works on screen is not "1–0".
        let bare = try #require(AO3Client.parseResultSummary("0 Found"))
        #expect(bare.completing(subject: nil, page: 1, onPageCount: 0).range == nil)
    }

    @Test func aDerivedRangeNeverRunsPastTheTotal() throws {
        // Belt and braces: if AO3's total and its paging ever disagree, the card
        // must not claim to be showing works 21-40 of a 25-work list.
        let bare = try #require(AO3Client.parseResultSummary("25 Found"))
        let completed = bare.completing(subject: nil, page: 2, onPageCount: 20)
        #expect(completed.range == 21 ... 25)
    }

    @Test func searchKeepsNoSubjectBecauseItCanHaveMany() throws {
        // The Search tab passes nil: several fandoms and tags can be active at once,
        // so there is no single thing the results are "in".
        let bare = try #require(AO3Client.parseResultSummary("92,495 Found"))
        let completed = bare.completing(subject: nil, page: 1, onPageCount: 20)
        #expect(completed.subject == nil)
        #expect(completed.scope == nil)
        #expect(completed.range == 1 ... 20)
    }
}
