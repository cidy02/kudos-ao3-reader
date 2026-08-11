package io.github.cidy02.kudos.ui.theme

import androidx.compose.ui.graphics.toArgb
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ThemeTest {
    @Test
    fun parseAccentColorParsesValidHexAndFallsBackToAo3RedOtherwise() {
        assertEquals(Ao3Red, parseAccentColor("not a color"))
        assertEquals(0xFF0B57D0.toInt(), parseAccentColor("#0B57D0").toArgb())
    }
}
