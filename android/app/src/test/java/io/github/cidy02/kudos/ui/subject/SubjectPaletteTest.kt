package io.github.cidy02.kudos.ui.subject

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import io.github.cidy02.kudos.ui.theme.SepiaTint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SubjectPaletteTest {
    @Test
    fun hsbMatchesThePrimaryColours() {
        assertClose(Color.Red, hsb(0.0, 1.0, 1.0))
        assertClose(Color.Green, hsb(1.0 / 3.0, 1.0, 1.0))
        assertClose(Color.Blue, hsb(2.0 / 3.0, 1.0, 1.0))
        val darkenedRed = hsb(0.0, 0.48, 0.86)
        assertEquals(0.86f, darkenedRed.red, 0.01f)
        assertEquals(0.4472f, darkenedRed.green, 0.01f)
        assertEquals(0.4472f, darkenedRed.blue, 0.01f)
    }

    @Test
    fun hueComponentMatchesTheWheelAndGreyIsZero() {
        assertEquals(0.0, Color.Red.hueComponent(), 0.001)
        assertEquals(2.0 / 3.0, Color.Blue.hueComponent(), 0.01)
        assertEquals(0.0, Color.Gray.hueComponent(), 0.0001)
    }

    @Test
    fun aDerivedHueUsesTheSaturationTable() {
        val hue = 38.0 / 360.0
        val dark = SubjectPalette.fromHue(hue, ReaderTheme.Dark)
        assertClose(hsb(hue, 0.48, 0.86), dark.accent)
        assertClose(hsb(hue, 0.18, 0.97), dark.accentOnFill)
        assertClose(hsb(hue, 0.55, 0.29), dark.washStops[0].color)
        assertClose(hsb(hue, 0.53, 0.24), dark.washStops[1].color)
        assertClose(dark.accent.withOpacity(0.24), dark.chipFill)
        assertClose(dark.accent.withOpacity(0.50), dark.chipStroke)
        assertClose(hsb(hue, 0.54, 0.36), dark.cardWashColors[0])
        assertClose(hsb(hue, 0.52, 0.155), dark.cardWashColors[1])
        assertEquals(1f, dark.cardWashColors[0].alpha, 0.001f)
        assertClose(hsb(hue, 0.53, 0.36, 0.40), dark.rowWashColors[0])
        assertClose(hsb(hue, 0.50, 0.60, 0.15), dark.panelWashColors[0])
        assertEquals(0f, dark.cardBorder.alpha, 0.001f)

        val light = SubjectPalette.fromHue(hue, ReaderTheme.Light)
        assertClose(hsb(hue, 0.72, 0.52), light.accent)
        assertClose(hsb(hue, 0.20, 0.98), light.washStops[0].color)
        assertClose(light.accent.withOpacity(0.16), light.chipFill)
        assertClose(light.accent.withOpacity(0.40), light.chipStroke)
        assertClose(light.accent.withOpacity(0.16), light.cardBorder)

        val sepia = SubjectPalette.fromHue(hue, ReaderTheme.Sepia)
        assertClose(hsb(hue, 0.60, 0.48), sepia.accent)
        assertClose(hsb(hue, 0.22, 0.92), sepia.washStops[0].color)
    }

    @Test
    fun bothPathsUseTheSameStopPositionsAndEndOnThePage() {
        val expected = listOf(0f, 0.26f, 0.52f, 0.74f, 1f)
        for (theme in ReaderTheme.entries) {
            val picked = SubjectPalette.fromColor(Color(0xFF5C8C99), theme).washStops
            val derived = SubjectPalette.fromHue(0.1, theme).washStops
            assertEquals(expected, picked.map { it.location })
            assertEquals(expected, derived.map { it.location })
            assertClose(theme.cardBackdrop, picked.last().color)
            assertClose(theme.cardBackdrop, derived.last().color)
        }
    }

    @Test
    fun aPickedColourReachesBackgroundsAsItselfAtAlpha() {
        val picked = Color(0xFF5C8C99)
        val washAlphas = mapOf(
            ReaderTheme.Dark to floatArrayOf(0.41f, 0.33f, 0.21f, 0.09f),
            ReaderTheme.Oled to floatArrayOf(0.48f, 0.40f, 0.28f, 0.17f),
            ReaderTheme.Light to floatArrayOf(0.17f, 0.13f, 0.07f, 0.03f),
            ReaderTheme.Sepia to floatArrayOf(0.14f, 0.10f, 0.06f, 0.02f)
        )
        for ((theme, alphas) in washAlphas) {
            val palette = SubjectPalette.fromColor(picked, theme)
            alphas.forEachIndexed { index, alpha ->
                assertSameRgb("$theme wash $index", picked, palette.washStops[index].color, alpha)
            }
            val card = if (theme.isDarkFamily) floatArrayOf(0.55f, 0.25f) else floatArrayOf(0.22f, 0.10f)
            val row = if (theme.isDarkFamily) floatArrayOf(0.30f, 0.14f) else floatArrayOf(0.18f, 0.10f)
            val panel = if (theme.isDarkFamily) floatArrayOf(0.15f, 0.06f) else floatArrayOf(0.14f, 0.05f)
            card.forEachIndexed { index, alpha ->
                assertSameRgb("$theme card $index", picked, palette.cardWashColors[index], alpha)
            }
            row.forEachIndexed { index, alpha ->
                assertSameRgb("$theme row $index", picked, palette.rowWashColors[index], alpha)
            }
            panel.forEachIndexed { index, alpha ->
                assertSameRgb("$theme panel $index", picked, palette.panelWashColors[index], alpha)
            }
        }
    }

    @Test
    fun twoAccentsSharingAHueDoNotWashTheSame() {
        val muted = hsb(0.95, 0.22, 0.62)
        val vivid = hsb(0.95, 1.0, 1.0)
        for (theme in ReaderTheme.entries) {
            val mutedStop = SubjectPalette.fromColor(muted, theme).washStops.first().color
            val vividStop = SubjectPalette.fromColor(vivid, theme).washStops.first().color
            assertNotEquals(mutedStop, vividStop)
        }
        val derived = SubjectPalette.fromHue(0.58, ReaderTheme.Dark).washStops.first().color
        val asPicked = SubjectPalette.fromColor(hsb(0.58, 1.0, 1.0), ReaderTheme.Dark).washStops.first().color
        assertNotEquals(derived, asPicked)
    }

    @Test
    fun controlsUseThePickedAccentExactly() {
        val picked = Color(0xFF336699)
        for (theme in ReaderTheme.entries) {
            assertEquals(picked.toArgb(), SubjectPalette.controlColor(picked, theme).toArgb())
            assertEquals(picked.toArgb(), SubjectPalette.fromColor(picked, theme).tint.toArgb())
        }
        val dark = SubjectPalette.fromColor(picked, ReaderTheme.Dark)
        assertNotEquals(dark.accent.toArgb(), dark.tint.toArgb())

        val sepiaScope = ReaderTheme.Sepia.scopePalette(picked)
        assertEquals(SepiaTint.toArgb(), sepiaScope.tint.toArgb())
        val darkScope = ReaderTheme.Dark.scopePalette(picked)
        assertEquals(picked.toArgb(), darkScope.tint.toArgb())

        val darkTokens = KudosTokens.of(ReaderTheme.Dark, picked)
        assertEquals(picked.toArgb(), darkTokens.accent.toArgb())
        assertEquals(picked.toArgb(), darkTokens.scopePalette.tint.toArgb())
        val sepiaTokens = KudosTokens.of(ReaderTheme.Sepia, picked)
        assertEquals(SepiaTint.toArgb(), sepiaTokens.accent.toArgb())
        assertEquals(SepiaTint.toArgb(), sepiaTokens.scopePalette.tint.toArgb())

        assertEquals(Color.White, SubjectPalette.label(Color(0xFF990000)))
        assertEquals(Color.Black, SubjectPalette.label(Color.White))
        assertTrue(Color(0xFF990000).relativeLuminance() < 0.179)
        assertEquals(1.0, Color.White.relativeLuminance(), 0.001)
        assertEquals(0.0, Color.Black.relativeLuminance(), 0.001)
    }

    @Test
    fun glassAndPageColoursFollowTheTheme() {
        val dark = KudosTokens.of(ReaderTheme.Dark, Color(0xFF990000))
        assertEquals(11f / 255f, dark.background.red, 0.001f)
        assertEquals(13f / 255f, dark.background.blue, 0.001f)
        assertEquals(0.09f, dark.panelFill.alpha, 0.001f)
        assertEquals(1f, dark.panelFill.red, 0.001f)
        val stroke = dark.glassStroke(0.16)
        assertEquals(0.16f, stroke.alpha, 0.001f)
        assertEquals(1f, stroke.red, 0.001f)

        val light = KudosTokens.of(ReaderTheme.Light, Color(0xFF990000))
        // Compose packs sRGB into 8 bits, so 0.16 * 0.55 lands one level off 0.088.
        assertEquals(0.16 * 0.55, light.glassStroke(0.16).alpha.toDouble(), 1.0 / 255.0)
        assertEquals(0f, light.glassFill().red, 0.001f)
        assertEquals(242f / 255f, light.background.red, 0.001f)

        assertEquals(0f, ReaderTheme.Oled.cardBackdrop.red, 0.001f)
        assertEquals(0.925f, ReaderTheme.Sepia.cardBackdrop.red, 0.001f)
        assertEquals(0.984f, ReaderTheme.Sepia.cardSurface.red, 0.001f)
    }

    private fun assertClose(expected: Color, actual: Color) {
        assertEquals(expected.alpha, actual.alpha, 0.002f)
        assertEquals(expected.red, actual.red, 0.002f)
        assertEquals(expected.green, actual.green, 0.002f)
        assertEquals(expected.blue, actual.blue, 0.002f)
    }

    private fun assertSameRgb(message: String, expected: Color, actual: Color, alpha: Float) {
        assertEquals("$message alpha", alpha, actual.alpha, 0.002f)
        assertEquals("$message red", expected.red, actual.red, 0.002f)
        assertEquals("$message green", expected.green, actual.green, 0.002f)
        assertEquals("$message blue", expected.blue, actual.blue, 0.002f)
    }
}
