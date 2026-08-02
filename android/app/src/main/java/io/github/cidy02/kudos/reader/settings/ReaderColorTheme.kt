package io.github.cidy02.kudos.reader.settings

import androidx.compose.ui.graphics.Color
import io.github.cidy02.kudos.ui.theme.Paper
import io.github.cidy02.kudos.ui.theme.PaperWarm
import io.github.cidy02.kudos.ui.theme.SurfaceDark

/** Engine-agnostic reader colour theme. Mapped to Readium's EPUB theme in the adapter. */
enum class ReaderColorTheme { Light, Sepia, Dark }

/** Matches the same tone KudosTheme uses for this theme's app-wide background. */
fun ReaderColorTheme.backgroundColor(): Color = when (this) {
    ReaderColorTheme.Light -> Paper
    ReaderColorTheme.Sepia -> PaperWarm
    ReaderColorTheme.Dark -> SurfaceDark
}
