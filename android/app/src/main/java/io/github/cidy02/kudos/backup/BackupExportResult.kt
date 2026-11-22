package io.github.cidy02.kudos.backup

/** Local export receipt; the shared ZIP and manifest are unchanged. */
data class BackupExportResult(
    val bytes: ByteArray,
    val omittedBookTitles: List<String> = emptyList(),
    val omittedFontNames: List<String> = emptyList(),
    val pronunciationsUnreadable: Boolean = false
) {
    fun toUserMessage(): String = buildString {
        append("Exported ${bytes.size / 1024} KB as a v${BackupVersion.CURRENT} .kudosbackup ZIP.")
        if (omittedBookTitles.isNotEmpty()) {
            append(" ${omission(omittedBookTitles, "book")}.")
        }
        if (omittedFontNames.isNotEmpty()) {
            append(" ${omission(omittedFontNames, "font")}.")
        }
        if (pronunciationsUnreadable) {
            append(" $PRONUNCIATIONS_EXPORT_WARNING")
        }
    }

    private fun omission(values: List<String>, noun: String): String {
        val reason = if (values.size == 1) {
            "$noun was left out because its file is missing"
        } else {
            "${noun}s were left out because their files are missing"
        }
        val names = if (values.size > 3) {
            values.take(3).joinToString(", ") + " and ${values.size - 3} more"
        } else {
            values.dropLast(1).joinToString(", ").let { first ->
                if (first.isEmpty()) values.last() else "$first and ${values.last()}"
            }
        }
        return "${values.size} $reason: $names"
    }
}

internal const val PRONUNCIATIONS_EXPORT_WARNING =
    "Pronunciation corrections could not be read. Their file was kept; no local corrections were exported."
