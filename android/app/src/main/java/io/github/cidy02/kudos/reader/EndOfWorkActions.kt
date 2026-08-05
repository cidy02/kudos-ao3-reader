package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.works.WorkTags

/**
 * End-of-work action data stays engine-agnostic.
 * Auto-finish is driven by [isAtEndOfPublication] on live progress.
 */
data class EndOfWorkActions(
    val canMarkFinished: Boolean,
    val workId: Long?,
    val sourceUrl: String?,
    val seriesUrl: String?,
    val commentsAvailable: Boolean = workId != null
) {
    companion object {
        /** Total-progression threshold treated as "at end" (iOS trailing-edge). */
        const val END_PROGRESSION_THRESHOLD = 0.985

        fun forWork(work: SavedWork): EndOfWorkActions {
            val sourceUrl = work.sourceUrl.ifBlank { null }
            // Item 10: only auto-finish completed fics. An incomplete fic's "end" is just
            // the end of the currently-downloaded chapters, not the story.
            val canAutoFinish = work.isComplete && !work.isFinished
            return EndOfWorkActions(
                canMarkFinished = canAutoFinish,
                workId = sourceUrl?.let(WorkTags::ao3WorkIdFromUrl),
                sourceUrl = sourceUrl,
                seriesUrl = work.seriesUrl.ifBlank { null }
            )
        }

        fun isAtEndOfPublication(progress: ReaderProgress?, spineCount: Int): Boolean {
            if (progress == null) return false
            progress.totalProgression?.let { total ->
                return total >= END_PROGRESSION_THRESHOLD
            }
            if (spineCount <= 0) return false
            val lastSpine = spineCount - 1
            return progress.spineIndex >= lastSpine && progress.scrollFraction >= 0.95
        }
    }
}
