package io.github.cidy02.kudos.ui.subject

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider

/** A coloured sheet owns its controls' tint independently of the page beneath it. */
@Composable
fun SubjectPaletteTheme(palette: SubjectPalette, content: @Composable () -> Unit) {
    val tokens = LocalKudosTokens.current
    val ink = palette.theme.accentInk(palette.tint)
    CompositionLocalProvider(
        LocalSubjectPalette provides palette,
        LocalKudosTokens provides tokens.copy(accent = palette.tint, accentInk = ink, scopePaletteOverride = palette)
    ) {
        MaterialTheme(colorScheme = MaterialTheme.colorScheme.copy(
            primary = palette.tint,
            onPrimary = SubjectPalette.label(palette.tint),
            secondary = ink,
            tertiary = ink
        )) {
            content()
        }
    }
}
