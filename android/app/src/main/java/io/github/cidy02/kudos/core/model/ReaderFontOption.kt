package io.github.cidy02.kudos.core.model

/**
 * Selectable reader font. Built-in ids match Apple + [BackupValidator] normalization.
 * Imported fonts use [CustomFont.selectionId] (`custom:<fileName>`).
 */
data class ReaderFontOption(
    val id: String,
    val name: String,
    val isCustom: Boolean = false
)

object ReaderFontCatalog {
    /** Same set as backup-normalized built-in readerFontID values. */
    val builtIns: List<ReaderFontOption> = listOf(
        ReaderFontOption(id = "system", name = "System"),
        ReaderFontOption(id = "nyserif", name = "New York"),
        ReaderFontOption(id = "georgia", name = "Georgia"),
        ReaderFontOption(id = "palatino", name = "Palatino"),
        ReaderFontOption(id = "times", name = "Times New Roman"),
        ReaderFontOption(id = "helvetica", name = "Helvetica Neue"),
        ReaderFontOption(id = "avenir", name = "Avenir"),
        ReaderFontOption(id = "menlo", name = "Menlo")
    )

    val builtInIds: Set<String> = builtIns.map { it.id }.toSet()

    fun options(customFonts: List<CustomFont>): List<ReaderFontOption> {
        val imported = customFonts.map { font ->
            ReaderFontOption(
                id = font.selectionId,
                name = font.name.ifBlank { font.fileName },
                isCustom = true
            )
        }
        return builtIns + imported
    }
}
