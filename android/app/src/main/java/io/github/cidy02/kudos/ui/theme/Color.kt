package io.github.cidy02.kudos.ui.theme

import androidx.compose.ui.graphics.Color

internal fun parseHexColorOrNull(hex: String): Color? {
    val trimmed = hex.trim()
    if (!trimmed.startsWith("#")) return null
    val raw = trimmed.substring(1)
    if (raw.length != 6) return null
    val rgb = raw.toLongOrNull(16) ?: return null
    return Color(
        red = ((rgb shr 16) and 0xFF) / 255f,
        green = ((rgb shr 8) and 0xFF) / 255f,
        blue = (rgb and 0xFF) / 255f,
        alpha = 1f
    )
}

/** One named Appearance accent: its exact control fill and Dark/OLED text step. */
data class AppAccent(val name: String, val fillHex: String, val darkInkHex: String) {
    val fill: Color = requireNotNull(parseHexColorOrNull(fillHex)) { fillHex }
    val darkInk: Color = requireNotNull(parseHexColorOrNull(darkInkHex)) { darkInkHex }
    val isDefault: Boolean get() = fillHex.equals(DefaultAccentHex, ignoreCase = true)
}

object AppAccents {
    val Ao3Red = AppAccent("AO3 Red", "#821019", "#EE8A93")
    val Plum = AppAccent("Plum", "#7B2D6B", "#D88BC7")
    val InkBlue = AppAccent("Ink Blue", "#24508F", "#7FA6E8")
    val DeepTeal = AppAccent("Deep Teal", "#11707A", "#5CC3CC")
    val Forest = AppAccent("Forest", "#2F6B4F", "#7CC59E")
    val Ochre = AppAccent("Ochre", "#9A5B00", "#E7A84B")
    val all = listOf(Ao3Red, Plum, InkBlue, DeepTeal, Forest, Ochre)

    fun named(hex: String): AppAccent? = all.firstOrNull { it.fillHex.equals(hex.trim(), ignoreCase = true) }
    fun named(color: Color): AppAccent? = all.firstOrNull { it.fill == color }

    /** Hex shown in the Appearance picker: legacy #990000 and malformed strings show AO3 Red. */
    fun pickerHex(stored: String?): String = resolvedAccentHex(stored)
}

/** Default app accent. A stored legacy #990000 resolves to this without being rewritten. */
val Ao3Red = Color(0xFF821019)
val Ao3RedDark = Color(0xFF660000)
val SepiaTint = Color(0xFF9A6732)
val Ink = Color(0xFF23201D)
val InkMuted = Color(0xFF6F6960)
val Paper = Color(0xFFFFFBF5)
val PaperWarm = Color(0xFFF4E8D7)
/** Shared app and reader Dark base (iOS ReaderTheme.dark.backgroundHex). */
val SurfaceDark = Color(0xFF16161A)
val SurfaceDarkElevated = Color(0xFF252321)
val SurfaceOled = Color(0xFF000000)
val SurfaceOledElevated = Color(0xFF1C1C1E)
val AccentBlue = Color(0xFF356C8C)
val SuccessGreen = Color(0xFF3E6B4F)
