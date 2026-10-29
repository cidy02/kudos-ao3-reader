package io.github.cidy02.kudos.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

enum class KudosThemeMode(val label: String) {
    System("System"),
    Light("Light"),
    Dark("Dark"),
    Oled("OLED"),
    Sepia("Sepia");

    fun next(): KudosThemeMode {
        return when (this) {
            System -> Light
            Light -> Dark
            Dark -> Oled
            Oled -> Sepia
            Sepia -> System
        }
    }
}

private fun lightScheme(accent: Color) = lightColorScheme(
    primary = accent,
    onPrimary = Paper,
    secondary = AccentBlue,
    onSecondary = Paper,
    background = Paper,
    onBackground = Ink,
    surface = Paper,
    onSurface = Ink,
    surfaceVariant = PaperWarm,
    onSurfaceVariant = InkMuted
)

private fun darkScheme(accent: Color) = darkColorScheme(
    primary = PaperWarm,
    onPrimary = accent,
    secondary = AccentBlue,
    onSecondary = Paper,
    background = SurfaceDark,
    onBackground = Paper,
    surface = SurfaceDark,
    onSurface = Paper,
    surfaceVariant = SurfaceDarkElevated,
    onSurfaceVariant = PaperWarm
)

private fun oledScheme(accent: Color) = darkColorScheme(
    primary = PaperWarm,
    onPrimary = accent,
    secondary = AccentBlue,
    onSecondary = Paper,
    background = SurfaceOled,
    onBackground = Paper,
    surface = SurfaceOled,
    onSurface = Paper,
    surfaceVariant = SurfaceOledElevated,
    onSurfaceVariant = PaperWarm
)

private val SepiaScheme = lightColorScheme(
    // Apple suppresses the red accent in Sepia and uses a single warm-brown tint
    // (#9A6732) for controls/links/selection. Match that for parity.
    primary = SepiaTint,
    onPrimary = Paper,
    secondary = SepiaTint,
    onSecondary = Paper,
    background = PaperWarm,
    onBackground = Ink,
    surface = ColorTokens.SepiaSurface,
    onSurface = Ink,
    surfaceVariant = ColorTokens.SepiaVariant,
    onSurfaceVariant = InkMuted
)

@Composable
fun KudosTheme(
    themeMode: KudosThemeMode,
    content: @Composable () -> Unit
) {
    val systemDark = isSystemInDarkTheme()
    val colorScheme = when (themeMode) {
        KudosThemeMode.System -> if (systemDark) darkScheme(Ao3Red) else lightScheme(Ao3Red)
        KudosThemeMode.Light -> lightScheme(Ao3Red)
        KudosThemeMode.Dark -> darkScheme(Ao3Red)
        KudosThemeMode.Oled -> oledScheme(Ao3Red)
        KudosThemeMode.Sepia -> SepiaScheme
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = KudosTypography,
        content = content
    )
}

const val DefaultAccentHex = "#990000"

private object ColorTokens {
    val SepiaSurface = androidx.compose.ui.graphics.Color(0xFFFFF6E8)
    val SepiaVariant = androidx.compose.ui.graphics.Color(0xFFEAD8BF)
}
