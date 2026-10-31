package io.github.cidy02.kudos.ui.subject

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider

/** A subject sheet keeps its identity palette while every control uses the chosen app colour. */
@Composable
fun SubjectPaletteTheme(palette: SubjectPalette, content: @Composable () -> Unit) {
    val tokens = LocalKudosTokens.current
    val fill = palette.theme.appTint(tokens.accent)
    val ink = palette.theme.accentInk(fill)
    val themedPalette = palette.withAppAccent(fill)
    CompositionLocalProvider(
        LocalSubjectPalette provides themedPalette,
        LocalKudosTokens provides tokens.copy(accent = fill, accentInk = ink, scopePaletteOverride = themedPalette)
    ) {
        MaterialTheme(colorScheme = MaterialTheme.colorScheme.copy(
            primary = ink,
            onPrimary = SubjectPalette.label(ink),
            secondary = ink,
            tertiary = ink
        )) {
            content()
        }
    }
}
