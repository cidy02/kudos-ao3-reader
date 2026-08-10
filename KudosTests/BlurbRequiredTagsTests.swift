import Foundation
import SwiftSoup
import Testing
@testable import Kudos

/// Pins how a work blurb's warnings and categories are read.
///
/// AO3's `ul.required-tags` row is a **summary of icons**, not a list: one symbol
/// per facet, and its single `<span class="text">` holds every value comma-joined.
/// Reading it as an array therefore yields exactly one element no matter how many
/// values apply — which showed up as "1 Warning Applies" on a work warned for
/// three things, and "N/A" on a work that is both F/F and M/M.
///
/// Every fixture below is the real element structure, copied from live
/// `/tags/Harry Potter - J. K. Rowling/works` markup on 2026-08-07. A tidied
/// fixture would hide the exact thing under test.
struct BlurbRequiredTagsTests {
    /// One blurb, with the two facets under test substituted in.
    private func blurb(requiredWarnings: String, requiredCategory: String, tagList: String) -> String {
        """
        <li id="work_12345" class="work blurb group">
          <h4 class="heading"><a href="/works/12345">A Work</a>
            <a rel="author" href="/users/someone/pseuds/someone">someone</a></h4>
          <h5 class="fandoms heading"><a class="tag" href="/tags/X/works">X</a></h5>
          <ul class="required-tags">
        <li><a class="help symbol question modal" href="/help/symbols_key"><span class="rating-mature rating" \
        title="Mature"><span class="text">Mature</span></span></a></li>
        <li><a class="help symbol question modal" href="/help/symbols_key"><span class="warning-yes warnings" \
        title="\(requiredWarnings)"><span class="text">\(requiredWarnings)</span></span></a></li>
        <li><a class="help symbol question modal" href="/help/symbols_key"><span class="category-multi category" \
        title="\(requiredCategory)"><span class="text">\(requiredCategory)</span></span></a></li>
        <li><a class="help symbol question modal" href="/help/symbols_key"><span class="complete-no iswip" \
        title="Work in Progress"><span class="text">Work in Progress</span></span></a></li>
        </ul>
          <p class="datetime">07 Aug 2026</p>
          <ul class="tags commas">\(tagList)</ul>
        </li>
        """
    }

    private func parse(_ html: String) throws -> AO3WorkSummary {
        let element = try #require(try SwiftSoup.parse(html).select("li.blurb").first())
        return try AO3Client.parseBlurb(element)
    }

    /// The reported bug. Three warnings apply; the icon says so in one string.
    @Test func threeWarningsCountAsThree() throws {
        let work = try parse(blurb(
            requiredWarnings: "Graphic Depictions Of Violence, Rape/Non-Con, Underage Sex",
            requiredCategory: "M/M",
            tagList: """
            <li class='warnings'><strong><a class="tag" href="/tags/Graphic%20Depictions%20Of%20Violence/works">\
            Graphic Depictions Of Violence</a></strong></li> \
            <li class='warnings'><strong><a class="tag" href="/tags/Rape*s*Non-Con/works">Rape/Non-Con</a></strong></li> \
            <li class='warnings'><strong><a class="tag" href="/tags/Underage%20Sex/works">Underage Sex</a></strong></li>
            """
        ))
        #expect(work.warnings.count == 3)
        #expect(WorkStat.realWarnings(work.warnings).count == 3)
        // The user-visible symptom: this read "1 Warning Applies".
        #expect(WorkWarningStatus(rawWarnings: work.warnings).text == "3 Warnings")
        // "Rape/Non-Con" must survive intact — the slash is not a separator.
        #expect(work.warnings.contains("Rape/Non-Con"))
    }

    /// The same defect on the other facet. Categories are *not* repeated in
    /// `ul.tags`, so the comma-joined icon label is their only source.
    @Test func aMultiCategoryWorkKeepsBothCategories() throws {
        let work = try parse(blurb(
            requiredWarnings: "No Archive Warnings Apply",
            requiredCategory: "F/F, M/M",
            tagList: """
            <li class='warnings'><strong><a class="tag" href="/tags/No%20Archive%20Warnings%20Apply/works">\
            No Archive Warnings Apply</a></strong></li>
            """
        ))
        #expect(work.categories == ["F/F", "M/M"])
        // Both are recognized, so the card shows two coloured chips. Before the
        // fix "F/F, M/M" matched no known category and the card said "N/A".
        #expect(work.categories.allSatisfy { WorkStat.categoryColor($0) != nil })
    }

    /// The sentinels are single values and must not be mangled by splitting;
    /// "Creator Chose Not To Use Archive Warnings" has no comma but is the state
    /// the warning chip keys off.
    @Test func theUndisclosedSentinelStaysOneValue() throws {
        let work = try parse(blurb(
            requiredWarnings: "Creator Chose Not To Use Archive Warnings",
            requiredCategory: "Gen",
            tagList: """
            <li class='warnings'><strong><a class="tag" href="/tags/Creator%20Chose%20Not%20To%20Use%20Archive%20\
            Warnings/works">Creator Chose Not To Use Archive Warnings</a></strong></li>
            """
        ))
        #expect(work.warnings == ["Creator Chose Not To Use Archive Warnings"])
        #expect(WorkWarningStatus(rawWarnings: work.warnings).text == "Not Disclosed")
        #expect(work.categories == ["Gen"])
    }

    /// Markup that drops the `ul.tags` repeat still has to produce the real count
    /// — the icon label is the fallback, split the same way.
    @Test func theIconLabelIsTheFallbackWhenTheTagListOmitsWarnings() throws {
        let work = try parse(blurb(
            requiredWarnings: "Major Character Death, Underage Sex",
            requiredCategory: "F/M",
            tagList: "<li class='freeforms'><a class=\"tag\" href=\"/tags/Angst/works\">Angst</a></li>"
        ))
        #expect(work.warnings == ["Major Character Death", "Underage Sex"])
        #expect(WorkWarningStatus(rawWarnings: work.warnings).text == "2 Warnings")
    }

    @Test func splittingIgnoresAnEmptyLabel() {
        #expect(AO3Client.splitRequiredTag(nil).isEmpty)
        #expect(AO3Client.splitRequiredTag("").isEmpty)
        #expect(AO3Client.splitRequiredTag("   ").isEmpty)
    }
}
