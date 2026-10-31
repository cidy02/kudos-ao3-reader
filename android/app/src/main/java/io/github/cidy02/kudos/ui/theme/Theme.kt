package io.github.cidy02.kudos.ui.theme

import android.app.Activity
import android.view.View
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat
import io.github.cidy02.kudos.ui.subject.KudosTokens
import io.github.cidy02.kudos.ui.subject.LocalAppPalette
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.LocalSubjectPalette
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import io.github.cidy02.kudos.ui.subject.SubjectPalette

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
    error = ReaderTheme.Light.destructive,
    onError = SubjectPalette.label(ReaderTheme.Light.destructive),
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
    error = ReaderTheme.Dark.destructive,
    onError = SubjectPalette.label(ReaderTheme.Dark.destructive),
    // Material's primary is the filled-control role. Text and links use KudosTokens.accentInk.
    primary = accent,
    onPrimary = SubjectPalette.label(accent),
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
    error = ReaderTheme.Oled.destructive,
    onError = SubjectPalette.label(ReaderTheme.Oled.destructive),
    primary = accent,
    onPrimary = SubjectPalette.label(accent),
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
    error = ReaderTheme.Sepia.destructive,
    onError = SubjectPalette.label(ReaderTheme.Sepia.destructive),
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
    onSurfaceVariant = InkMuted,
    // Left unset, these are Material's lavender-white baseline: stark white cards on Sepia.
    surfaceContainerLowest = ColorTokens.SepiaSurface,
    surfaceContainerLow = ColorTokens.SepiaSurface,
    surfaceContainer = ColorTokens.SepiaVariant,
    surfaceContainerHigh = ColorTokens.SepiaVariant,
    surfaceContainerHighest = ColorTokens.SepiaVariant
)

/** Dark icons in the status and navigation bars when the ground drawn behind them is light. */
internal fun View.setLightSystemBars(light: Boolean) {
    val window = (context as? Activity)?.window ?: return
    WindowCompat.getInsetsController(window, this).apply {
        isAppearanceLightStatusBars = light
        isAppearanceLightNavigationBars = light
    }
}

/** A sheet owns a dialog window; leave the activity's reading-page bars underneath it. */
@Composable
internal fun SheetSystemBars(tokens: KudosTokens) {
    val view = LocalView.current
    val window = (view.parent as? DialogWindowProvider)?.window ?: return
    SideEffect {
        WindowCompat.getInsetsController(window, view).apply {
            isAppearanceLightStatusBars = !tokens.theme.isDarkFamily
            isAppearanceLightNavigationBars = !tokens.theme.isDarkFamily
        }
    }
}

@Composable
fun KudosTheme(
    themeMode: KudosThemeMode,
    accentColorHex: String = DefaultAccentHex,
    content: @Composable () -> Unit
) {
    val systemDark = isSystemInDarkTheme()
    val accent = remember(accentColorHex) { parseAccentColor(accentColorHex) }
    val colorScheme = when (themeMode) {
        KudosThemeMode.System -> if (systemDark) darkScheme(accent) else lightScheme(accent)
        KudosThemeMode.Light -> lightScheme(accent)
        KudosThemeMode.Dark -> darkScheme(accent)
        KudosThemeMode.Oled -> oledScheme(accent)
        KudosThemeMode.Sepia -> SepiaScheme
    }
    // System dark follows Dark, not OLED — the same split the Material schemes use.
    val readerTheme = when (themeMode) {
        KudosThemeMode.System -> if (systemDark) ReaderTheme.Dark else ReaderTheme.Light
        KudosThemeMode.Light -> ReaderTheme.Light
        KudosThemeMode.Dark -> ReaderTheme.Dark
        KudosThemeMode.Oled -> ReaderTheme.Oled
        KudosThemeMode.Sepia -> ReaderTheme.Sepia
    }
    val tokens = remember(themeMode, systemDark, accentColorHex) {
        KudosTokens.of(readerTheme, accent)
    }
    val scopePalette = remember(themeMode, systemDark, accentColorHex) {
        readerTheme.scopePalette(accent)
    }

    // The bars' icons follow the app's theme, not the phone's. `enableEdgeToEdge()` alone leaves
    // a dark clock on a Dark or OLED page whenever the phone is in light mode, and the reverse.
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect { view.setLightSystemBars(!readerTheme.isDarkFamily) }
    }

    CompositionLocalProvider(
        LocalKudosTokens provides tokens,
        LocalAppPalette provides scopePalette,
        LocalSubjectPalette provides scopePalette
    ) {
        MaterialTheme(colorScheme = colorScheme, typography = KudosTypography) {
            // Screens draw on a wash, not on a Material Surface, so nothing else sets the colour
            // of an untinted icon: it stayed black, invisible on Dark and OLED.
            CompositionLocalProvider(LocalContentColor provides colorScheme.onBackground, content = content)
        }
    }
}

const val DefaultAccentHex = "#821019"
const val LegacyDefaultAccentHex = "#990000"

/** Read compatibility only: old default and malformed strings paint AO3 Red without rewriting storage. */
fun resolvedAccentHex(stored: String?): String = when {
    stored == null || stored.equals(LegacyDefaultAccentHex, ignoreCase = true) -> DefaultAccentHex
    runCatching { android.graphics.Color.parseColor(stored) }.isSuccess -> stored
    else -> DefaultAccentHex
}

fun parseAccentColor(hex: String): Color = runCatching {
    Color(android.graphics.Color.parseColor(resolvedAccentHex(hex)))
}.getOrDefault(Ao3Red)

private object ColorTokens {
    val SepiaSurface = androidx.compose.ui.graphics.Color(0xFFFFF6E8)
    val SepiaVariant = androidx.compose.ui.graphics.Color(0xFFEAD8BF)
}
