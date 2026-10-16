package io.github.cidy02.kudos.ui.theme

import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.Color
import io.github.cidy02.kudos.reader.settings.ReaderColorTheme
import io.github.cidy02.kudos.reader.settings.backgroundColor
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ThemeTest {
    @Test fun darkAppBackgroundReusesReaderBackgroundToken() {
        assertEquals(SurfaceDark, ReaderColorTheme.Dark.backgroundColor())
        assertEquals(0xFF16161A.toInt(), SurfaceDark.toArgb())
        org.junit.Assert.assertNotEquals(Color.Black, SurfaceDark)
        org.junit.Assert.assertNotEquals(SurfaceDark, SurfaceDarkElevated)
        org.junit.Assert.assertNotEquals(SurfaceOled, SurfaceOledElevated)
        assertEquals(Color.Black, ReaderColorTheme.Oled.backgroundColor())
        assertEquals(Color.Black, SurfaceOled)
    }

    @Test
    fun parseAccentColorParsesValidHexAndFallsBackToAo3RedOtherwise() {
        assertEquals(Ao3Red, parseAccentColor("not a color"))
        assertEquals(0xFF0B57D0.toInt(), parseAccentColor("#0B57D0").toArgb())
    }
}
