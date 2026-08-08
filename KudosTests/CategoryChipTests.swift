import Testing
@testable import Kudos

/// Pins how a work's categories collapse on a card.
///
/// **AO3's rule, measured live on 2026-08-07** against
/// `/tags/Harry Potter - J. K. Rowling/works`: the blurb draws the CSS class
/// `category-multi` for *any* work with more than one category — not only for
/// works carrying the literal "Multi" tag. Real examples from that page:
///
///     work 89128281  category-multi  title="F/M, F/F"
///     work 90084031  category-multi  title="Gen, M/M"
///     work 89990336  category-multi  title="F/F, M/M"
///     work 89741776  category-multi  title="F/M, Gen, M/M, Multi"
///
/// so "Multi" is both a real category tag *and* AO3's name for "several of
/// them", which is the trap here. Cross-checked against the works' own pages:
/// 89990336's Category row is `["F/F", "M/M"]` and 89741776's is
/// `["F/M", "Gen", "M/M", "Multi"]` — AO3 spells them out where it has room and
/// folds them where it doesn't, which is exactly the collapsed/expanded split.
struct CategoryChipTests {
    private func chipTexts(_ categories: [String], expanded: Bool) -> [String] {
        WorkListStatsRow(categories: categories, isExpanded: expanded).categoryChipTexts
    }

    @Test func severalCategoriesFoldToMultiOnACollapsedCard() {
        #expect(chipTexts(["F/F", "M/M"], expanded: false) == ["Multi"])
        #expect(chipTexts(["Gen", "M/M"], expanded: false) == ["Multi"])
        #expect(chipTexts(["F/M", "Gen", "M/M", "Multi"], expanded: false) == ["Multi"])
    }

    @Test func expandingSpellsThemOut() {
        #expect(chipTexts(["F/F", "M/M"], expanded: true) == ["F/F", "M/M"])
        #expect(chipTexts(["F/M", "Gen", "M/M", "Multi"], expanded: true)
            == ["F/M", "Gen", "M/M", "Multi"])
    }

    /// A single category is already glanceable, so nothing changes either way —
    /// including the literal "Multi" tag, which is one category and stays one chip.
    @Test func oneCategoryIsUntouched() {
        for expanded in [true, false] {
            #expect(chipTexts(["M/M"], expanded: expanded) == ["M/M"])
            #expect(chipTexts(["Multi"], expanded: expanded) == ["Multi"])
        }
    }

    /// AO3's `category-none` blurbs. Still one chip rather than a blank slot.
    @Test func noCategoryStillSaysSomething() {
        #expect(chipTexts([], expanded: false) == ["N/A"])
        #expect(chipTexts(["No category"], expanded: false) == ["N/A"])
    }

    /// Unrecognized strings are filtered before the count is taken, so one real
    /// category plus junk is *not* mistaken for a multi-category work.
    @Test func junkDoesNotCountTowardsMulti() {
        #expect(chipTexts(["M/M", "Not A Category"], expanded: false) == ["M/M"])
    }
}
