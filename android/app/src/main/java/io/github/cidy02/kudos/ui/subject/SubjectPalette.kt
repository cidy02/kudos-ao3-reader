package io.github.cidy02.kudos.ui.subject

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/** One stop of a subject wash. Locations match the spec: 0, 0.26, 0.52, 0.74, 1. */
data class WashStop(val color: Color, val location: Float)

/**
 * Hue-derived, or picked-colour, colours for one subject.
 * Ported from `SubjectPalette` in `UIComponents/SubjectSurface.swift`.
 *
 * Backgrounds of a picked colour are that colour at an alpha. Text and stroke
 * roles stay on the saturation/brightness table so they keep contrast.
 */
class SubjectPalette private constructor(
    val hue: Double,
    val theme: ReaderTheme,
    private val picked: Color?
) {
    /**
     * Control tint. A picked colour is used exactly, on every theme (T-348).
     * A derived subject uses [accent] instead, so a fandom's buttons are that
     * fandom's colour rather than the app accent.
     */
    val tint: Color
        get() = picked?.let { controlColor(it, theme) } ?: accent

    val accent: Color
        get() = when (theme) {
            ReaderTheme.Dark, ReaderTheme.Oled -> hsb(hue, 0.48, 0.86)
            ReaderTheme.Light -> hsb(hue, 0.72, 0.52)
            ReaderTheme.Sepia -> hsb(hue, 0.60, 0.48)
        }

    val labelOnAccent: Color
        get() = label(accent)

    val accentOnFill: Color
        get() = when (theme) {
            ReaderTheme.Dark, ReaderTheme.Oled -> hsb(hue, 0.18, 0.97)
            ReaderTheme.Light, ReaderTheme.Sepia -> hsb(hue, 0.86, 0.38)
        }

    val washStops: List<WashStop>
        get() {
            val chosen = picked
            if (chosen != null) {
                val alphas = when (theme) {
                    ReaderTheme.Dark -> doubleArrayOf(0.41, 0.33, 0.21, 0.09)
                    ReaderTheme.Oled -> doubleArrayOf(0.48, 0.40, 0.28, 0.17)
                    ReaderTheme.Light -> doubleArrayOf(0.17, 0.13, 0.07, 0.03)
                    ReaderTheme.Sepia -> doubleArrayOf(0.14, 0.10, 0.06, 0.02)
                }
                val locations = floatArrayOf(0f, 0.26f, 0.52f, 0.74f)
                return alphas.mapIndexed { index, alpha ->
                    WashStop(chosen.withOpacity(alpha), locations[index])
                } + WashStop(theme.cardBackdrop, 1f)
            }
            val derived = when (theme) {
                ReaderTheme.Dark, ReaderTheme.Oled -> listOf(
                    stop(0.55, 0.29, 0f),
                    stop(0.53, 0.24, 0.26f),
                    stop(0.42, 0.17, 0.52f),
                    stop(0.26, 0.10, 0.74f)
                )
                ReaderTheme.Light -> listOf(
                    stop(0.20, 0.98, 0f),
                    stop(0.15, 0.98, 0.26f),
                    stop(0.09, 0.99, 0.52f),
                    stop(0.04, 0.99, 0.74f)
                )
                ReaderTheme.Sepia -> listOf(
                    stop(0.22, 0.92, 0f),
                    stop(0.17, 0.92, 0.26f),
                    stop(0.11, 0.92, 0.52f),
                    stop(0.05, 0.92, 0.74f)
                )
            }
            return derived + WashStop(theme.cardBackdrop, 1f)
        }

    /** The wash over [height] px. Give the height: drawRect sizes a gradient by the whole canvas. */
    fun wash(height: Float): Brush = Brush.verticalGradient(
        *washStops.map { it.location to it.color }.toTypedArray(),
        endY = height
    )

    val cardWashColors: List<Color>
        get() {
            val chosen = picked
            if (chosen != null) {
                val alphas = if (theme.isDarkFamily) listOf(0.55, 0.25) else listOf(0.22, 0.10)
                return alphas.map { chosen.withOpacity(it) }
            }
            return when (theme) {
                ReaderTheme.Dark, ReaderTheme.Oled -> listOf(hsb(hue, 0.54, 0.36), hsb(hue, 0.52, 0.155))
                ReaderTheme.Light -> listOf(hsb(hue, 0.26, 0.99), hsb(hue, 0.14, 0.93))
                ReaderTheme.Sepia -> listOf(hsb(hue, 0.24, 0.93), hsb(hue, 0.13, 0.85))
            }
        }

    val cardWash: Brush
        get() = Brush.linearGradient(cardWashColors)

    val rowWashColors: List<Color>
        get() {
            val chosen = picked
            if (chosen != null) {
                val alphas = if (theme.isDarkFamily) listOf(0.30, 0.14) else listOf(0.18, 0.10)
                return alphas.map { chosen.withOpacity(it) }
            }
            return when (theme) {
                ReaderTheme.Dark, ReaderTheme.Oled -> listOf(
                    hsb(hue, 0.53, 0.36, 0.40),
                    hsb(hue, 0.53, 0.16, 0.30)
                )
                ReaderTheme.Light -> listOf(
                    hsb(hue, 0.30, 1.0, 0.42),
                    hsb(hue, 0.22, 0.96, 0.30)
                )
                ReaderTheme.Sepia -> listOf(
                    hsb(hue, 0.30, 0.95, 0.40),
                    hsb(hue, 0.22, 0.88, 0.30)
                )
            }
        }

    val rowWash: Brush
        get() = Brush.linearGradient(rowWashColors)

    val panelWashColors: List<Color>
        get() {
            val chosen = picked
            if (chosen != null) {
                val alphas = if (theme.isDarkFamily) listOf(0.15, 0.06) else listOf(0.14, 0.05)
                return alphas.map { chosen.withOpacity(it) }
            }
            return when (theme) {
                ReaderTheme.Dark, ReaderTheme.Oled -> listOf(
                    hsb(hue, 0.50, 0.60, 0.15),
                    hsb(hue, 0.50, 0.60, 0.06)
                )
                ReaderTheme.Light, ReaderTheme.Sepia -> listOf(
                    hsb(hue, 0.55, 0.70, 0.14),
                    hsb(hue, 0.55, 0.70, 0.05)
                )
            }
        }

    val panelWash: Brush
        get() = Brush.linearGradient(panelWashColors)

    val cardBorder: Color
        get() = if (theme.isDarkFamily) Color.Transparent else accent.withOpacity(0.16)

    val rowBorder: Color
        get() = accent.withOpacity(if (theme.isDarkFamily) 0.22 else 0.18)

    val solidButtonFill: Color
        get() = if (theme.isDarkFamily) Color.White else accent

    val solidButtonLabel: Color
        get() = if (theme.isDarkFamily) hsb(hue, 0.52, 0.155) else Color.White

    val chipFill: Color
        get() = accent.withOpacity(if (theme.isDarkFamily) 0.24 else 0.16)

    val chipStroke: Color
        get() = accent.withOpacity(if (theme.isDarkFamily) 0.50 else 0.40)

    private fun stop(saturation: Double, brightness: Double, location: Float) =
        WashStop(hsb(hue, saturation, brightness), location)

    companion object {
        fun fromHue(hue: Double, theme: ReaderTheme) = SubjectPalette(hue, theme, null)

        fun fromColor(color: Color, theme: ReaderTheme) =
            SubjectPalette(color.hueComponent(), theme, color)

        /**
         * A picked colour as a control colour. Returns the colour itself on every
         * theme. Dark and OLED used to lift it toward white; the owner wants the
         * colour as picked (T-348). [theme] stays in the signature so a later
         * change has the same call site as iOS.
         */
        @Suppress("UNUSED_PARAMETER")
        fun controlColor(color: Color, theme: ReaderTheme): Color = color

        /** Black or white, whichever clears WCAG's 0.179 luminance crossover. */
        fun label(on: Color): Color =
            if (on.relativeLuminance() > 0.179) Color.Black else Color.White
    }
}
