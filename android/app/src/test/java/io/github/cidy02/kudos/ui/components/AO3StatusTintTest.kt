package io.github.cidy02.kudos.ui.components

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Test

/** iOS `WorkStatLabelTests` / T-479 fixed AO3 tag palette. */
class AO3StatusTintTest {
    @Test fun tilePaletteDoesNotShiftWithAppearance() {
        val teen = AO3StatusTint.rating("Teen And Up Audiences")!!
        assertEquals(AO3StatusTint.yellow, AO3StatusTint.forAppearance(teen, isDark = true))
        assertEquals(AO3StatusTint.yellow, AO3StatusTint.forAppearance(teen, isDark = false))
        assertEquals(Color(0xFFF5C400), teen)
    }

    @Test fun metadataUsesTheFixedAo3TagHexes() {
        assertEquals(Color(0xFFC8102E), AO3StatusTint.rating("Explicit"))
        assertEquals(Color(0xFFD2264B), AO3StatusTint.category("F/F"))
        assertEquals(Color(0xFFC8102E), io.github.cidy02.kudos.works.detail.WorkStatRating.color("Explicit", false))
        for (theme in io.github.cidy02.kudos.ui.subject.ReaderTheme.entries) {
            assertEquals(
                Color(0xFFC8102E),
                io.github.cidy02.kudos.works.detail.WorkWarningStatus.Present(1).figureColor(theme)
            )
        }
    }

    @Test fun categoryColorMatchesAO3sOwnCoding() {
        assertEquals(Color(0xFF1C1C1E), AO3StatusTint.category("Other"))
        assertEquals(AO3StatusTint.purple, AO3StatusTint.category("Multi"))
        assertEquals(null, AO3StatusTint.category("Not A Category"))
    }
}
