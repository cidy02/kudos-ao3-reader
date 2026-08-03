package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary

/** Pairs a remote work summary with a local [SavedWork] if present in the library. */
data class CanonicalWork(
    val local: SavedWork?,
    val remote: AO3WorkSummary
) {
    val id: String get() = local?.id ?: "remote_${remote.id}"
}

/**
 * Deduplicates remote AO3 lists against the local library so the same work
 * renders as the richer local card when saved.
 * Port of Apple `CanonicalWorkMerge` (Services/CanonicalWorkMerge.swift).
 */
object CanonicalWorkMerge {
    fun remoteLed(remote: List<AO3WorkSummary>, localLibrary: List<SavedWork>): List<CanonicalWork> {
        val index = WorkIdentityIndexInstance(localLibrary)
        val pairedLocalIds = mutableSetOf<String>()
        return remote.map { summary ->
            val match = index.findMatch(summary)
            if (match != null && pairedLocalIds.add(match.id)) {
                CanonicalWork(local = match, remote = summary)
            } else {
                CanonicalWork(local = null, remote = summary)
            }
        }
    }

    fun remoteOnly(remote: List<AO3WorkSummary>, localLibrary: List<SavedWork>): List<AO3WorkSummary> {
        val index = WorkIdentityIndexInstance(localLibrary)
        return remote.filter { index.findMatch(it) == null }
    }
}

class WorkIdentityIndexInstance(works: List<SavedWork>) {
    private val byAo3Id: Map<Long, SavedWork> = works.mapNotNull { work ->
        WorkTags.ao3WorkIdFromUrl(work.sourceUrl)?.let { it to work }
    }.toMap()

    private val byCanonicalUrl: Map<String, SavedWork> = works.mapNotNull { work ->
        WorkTags.canonicalAO3WorkURL(work.sourceUrl)?.let { it to work }
    }.toMap()

    private val bySourceUrl: Map<String, SavedWork> = works.filter { it.sourceUrl.isNotBlank() }
        .associateBy { it.sourceUrl }

    fun findMatch(summary: AO3WorkSummary): SavedWork? {
        val summaryAo3Id = summary.id.takeIf { it > 0 } ?: WorkTags.ao3WorkIdFromUrl(summary.workUrl)
        if (summaryAo3Id != null) {
            byAo3Id[summaryAo3Id]?.let { return it }
            val canonical = WorkTags.canonicalAO3WorkURL(summary.workUrl)
            if (canonical != null) {
                byCanonicalUrl[canonical]?.let { return it }
            }
        }
        if (summary.workUrl.isNotBlank()) {
            bySourceUrl[summary.workUrl]?.let { return it }
        }
        return null
    }
}
