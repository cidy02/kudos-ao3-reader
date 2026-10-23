package io.github.cidy02.kudos.reader

import androidx.compose.ui.graphics.toArgb
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.reader.settings.ReaderSettingsMapper
import io.github.cidy02.kudos.reader.settings.backgroundColor
import io.github.cidy02.kudos.reader.settings.textColor

/** Local sample from iOS CustomizeThemeView, using the reader's resolved layout values. */
internal fun readerThemePreviewHTML(settings: KudosSettings, fontData: String? = null): String {
    val prefs = ReaderSettingsMapper().map(settings.reader, settings.app)
    val family = if (fontData != null) "preview-custom" else when (settings.reader.readerFontId) {
        "nyserif", "georgia", "palatino", "times" -> "serif"
        "menlo" -> "monospace"
        else -> "sans-serif"
    }
    fun hex(color: androidx.compose.ui.graphics.Color) = "#%06X".format(color.toArgb() and 0xFFFFFF)
    val face = fontData?.let { "@font-face { font-family: preview-custom; src: url('$it'); }" }.orEmpty()
    val reader = settings.reader
    val margin = prefs.pageMarginsFactor * ReaderSettingsMapper.DEFAULT_MARGIN_PT
    return """
        <!doctype html><html lang="en"><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        $face
        html { -webkit-text-size-adjust: 100%; text-size-adjust: 100%; background: ${hex(prefs.theme.backgroundColor())}; color: ${hex(prefs.theme.textColor())}; }
        body { margin: 0; padding: 0.5em ${margin}px 0.7em;
          font-family: $family; font-size: ${reader.readerFontPt}px;
          font-weight: ${if (prefs.bold) "700" else "400"}; line-height: ${prefs.lineHeight};
          letter-spacing: ${prefs.letterSpacingEm}em; word-spacing: ${prefs.wordSpacingEm}em;
          text-align: ${if (prefs.justify) "justify" else "start"}; }
        body > :first-child { margin-top: 0; }
        </style></head><body>
        <h3>A Study in Starlight</h3>
        <p>The lantern guttered as she turned the final page, and for a moment the whole
        library seemed to lean in to listen.</p>
        <p>Outside, the rain had softened to a whisper against the glass — patient and
        unhurried, the way the best stories always are.</p>
        <p>She traced the last line with one finger, unwilling to let it end, and wondered
        how many readers before her had paused in exactly this place.</p>
        <p>Somewhere a clock counted the small hours. The words stayed with her, warm as a
        held breath, long after the candle had burned low.</p>
        <p>When at last she rose, the room felt larger than before — as though the story had
        quietly made room for one more.</p>
        </body></html>
    """.trimIndent()
}
