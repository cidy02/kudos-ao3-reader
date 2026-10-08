package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.works.WorkTags

/**
 * End-of-work action data stays engine-agnostic.
 * Auto-finish is driven by [isAtEndOfPublication] on rendered viewport metrics.
 */
data class EndOfWorkActions(
    val canMarkFinished: Boolean,
    val workId: Long?,
    val sourceUrl: String?,
    val seriesUrl: String?,
    val commentsAvailable: Boolean = workId != null
) {
    companion object {
        fun forWork(work: SavedWork): EndOfWorkActions {
            val sourceUrl = work.sourceUrl.ifBlank { null }
            // Item 10: only auto-finish completed fics. An incomplete fic's "end" is just
            // the end of the currently-downloaded chapters, not the story.
            val canAutoFinish = work.isComplete && !work.isFinished
            return EndOfWorkActions(
                canMarkFinished = canAutoFinish,
                workId = work.ao3WorkID?.toLong() ?: sourceUrl?.let(WorkTags::ao3WorkIdFromUrl),
                sourceUrl = sourceUrl,
                seriesUrl = work.seriesUrl.ifBlank { null }
            )
        }

        fun isAtEndOfPublication(viewport: ReaderViewport?, spineCount: Int): Boolean {
            if (viewport == null || spineCount <= 0 || viewport.spineIndex != spineCount - 1) return false
            if (viewport.scrollOffset != null) {
                val extent = viewport.scrollExtent ?: return false
                val range = viewport.scrollRange ?: return false
                return viewport.scrollOffset.isFinite() && viewport.scrollOffset >= 0 &&
                    extent.isFinite() && extent > 0 && range.isFinite() && range > 0 &&
                    viewport.scrollOffset + extent >= range
            }
            return viewport.pageCount > 0 && viewport.page == viewport.pageCount
        }
    }
}
