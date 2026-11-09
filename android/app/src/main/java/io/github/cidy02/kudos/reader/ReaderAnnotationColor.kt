package io.github.cidy02.kudos.reader

import androidx.compose.ui.graphics.Color

/**
 * Muted highlight swatches matching iOS `ReadingAnnotationColor.tint`.
 * Low-saturation so highlights sit under body text and remain readable
 * across all reader themes.
 */
enum class ReadingAnnotationColor(
    val raw: String,
    val displayName: String,
    val color: Color
) {
    YELLOW("yellow", "Yellow", Color(red = 0.98f, green = 0.85f, blue = 0.35f)),
    GREEN("green", "Green", Color(red = 0.55f, green = 0.85f, blue = 0.55f)),
    BLUE("blue", "Blue", Color(red = 0.50f, green = 0.76f, blue = 0.98f)),
    PINK("pink", "Pink", Color(red = 0.98f, green = 0.62f, blue = 0.76f)),
    PURPLE("purple", "Purple", Color(red = 0.76f, green = 0.64f, blue = 0.95f)),
    UNDERLINE("underline", "Underline", Color(red = 0.35f, green = 0.55f, blue = 0.95f));

    companion object {
        fun fromRaw(raw: String?): ReadingAnnotationColor {
            if (raw == null) return YELLOW
            return entries.firstOrNull { it.raw == raw } ?: YELLOW
        }

        /** Uppercase `#RRGGBB`, or null for a preset/malformed value. */
        fun customHex(raw: String?): String? {
            val trimmed = raw?.trim() ?: return null
            if (!trimmed.startsWith("#")) return null
            val digits = trimmed.drop(1)
            if (digits.length != 6 || digits.toLongOrNull(16) == null) return null
            return "#${digits.uppercase()}"
        }

        fun normalizedRaw(raw: String): String =
            entries.firstOrNull { it.raw == raw }?.raw
                ?: customHex(raw)
                ?: YELLOW.raw

        fun displayColor(raw: String?): Color = customHex(raw)
            ?.let { io.github.cidy02.kudos.ui.subject.parseStoredColor(it) }
            ?: fromRaw(raw).color
    }
}
