package io.github.cidy02.kudos.ui.components

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `WorkStatLabelTests` (A58 #13). */
class AO3StatusTintTest {
    @Test fun teenRatingDarkensInLightAppearances() {
        val teen = AO3StatusTint.rating("Teen And Up Audiences")!!
        assertEquals(AO3StatusTint.yellow, AO3StatusTint.forAppearance(teen, isDark = true))
        val light = AO3StatusTint.forAppearance(teen, isDark = false)
        assertTrue(light.red < 0.6f && light.green < 0.45f)
        assertEquals(AO3StatusTint.red, AO3StatusTint.forAppearance(AO3StatusTint.red, isDark = false))
    }

    @Test fun redMetadataUsesTheSameSystemRedAsIosInEachTheme() {
        for (theme in io.github.cidy02.kudos.ui.subject.ReaderTheme.entries) {
            val expected = if (theme.isDarkFamily) Color(0xFFFF4245) else Color(0xFFFF383C)
            assertEquals(expected, AO3StatusTint.forAppearance(AO3StatusTint.rating("Explicit")!!, theme.isDarkFamily))
            assertEquals(expected, AO3StatusTint.forAppearance(AO3StatusTint.category("F/F")!!, theme.isDarkFamily))
            assertEquals(expected, io.github.cidy02.kudos.works.detail.WorkStatRating.color("Explicit", theme.isDarkFamily))
            assertEquals(expected, io.github.cidy02.kudos.works.detail.WorkWarningStatus.Present(1).figureColor(theme))
        }
    }

    @Test fun categoryColorMatchesAO3sOwnCoding() {
        assertEquals(Color.Black, AO3StatusTint.category("Other"))
        assertEquals(AO3StatusTint.purple, AO3StatusTint.category("Multi"))
        assertEquals(null, AO3StatusTint.category("Not A Category"))
    }
}
