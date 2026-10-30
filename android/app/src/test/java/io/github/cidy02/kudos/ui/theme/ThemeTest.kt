package io.github.cidy02.kudos.ui.theme

import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.Color
import io.github.cidy02.kudos.reader.settings.ReaderColorTheme
import io.github.cidy02.kudos.reader.settings.backgroundColor
import io.github.cidy02.kudos.ui.subject.KudosTokens
import io.github.cidy02.kudos.ui.subject.ReaderTheme
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
    fun theAppColourIsOneFixedAo3RedExceptSepiasBrown() {
        assertEquals(0xFF990000.toInt(), Ao3Red.toArgb())
        assertEquals(0xFFFF7A70.toInt(), Ao3RedInkDark.toArgb())
        assertEquals("#990000", DefaultAccentHex)
        for (theme in ReaderTheme.entries) {
            val expected = if (theme == ReaderTheme.Sepia) SepiaTint else Ao3Red
            assertEquals(expected, theme.appTint)
            assertEquals(expected, KudosTokens.of(theme).accent)
            assertEquals(expected, theme.scopePalette().tint)
        }
    }

    @Test
    fun darkAndOledTextTakesTheLighterRedStepWhileFillsKeepAo3Red() {
        for (theme in listOf(ReaderTheme.Dark, ReaderTheme.Oled)) {
            val tokens = KudosTokens.of(theme)
            assertEquals(Ao3Red, tokens.accent)
            assertEquals(Ao3RedInkDark, tokens.accentInk)
            assertEquals(Ao3RedInkDark, theme.scopePalette().controlInk)
            assertEquals(Ao3Red, theme.scopePalette().tint)
        }
        for (theme in listOf(ReaderTheme.Light, ReaderTheme.Sepia)) {
            assertEquals(theme.appTint, theme.scopePalette().controlInk)
        }
    }
}
