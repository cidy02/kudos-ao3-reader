package io.github.cidy02.kudos.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

enum class KudosThemeMode(val label: String) {
    System("System"),
    Light("Light"),
    Dark("Dark"),
    Sepia("Sepia");

    fun next(): KudosThemeMode {
        return when (this) {
            System -> Light
            Light -> Dark
            Dark -> Sepia
            Sepia -> System
        }
    }
}

private val LightScheme = lightColorScheme(
    primary = Ao3Red,
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

private val DarkScheme = darkColorScheme(
    primary = PaperWarm,
    onPrimary = Ao3RedDark,
    secondary = AccentBlue,
    onSecondary = Paper,
    background = SurfaceDark,
    onBackground = Paper,
    surface = SurfaceDark,
    onSurface = Paper,
    surfaceVariant = SurfaceDarkElevated,
    onSurfaceVariant = PaperWarm
)

private val SepiaScheme = lightColorScheme(
    primary = Ao3Red,
    onPrimary = Paper,
    secondary = SuccessGreen,
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
        KudosThemeMode.System -> if (systemDark) DarkScheme else LightScheme
        KudosThemeMode.Light -> LightScheme
        KudosThemeMode.Dark -> DarkScheme
        KudosThemeMode.Sepia -> SepiaScheme
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = KudosTypography,
        content = content
    )
}

private object ColorTokens {
    val SepiaSurface = androidx.compose.ui.graphics.Color(0xFFFFF6E8)
    val SepiaVariant = androidx.compose.ui.graphics.Color(0xFFEAD8BF)
}
