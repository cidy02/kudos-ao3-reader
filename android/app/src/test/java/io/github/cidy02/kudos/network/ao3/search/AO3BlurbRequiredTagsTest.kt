package io.github.cidy02.kudos.network.ao3.search

import io.github.cidy02.kudos.ui.components.statusChips
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins how a work blurb's warnings and categories are read.
 *
 * AO3's `ul.required-tags` row is a **summary of icons**, not a list: one symbol
 * per facet, and its single `<span class="text">` holds every value comma-joined.
 * Reading it as a list therefore yields exactly one element no matter how many
 * values apply — which showed as "1 Warning Applies" on a work warned for three
 * things, and "N/A" on a work that is both F/F and M/M.
 *
 * The markup below is the real element structure, copied from live
 * `/tags/Harry Potter - J. K. Rowling/works` on 2026-08-07.
 */
class AO3BlurbRequiredTagsTest {
    private val parser = AO3SearchParser()

    private fun page(
        requiredWarnings: String,
        requiredCategory: String,
        tagList: String
    ): String = """
        <!DOCTYPE html><html><body>
        <ol class="work index group">
        <li id="work_12345" class="work blurb group">
          <h4 class="heading"><a href="/works/12345">A Work</a>
            <a rel="author" href="/users/someone/pseuds/someone">someone</a></h4>
          <h5 class="fandoms heading"><a class="tag" href="/tags/X/works">X</a></h5>
          <ul class="required-tags">
        <li><a class="help symbol question modal" href="/help/symbols_key"><span class="rating-mature rating"
        title="Mature"><span class="text">Mature</span></span></a></li>
        <li><a class="help symbol question modal" href="/help/symbols_key"><span class="warning-yes warnings"
        title="$requiredWarnings"><span class="text">$requiredWarnings</span></span></a></li>
        <li><a class="help symbol question modal" href="/help/symbols_key"><span class="category-multi category"
        title="$requiredCategory"><span class="text">$requiredCategory</span></span></a></li>
        <li><a class="help symbol question modal" href="/help/symbols_key"><span class="complete-no iswip"
        title="Work in Progress"><span class="text">Work in Progress</span></span></a></li>
        </ul>
          <p class="datetime">07 Aug 2026</p>
          <ul class="tags commas">$tagList</ul>
        </li>
        </ol>
        </body></html>
    """.trimIndent()

    private fun parse(html: String) = parser.parseSearchPage(html, page = 1).works.first()

    /** The reported bug: three warnings apply, and the icon says so in one string. */
    @Test
    fun threeWarningsCountAsThree() {
        val work = parse(
            page(
                requiredWarnings = "Graphic Depictions Of Violence, Rape/Non-Con, Underage Sex",
                requiredCategory = "M/M",
                tagList = """
                    <li class='warnings'><strong><a class="tag" href="/tags/a/works">Graphic Depictions Of Violence</a></strong></li>
                    <li class='warnings'><strong><a class="tag" href="/tags/b/works">Rape/Non-Con</a></strong></li>
                    <li class='warnings'><strong><a class="tag" href="/tags/c/works">Underage Sex</a></strong></li>
                """.trimIndent()
            )
        )
        assertEquals(3, work.warnings.size)
        // "Rape/Non-Con" must survive intact — the slash is not a separator.
        assertTrue(work.warnings.contains("Rape/Non-Con"))
        // The user-visible symptom: this chip read "1 Warning Applies".
        val chips = statusChips(work.rating, work.categories, work.warnings, work.isComplete)
        assertTrue(chips.any { it.text == "3 Warnings Apply" })
    }

    /**
     * The same defect on the other facet. Categories are *not* repeated in
     * `ul.tags`, so the comma-joined icon label is their only source.
     */
    @Test
    fun aMultiCategoryWorkKeepsBothCategories() {
        val work = parse(
            page(
                requiredWarnings = "No Archive Warnings Apply",
                requiredCategory = "F/F, M/M",
                tagList = """<li class='warnings'><strong><a class="tag" href="/tags/d/works">No Archive Warnings Apply</a></strong></li>"""
            )
        )
        assertEquals(listOf("F/F", "M/M"), work.categories)
        // Both resolve to a colour, so the card draws two tinted chips. Before the
        // fix "F/F, M/M" matched nothing and the card said "N/A".
        assertTrue(work.categories.all { AO3StatusTintLookup(it) != null })
    }

    /** The sentinels are single values and must not be split into fragments. */
    @Test
    fun theUndisclosedSentinelStaysOneValue() {
        val work = parse(
            page(
                requiredWarnings = "Creator Chose Not To Use Archive Warnings",
                requiredCategory = "Gen",
                tagList = """<li class='warnings'><strong><a class="tag" href="/tags/e/works">Creator Chose Not To Use Archive Warnings</a></strong></li>"""
            )
        )
        assertEquals(listOf("Creator Chose Not To Use Archive Warnings"), work.warnings)
        val chips = statusChips(work.rating, work.categories, work.warnings, work.isComplete)
        assertTrue(chips.any { it.text == "Not Disclosed" })
    }

    /** Markup without the `ul.tags` repeat still has to produce the real count. */
    @Test
    fun theIconLabelIsTheFallbackWhenTheTagListOmitsWarnings() {
        val work = parse(
            page(
                requiredWarnings = "Major Character Death, Underage Sex",
                requiredCategory = "F/M",
                tagList = """<li class='freeforms'><a class="tag" href="/tags/Angst/works">Angst</a></li>"""
            )
        )
        assertEquals(listOf("Major Character Death", "Underage Sex"), work.warnings)
        val chips = statusChips(work.rating, work.categories, work.warnings, work.isComplete)
        assertTrue(chips.any { it.text == "2 Warnings Apply" })
    }

    @Test
    fun splittingIgnoresAnEmptyLabel() {
        assertTrue(splitRequiredTag(null).isEmpty())
        assertTrue(splitRequiredTag("").isEmpty())
        assertTrue(splitRequiredTag("   ").isEmpty())
    }
}

private fun AO3StatusTintLookup(category: String) =
    io.github.cidy02.kudos.ui.components.AO3StatusTint.category(category)
