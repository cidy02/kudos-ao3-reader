package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.core.model.SavedWork

/**
 * Minimal end-of-work action scaffold. Real comments and AO3 writes are deferred
 * to later phases; [commentsAvailable] stays false ("comments come in Phase 10").
 */
data class EndOfWorkActions(
    val canMarkFinished: Boolean,
    val sourceUrl: String?,
    val seriesUrl: String?,
    val nextInSeriesAvailable: Boolean = false,
    val commentsAvailable: Boolean = false
) {
    companion object {
        fun forWork(work: SavedWork): EndOfWorkActions = EndOfWorkActions(
            canMarkFinished = !work.isFinished,
            sourceUrl = work.sourceUrl.ifBlank { null },
            seriesUrl = work.seriesUrl.ifBlank { null },
            nextInSeriesAvailable = false,
            commentsAvailable = false
        )
    }
}
