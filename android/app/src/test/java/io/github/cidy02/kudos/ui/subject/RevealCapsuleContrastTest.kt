package io.github.cidy02.kudos.ui.subject

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import kotlin.math.pow
import org.junit.Assert.assertTrue
import org.junit.Test

class RevealCapsuleContrastTest {
    private fun channel(c: Float): Double =
        if (c <= 0.03928f) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4)

    private fun luminance(c: Color): Double =
        0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue)

    private fun contrast(a: Color, b: Color): Double {
        val (hi, lo) = luminance(a).let { la -> luminance(b).let { lb -> maxOf(la, lb) to minOf(la, lb) } }
        return (hi + 0.05) / (lo + 0.05)
    }

    @Test
    fun tapToRevealReaches4_5ToOneOnAnyGroundInEveryTheme() {
        // The capsule is theme-independent now; it must clear 4.5:1 on the whole range of grounds it can sit on:
        // a cover ground (always dark), a bright blurred card (Light/Sepia), and the extremes.
        val grounds = listOf(
            Color.White, Color(0xFFFAF4E8), Color(0xFF808080), Color(0xFFCC3322),
            Color(0xFF3366CC), Color(0xFF1C1C1E), Color.Black
        )
        for (ground in grounds) {
            val behindText = RevealCapsuleColors.backing.compositeOver(ground)
            val ratio = contrast(RevealCapsuleColors.ink, behindText)
            assertTrue("Tap to reveal is $ratio:1 on $ground", ratio >= 4.5)
        }
    }

    @Test
    fun theOldThemeInkOnThemeGlassWasUnreadableOnACoverGround() {
        // Documents why: Light/Sepia glass 0.28 (black at 15.4%) with secondary ink rgba(60,60,67,0.6) on a dark cover.
        val cover = Color(0xFF3A2A55)
        val old = Color.Black.copy(alpha = 0.154f).compositeOver(cover)
        val oldInk = Color(60f / 255f, 60f / 255f, 67f / 255f, 0.6f).compositeOver(old)
        assertTrue(contrast(oldInk, old) < 1.5)
    }
}
