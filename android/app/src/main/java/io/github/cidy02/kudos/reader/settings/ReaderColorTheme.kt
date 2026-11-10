package io.github.cidy02.kudos.reader.settings

import androidx.compose.ui.graphics.Color
import io.github.cidy02.kudos.ui.theme.SurfaceDark
import io.github.cidy02.kudos.reader.ReadingAnnotationColor
import io.github.cidy02.kudos.ui.subject.parseStoredColor
import io.github.cidy02.kudos.ui.subject.relativeLuminance

/**
 * Engine-agnostic reader colour theme. Mapped to Readium's EPUB theme in the
 * adapter. Readium has no OLED case of its own, so [Oled] is Readium DARK with a black
 * page — same split as iOS `ReaderTheme.readiumTheme`.
 */
enum class ReaderColorTheme { Light, Sepia, Dark, Oled }

/**
 * The page itself, and the reader's ground around it: iOS `ReaderTheme.backgroundHex`. Readium
 * is given this colour too, so the page and what surrounds it (the strips behind the system
 * bars, the gap while the reader is dragged away) are one colour.
 */
fun ReaderColorTheme.backgroundColor(): Color = when (this) {
    ReaderColorTheme.Light -> Color(0xFFFFFFFF)
    ReaderColorTheme.Sepia -> Color(0xFFFBF0D9)
    ReaderColorTheme.Dark -> SurfaceDark
    ReaderColorTheme.Oled -> Color(0xFF000000)
}

/** Body text: iOS `ReaderTheme.textHex`. */
fun ReaderColorTheme.textColor(): Color = when (this) {
    ReaderColorTheme.Light -> Color(0xFF1E1E1E)
    ReaderColorTheme.Sepia -> Color(0xFF5B4636)
    ReaderColorTheme.Dark, ReaderColorTheme.Oled -> Color(0xFFCFCFD4)
}

data class ReaderPageColors(
    val background: Color,
    val text: Color,
    val isCustom: Boolean
)

/** iOS ReaderPageColors: exact paper plus black/white body text at the WCAG luminance split. */
fun ReaderColorTheme.pageColors(customPaperHex: String?): ReaderPageColors {
    val paper = ReadingAnnotationColor.customHex(customPaperHex)?.let(::parseStoredColor)
    if (paper != null) {
        return ReaderPageColors(
            background = paper,
            text = if (paper.relativeLuminance() > 0.179) Color.Black else Color.White,
            isCustom = true
        )
    }
    return ReaderPageColors(backgroundColor(), textColor(), isCustom = false)
}
