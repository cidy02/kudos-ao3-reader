package io.github.cidy02.kudos.browse

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary

/** Local Library state for a browsed work, derived without any DB write. */
data class BrowseLocalIndicator(
    val isSaved: Boolean = false,
    val hasEpub: Boolean = false,
    val isFavorite: Boolean = false,
    val isFinished: Boolean = false
) {
    val any: Boolean get() = isSaved || hasEpub || isFavorite || isFinished

    companion object {
        val NONE = BrowseLocalIndicator()
    }
}

/**
 * Pure mapping from saved works to Browse result indicators. Browsing never mutates
 * the Library; this only reads an already-loaded snapshot. Note: [BrowseLocalIndicator.isFinished]
 * is the user's local reading state, NOT the AO3 `isComplete` completion status.
 */
object BrowseLocalIndicators {
    /** Index saved works by canonical source URL for O(1) lookup during composition. */
    fun index(saved: List<SavedWork>): Map<String, SavedWork> =
        saved.asSequence()
            .filter { it.sourceUrl.isNotBlank() }
            .associateBy { it.sourceUrl.trim() }

    fun forWork(summary: AO3WorkSummary, savedByUrl: Map<String, SavedWork>): BrowseLocalIndicator {
        val local = savedByUrl[summary.workUrl.trim()] ?: return BrowseLocalIndicator.NONE
        return BrowseLocalIndicator(
            isSaved = local.isSaved,
            hasEpub = local.hasEpub,
            isFavorite = local.isFavorite,
            isFinished = local.isFinished
        )
    }
}
