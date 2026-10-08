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
    // ReadingQueueService.swift:52–55; WorkDetailView.swift:955. Inclusive, complete first page only.
    fun shouldAutoPreserve(enabled: Boolean): Boolean = enabled && canAutoPreserve

    val knownCount: Int
        get() = preview?.works?.size ?: 0

    val canAutoPreserve: Boolean
        get() = preview != null && preview.currentPage >= preview.totalPages && knownCount <= threshold

    val canUsePreviewForPreservation: Boolean
        get() = preview != null && preview.currentPage >= preview.totalPages

    val message: String
        get() {
            if (previewFailed || preview == null) {
                return "Kudos couldn't check how many works are in this series. Continuing may download many works. " +
                    "Kudos adds them one at a time."
            }
            if (canUsePreviewForPreservation) {
                val s = if (knownCount == 1) "" else "s"
                return "This series has $knownCount work$s. Download every work in the series?"
            }
            val s = if (knownCount == 1) "" else "s"
            return "This series has at least $knownCount work$s and more may be on other pages. Download every work in the series?"
        }

    val autoPreserveLabel: String
        get() = "Always auto-preserve series under $threshold works"
}

// WorkDetailView.swift:1017–1041; ReadingQueues.swift:667–680. Keep copy in one place.
fun SeriesPreservationResult.progressText(): String =
    if (total > 0) "Preserving series $completed of $total…" else "Preserving series…"

fun SeriesPreservationResult.completionText(): String = when {
    cancelled > 0 -> "Series preservation cancelled. Preserved $preserved work${if (preserved == 1) "" else "s"}."
    total == 0 -> "No other series works were found."
    summaryParts("preserved").isEmpty() -> "Series works are already preserved for later."
    else -> "Series preservation complete: " + summaryParts("preserved").joinToString(", ") + "."
}

fun SeriesPreservationResult.queueText(running: Boolean): String = when {
    running && total > 0 -> "Adding $completed of $total series works…"
    cancelled > 0 -> "Stopped adding the series. $preserved work${if (preserved == 1) " was" else "s were"} added."
    total == 0 -> "No series works were found."
    summaryParts("added").isEmpty() -> "Series works are already in the selected queues."
    else -> summaryParts("added").joinToString(", ") + "."
}
