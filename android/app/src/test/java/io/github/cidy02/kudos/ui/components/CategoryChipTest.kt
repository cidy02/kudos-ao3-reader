package io.github.cidy02.kudos.ui.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.People
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Pins how a work's categories collapse on a card — mirrors iOS `CategoryChipTests`.
 *
 * AO3's rule, verified live on 2026-08-07 against
 * `/tags/Harry Potter - J. K. Rowling/works`: the blurb draws `category-multi` for
 * *any* work with more than one category, not only for works carrying the literal
 * "Multi" tag. Real rows from that page: `F/M, F/F`, `Gen, M/M`, `F/F, M/M`,
 * `F/M, Gen, M/M, Multi` — all `category-multi`. So "Multi" is both a real
 * category and AO3's name for "several of them".
 */
class CategoryChipTest {
    private fun categoryChips(categories: List<String>, expanded: Boolean) =
        statusChips(rating = "", categories = categories, warnings = emptyList(),
                    isComplete = null, expanded = expanded)
            .filter { it.icon == Icons.Outlined.People }
            .map { it.text }

    @Test
    fun severalCategoriesFoldToMultiOnACollapsedCard() {
        assertEquals(listOf("Multi"), categoryChips(listOf("F/F", "M/M"), expanded = false))
        assertEquals(listOf("Multi"), categoryChips(listOf("Gen", "M/M"), expanded = false))
        assertEquals(
            listOf("Multi"),
            categoryChips(listOf("F/M", "Gen", "M/M", "Multi"), expanded = false)
        )
    }

    @Test
    fun expandingSpellsThemOut() {
        assertEquals(listOf("F/F", "M/M"), categoryChips(listOf("F/F", "M/M"), expanded = true))
    }

    /** One category is already glanceable — including the literal "Multi" tag. */
    @Test
    fun oneCategoryIsUntouched() {
        for (expanded in listOf(true, false)) {
            assertEquals(listOf("M/M"), categoryChips(listOf("M/M"), expanded))
            assertEquals(listOf("Multi"), categoryChips(listOf("Multi"), expanded))
        }
    }

    @Test
    fun noCategoryStillSaysSomething() {
        assertEquals(listOf("N/A"), categoryChips(emptyList(), expanded = false))
        assertEquals(listOf("N/A"), categoryChips(listOf("No category"), expanded = false))
    }

    /** Unrecognized strings are filtered before the count, so one real category
     *  plus junk is not mistaken for a multi-category work. */
    @Test
    fun junkDoesNotCountTowardsMulti() {
        assertEquals(listOf("M/M"), categoryChips(listOf("M/M", "Not A Category"), expanded = false))
    }
}
