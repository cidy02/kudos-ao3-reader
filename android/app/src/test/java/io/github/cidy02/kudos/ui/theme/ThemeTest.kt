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
    fun defaultAccentIsAo3Red821019AndLegacy990000MapsToIt() {
        assertEquals(0xFF821019.toInt(), Ao3Red.toArgb())
        assertEquals(0xFFEE8A93.toInt(), AppAccents.Ao3Red.darkInk.toArgb())
        assertEquals("#821019", DefaultAccentHex)
        assertEquals("#821019", resolvedAccentHex(null))
        assertEquals("#821019", resolvedAccentHex(""))
        assertEquals("#821019", resolvedAccentHex("#990000"))
        assertEquals("#821019", resolvedAccentHex(" #990000 "))
        assertEquals("#7B2D6B", resolvedAccentHex("#7B2D6B"))
        for (theme in ReaderTheme.entries) {
            val expected = if (theme == ReaderTheme.Sepia) SepiaTint else Ao3Red
            assertEquals(expected, theme.appTint(Ao3Red))
            assertEquals(expected, KudosTokens.of(theme).accent)
            assertEquals(expected, theme.scopePalette().tint)
        }
    }

    @Test
    fun darkAndOledTextTakesNamedOrReadableStepWhileFillsKeepChosenAccent() {
        for (accent in AppAccents.all) {
            for (theme in listOf(ReaderTheme.Dark, ReaderTheme.Oled)) {
                val tokens = KudosTokens.of(theme, accent.fill)
                assertEquals(accent.fill, tokens.accent)
                assertEquals(accent.darkInk, tokens.accentInk)
                assertEquals(accent.darkInk, theme.scopePalette(accent.fill).controlInk)
                assertEquals(accent.fill, theme.scopePalette(accent.fill).tint)
            }
            assertEquals(accent.fill, ReaderTheme.Light.scopePalette(accent.fill).controlInk)
            assertEquals(SepiaTint, ReaderTheme.Sepia.scopePalette(accent.fill).controlInk)
        }
    }
}
