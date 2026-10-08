package io.github.cidy02.kudos.ui.subject

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import io.github.cidy02.kudos.ui.theme.Ao3Red
import io.github.cidy02.kudos.ui.theme.SepiaTint

/**
 * The four app themes iOS calls `ReaderTheme`. Android's System mode resolves to
 * Light or Dark before a palette is built; it is not a fifth visual theme.
 */
enum class ReaderTheme {
    Light,
    Sepia,
    Dark,
    Oled;

    val isDarkFamily: Boolean
        get() = this == Dark || this == Oled

    /**
     * Page behind washed screens (`cardBackdrop`).
     *
     * Dark is not the reader page colour. `AppThemeSurface` special-cases it to
     * rgb(11, 11, 13) before the `appBaseBackground` fallback.
     * Light's `appBaseBackground` is nil, so iOS uses `systemGroupedBackground`;
     * the resolved light value is #F2F2F7.
     */
    val cardBackdrop: Color
        get() = when (this) {
            Dark -> Color(red = 11f / 255f, green = 11f / 255f, blue = 13f / 255f)
            Oled -> Color.Black
            Sepia -> Color(red = 0.925f, green = 0.871f, blue = 0.757f)
            Light -> Color(red = 242f / 255f, green = 242f / 255f, blue = 247f / 255f)
        }

    /** Elevated card surface (`cardSurface` / `appElevatedBackground`). */
    val cardSurface: Color
        get() = when (this) {
            // Light falls through to secondarySystemGroupedBackground, which is white.
            Light -> Color.White
            Sepia -> Color(red = 0.984f, green = 0.941f, blue = 0.851f)
            Dark -> Color(red = 0.133f, green = 0.133f, blue = 0.157f)
            Oled -> Color(red = 0.110f, green = 0.110f, blue = 0.118f)
        }

    /**
     * Sepia's fixed control tint (`ReaderTheme.appTint`). Other themes return
     * null and the caller's picked accent is used exactly.
     */
    val appTint: Color?
        get() = if (this == Sepia) SepiaTint else null

    /** `Color.primary` for this theme's colour scheme. Sepia is a light scheme. */
    val primaryInk: Color
        get() = if (isDarkFamily) Color.White else Color.Black

    /**
     * `Color.secondary`. Resolved UIKit `secondaryLabel`:
     * rgba(60, 60, 67, 0.6) on light schemes, rgba(235, 235, 245, 0.6) on dark.
     */
    val secondaryInk: Color
        get() = ink(alpha = 0.6)

    /** `Color.tertiary`. Same base as [secondaryInk], at 0.3 alpha. */
    val tertiaryInk: Color
        get() = ink(alpha = 0.3)

    /**
     * Hairline. Sepia is the only theme with an explicit `appSeparator`.
     * Light and dark use the resolved UIKit separator.
     */
    val separator: Color
        get() = when (this) {
            Sepia -> Color(red = 0.357f, green = 0.275f, blue = 0.212f).withOpacity(0.18)
            Dark, Oled -> Color(red = 84f / 255f, green = 84f / 255f, blue = 88f / 255f).withOpacity(0.6)
            Light -> Color(red = 60f / 255f, green = 60f / 255f, blue = 67f / 255f).withOpacity(0.29)
        }

    fun glassFill(opacity: Double = 0.12): Color = glass(opacity)

    fun glassStroke(opacity: Double = 0.16): Color = glass(opacity)

    /** Scope palette: the user's accent, or Sepia's own brown when the theme refuses the accent. */
    fun scopePalette(userAccent: Color): SubjectPalette =
        SubjectPalette.fromColor(appTint ?: userAccent, this)

    private fun glass(opacity: Double): Color =
        if (isDarkFamily) Color.White.withOpacity(opacity) else Color.Black.withOpacity(opacity * 0.55)

    private fun ink(alpha: Double): Color {
        val base = if (isDarkFamily) {
            Color(red = 235f / 255f, green = 235f / 255f, blue = 245f / 255f)
        } else {
            Color(red = 60f / 255f, green = 60f / 255f, blue = 67f / 255f)
        }
        return base.withOpacity(alpha)
    }
}

/**
 * Semantic colours for the redesign, provided by [io.github.cidy02.kudos.ui.theme.KudosTheme].
 * Material schemes stay as they are; existing screens keep reading those.
 */
data class KudosTokens(
    val theme: ReaderTheme,
    /** Picked accent, used exactly. Sepia substitutes [ReaderTheme.appTint]. */
    val accent: Color,
    val background: Color,
    val panelFill: Color,
    val cardFill: Color,
    val primaryInk: Color,
    val secondaryInk: Color,
    val tertiaryInk: Color,
    val separator: Color
) {
    /** Shared favorite star, as on the existing work cards. */
    val favoriteGold: Color get() = Color(0xFFFFC107)

    val scopePalette: SubjectPalette
        get() = theme.scopePalette(accent)

    fun glassFill(opacity: Double = 0.12): Color = theme.glassFill(opacity)

    fun glassStroke(opacity: Double = 0.16): Color = theme.glassStroke(opacity)

    companion object {
        fun of(theme: ReaderTheme, userAccent: Color): KudosTokens {
            val accent = theme.appTint ?: userAccent
            return KudosTokens(
                theme = theme,
                accent = accent,
                background = theme.cardBackdrop,
                panelFill = theme.glassFill(0.09),
                cardFill = theme.cardSurface,
                primaryInk = theme.primaryInk,
                secondaryInk = theme.secondaryInk,
                tertiaryInk = theme.tertiaryInk,
                separator = theme.separator
            )
        }
    }
}

val LocalKudosTokens = staticCompositionLocalOf { KudosTokens.of(ReaderTheme.Light, Ao3Red) }

val LocalSubjectPalette = staticCompositionLocalOf { ReaderTheme.Light.scopePalette(Ao3Red) }
