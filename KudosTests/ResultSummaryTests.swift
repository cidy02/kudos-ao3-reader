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
}
