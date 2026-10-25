package io.github.cidy02.kudos.ui.subject

import org.junit.Assert.assertEquals
import org.junit.Test

/** Brief 3dq: counts are written as iOS's compact notation writes them. */
class CompactCountTest {
    @Test fun twoSignificantDigitsAndNeverFewerThanTheWholeNumber() {
        val expected = mapOf(
            999 to "999", 1_000 to "1K", 1_204 to "1.2K", 4_500 to "4.5K", 48_330 to "48K",
            131_006 to "131K", 202_600 to "203K", 312_445 to "312K", 635_800 to "636K", 999_950 to "1M",
            1_500_000 to "1.5M", 2_000_000_000 to "2B", -48_330 to "-48K"
        )
        expected.forEach { (count, text) -> assertEquals("$count", text, count.compactCount()) }
    }
}
