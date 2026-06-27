package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.works.WorkTags

/**
 * End-of-work action data stays engine-agnostic. Android currently exposes the
 * Phase 10 comments entry from reader chrome because the Readium end-position hook
 * is not wired yet.
 */
data class EndOfWorkActions(
    val canMarkFinished: Boolean,
    val workId: Long?,
    val sourceUrl: String?,
    val seriesUrl: String?,
    val nextInSeriesAvailable: Boolean = false,
    val commentsAvailable: Boolean = workId != null
) {
    companion object {
        fun forWork(work: SavedWork): EndOfWorkActions {
            val sourceUrl = work.sourceUrl.ifBlank { null }
            return EndOfWorkActions(
                canMarkFinished = !work.isFinished,
                workId = sourceUrl?.let(WorkTags::ao3WorkIdFromUrl),
                sourceUrl = sourceUrl,
                seriesUrl = work.seriesUrl.ifBlank { null },
                nextInSeriesAvailable = false
            )
        }
    }
}
