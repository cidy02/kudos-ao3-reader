package io.github.cidy02.kudos.reader.settings

import androidx.compose.ui.graphics.Color

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
    ReaderColorTheme.Dark -> Color(0xFF16161A)
    ReaderColorTheme.Oled -> Color(0xFF000000)
}

/** Body text: iOS `ReaderTheme.textHex`. */
fun ReaderColorTheme.textColor(): Color = when (this) {
    ReaderColorTheme.Light -> Color(0xFF1E1E1E)
    ReaderColorTheme.Sepia -> Color(0xFF5B4636)
    ReaderColorTheme.Dark, ReaderColorTheme.Oled -> Color(0xFFCFCFD4)
}
