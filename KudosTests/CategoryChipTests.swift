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

/// The same collapsed/expanded split for Archive Warnings.
///
/// AO3's own blurb legend never names the warnings either — its icon means "some
/// warning applies" and the specifics live in the title attribute — so a count is
/// the right collapsed form. Expanding names them, which is what the work page
/// does.
struct WarningChipTests {
    private func chipTexts(_ warnings: [String], expanded: Bool) -> [String] {
        WorkListStatsRow(warnings: warnings, isExpanded: expanded).warningChipTexts
    }

    private let three = ["Graphic Depictions Of Violence", "Rape/Non-Con", "Underage Sex"]

    @Test func collapsedCountsThem() {
        #expect(chipTexts(three, expanded: false) == ["3 Warnings Apply"])
        #expect(chipTexts(["Major Character Death"], expanded: false) == ["1 Warning Applies"])
    }

    @Test func expandingNamesThem() {
        #expect(chipTexts(three, expanded: true) == three)
    }

    /// The two sentinels are single states, not folded lists — expanding must not
    /// turn "Not Disclosed" into a chip named after AO3's sentinel tag, and must
    /// not leave the slot empty (`realWarnings` filters both to nothing).
    @Test func theSentinelStatesReadTheSameEitherWay() {
        for expanded in [true, false] {
            #expect(chipTexts([], expanded: expanded) == ["No Warnings"])
            #expect(chipTexts(["No Archive Warnings Apply"], expanded: expanded) == ["No Warnings"])
            #expect(chipTexts(["Creator Chose Not To Use Archive Warnings"], expanded: expanded)
                == ["Not Disclosed"])
        }
    }

    /// A real warning alongside the "chose not to use" sentinel: AO3 treats that
    /// as undisclosed, and it stays one chip even expanded rather than silently
    /// revealing a warning the creator declined to state.
    @Test func undisclosedWinsOverAStrayWarning() {
        let mixed = ["Creator Chose Not To Use Archive Warnings", "Underage Sex"]
        #expect(chipTexts(mixed, expanded: true) == ["Not Disclosed"])
    }
}
