package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage

data class SeriesPreservationResult(
    var total: Int = 0,
    var preserved: Int = 0,
    var alreadyPreserved: Int = 0,
    var skipped: Int = 0,
    var failed: Int = 0,
    var unavailable: Int = 0,
    var cancelled: Int = 0
) {
    val completed: Int
        get() = preserved + alreadyPreserved + skipped + failed + unavailable + cancelled

    fun summaryParts(verb: String): List<String> {
        val parts = mutableListOf<String>()
        if (preserved > 0) parts.add("$preserved $verb")
        if (alreadyPreserved > 0) parts.add("$alreadyPreserved already preserved")
        if (unavailable > 0) parts.add("$unavailable unavailable")
        if (failed > 0) parts.add("$failed failed")
        if (skipped > 0) parts.add("$skipped skipped")
        return parts
    }
}

data class SeriesPreservationPrompt(
    val preview: AO3SearchPage?,
    val threshold: Int,
    val previewFailed: Boolean = false
) {
    val knownCount: Int
        get() = preview?.works?.size ?: 0

    val canAutoPreserve: Boolean
        get() = preview != null && preview.currentPage >= preview.totalPages && knownCount <= threshold

    val canUsePreviewForPreservation: Boolean
        get() = preview != null && preview.currentPage >= preview.totalPages

    val message: String
        get() {
            if (previewFailed || preview == null) {
                return "Kudos couldn't confirm the series size. Preserve the entire series only if " +
                    "you are comfortable with a larger AO3 request, paced one work at a time."
            }
            if (canUsePreviewForPreservation) {
                val s = if (knownCount == 1) "" else "s"
                return "This series has $knownCount work$s. Preserve the entire series?"
            }
            val s = if (knownCount == 1) "" else "s"
            return "This series has at least $knownCount work$s and may span multiple pages. Preserve the entire series?"
        }

    val autoPreserveLabel: String
        get() = "Always auto-preserve series under $threshold works"
}
