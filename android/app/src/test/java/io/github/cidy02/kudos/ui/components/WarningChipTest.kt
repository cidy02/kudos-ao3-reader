package io.github.cidy02.kudos.ui.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.WarningAmber
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The collapsed/expanded split for Archive Warnings — mirrors iOS
 * `WarningChipTests`.
 *
 * AO3's blurb legend never names the warnings either: its icon means "some
 * warning applies" and the specifics live in the title attribute. So a count is
 * the right collapsed form, and expanding names them.
 */
class WarningChipTest {
    private val three = listOf(
        "Graphic Depictions Of Violence", "Rape/Non-Con", "Underage Sex"
    )

    private fun warningChips(warnings: List<String>, expanded: Boolean) =
        statusChips(rating = "", categories = emptyList(), warnings = warnings,
                    isComplete = null, expanded = expanded)
            .filter { it.icon == Icons.Outlined.WarningAmber || it.icon == Icons.Outlined.CheckCircle }
            .filter { it.text != "Complete" }
            .map { it.text }

    @Test
    fun collapsedCountsThem() {
        assertEquals(listOf("3 Warnings"), warningChips(three, expanded = false))
        assertEquals(
            listOf("1 Warning"),
            warningChips(listOf("Major Character Death"), expanded = false)
        )
    }

    @Test
    fun expandingNamesThem() {
        assertEquals(three, warningChips(three, expanded = true))
    }

    /** The sentinels are single states, not folded lists. */
    @Test
    fun theSentinelStatesReadTheSameEitherWay() {
        for (expanded in listOf(true, false)) {
            assertEquals(listOf("No Warnings"), warningChips(emptyList(), expanded))
            assertEquals(
                listOf("No Warnings"),
                warningChips(listOf("No Archive Warnings Apply"), expanded)
            )
            assertEquals(
                listOf("Not Disclosed"),
                warningChips(listOf("Creator Chose Not To Use Archive Warnings"), expanded)
            )
        }
    }

    /**
     * A real warning alongside the "chose not to use" sentinel. Android used to
     * report the *count* here because its `when` tested `real.isNotEmpty()` first,
     * where iOS's `WorkWarningStatus.init` checks the sentinel first and says
     * "Not Disclosed". The two now agree — and the app never reveals a warning the
     * creator declined to state.
     */
    @Test
    fun undisclosedWinsOverAStrayWarning() {
        val mixed = listOf("Creator Chose Not To Use Archive Warnings", "Underage Sex")
        for (expanded in listOf(true, false)) {
            assertEquals(listOf("Not Disclosed"), warningChips(mixed, expanded))
        }
    }
}
