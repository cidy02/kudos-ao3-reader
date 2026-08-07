package io.github.cidy02.kudos.ui.components

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The four states AO3 surfaces up front on a work. Every slot must always say
 * something — a blank chip reads as a layout gap rather than a real state, which is
 * the failure this pins.
 */
class WorkStatusChipsTest {
    private fun texts(
        rating: String = "Teen And Up Audiences",
        categories: List<String> = listOf("Gen"),
        warnings: List<String> = listOf("No Archive Warnings Apply"),
        isComplete: Boolean? = true
    ) = statusChips(rating, categories, warnings, isComplete).map { it.text }

    @Test
    fun everySlotAlwaysSaysSomething() {
        // The emptiest possible work still produces a chip per slot.
        val chips = statusChips(rating = "", categories = emptyList(), warnings = emptyList(), isComplete = null)
        assertTrue(chips.none { it.text.isBlank() })
        // No rating from AO3 means no rating chip; the other three always appear.
        assertEquals(3, chips.size)
    }

    @Test
    fun anUncategorizedWorkSaysSoRatherThanShowingNothing() {
        assertTrue(texts(categories = emptyList()).contains("N/A"))
        assertTrue(texts(categories = listOf("  ")).contains("N/A"))
    }

    @Test
    fun warningsAreCountedNotSpelledOut() {
        // AO3's own legend shows how many apply, not which — the full list still
        // reaches TalkBack through the accessibility label.
        val two = statusChips(
            rating = "Explicit",
            categories = listOf("M/M"),
            warnings = listOf("Graphic Depictions Of Violence", "Major Character Death"),
            isComplete = false
        )
        assertTrue(two.map { it.text }.contains("2 Warnings Apply"))
        val label = two.first { it.text == "2 Warnings Apply" }.accessibilityLabel
        assertTrue(label!!.contains("Graphic Depictions Of Violence"))
        assertTrue(label.contains("Major Character Death"))

        assertTrue(texts(warnings = listOf("Underage Sex")).contains("1 Warning Applies"))
    }

    @Test
    fun AO3sTwoWaysOfSayingNothingToFlagAreNotCountedAsWarnings() {
        assertTrue(texts(warnings = listOf("No Archive Warnings Apply")).contains("No Warnings"))
        assertTrue(texts(warnings = emptyList()).contains("No Warnings"))
        assertTrue(
            texts(warnings = listOf("Creator Chose Not To Use Archive Warnings"))
                .contains("Not Disclosed")
        )
    }

    @Test
    fun completionCoversAllThreeStates() {
        assertTrue(texts(isComplete = true).contains("Complete"))
        assertTrue(texts(isComplete = false).contains("WIP"))
        assertTrue(texts(isComplete = null).contains("Unknown"))
    }

    @Test
    fun aMultiCategoryWorkGetsAChipEach() {
        val chips = texts(categories = listOf("F/F", "M/M"))
        assertTrue(chips.contains("F/F"))
        assertTrue(chips.contains("M/M"))
    }
}
