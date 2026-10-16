package io.github.cidy02.kudos.works.detail

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.works.WorkIdentityIndex

object WorkDetailPresentation {
    enum class PostRemovalAction { KeepLocal, ShowRemote, Dismiss }

    fun postRemovalAction(isPendingDeletion: Boolean, hasRemoteSource: Boolean): PostRemovalAction =
        if (!isPendingDeletion) PostRemovalAction.KeepLocal
        else if (hasRemoteSource) PostRemovalAction.ShowRemote else PostRemovalAction.Dismiss

    fun summaryFromLocal(work: SavedWork): AO3WorkSummary? {
        val id = WorkIdentityIndex.ao3WorkId(work) ?: return null
        return AO3WorkSummary(
            id = id, title = work.title, authors = work.author.split(',').map { it.trim() }.filter { it.isNotEmpty() },
            fandoms = work.workFandoms, rating = work.rating, warnings = work.workWarnings, categories = work.workCategories,
            relationships = work.workRelationships, characters = work.workCharacters, freeforms = work.workFreeforms,
            summary = work.summary, language = work.language, wordCount = work.wordCount, chapters = work.chapters,
            kudos = work.kudos, comments = work.comments, hits = work.hits, bookmarks = work.bookmarks,
            seriesTitle = work.seriesTitle, seriesPosition = work.seriesPosition, seriesUrl = work.seriesUrl,
            isComplete = work.knownCompletion, updatedDate = work.dateUpdated, publishedDate = work.datePublished,
            authorIdentitiesJSON = work.authorIdentitiesJSON
        )
    }

    fun queueLabel(count: Int): String = if (count <= 0) "Add to Queue" else "In $count ${if (count == 1) "Queue" else "Queues"}"
    fun collectionLabel(count: Int): String = if (count <= 0) "Add to Collection" else "In $count ${if (count == 1) "Collection" else "Collections"}"
}
