package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadata
import java.time.Instant
import java.util.UUID

class WorkMetadataMerger(
    private val clock: () -> Instant = { Instant.now() },
    private val uuidFactory: () -> String = { UUID.randomUUID().toString() }
) {
    fun merge(
        summary: AO3WorkSummary?,
        canonical: AO3WorkMetadata?,
        existing: SavedWork?,
        markSaved: Boolean,
        hasEpub: Boolean? = null
    ): SavedWork {
        val base = existing ?: SavedWork(
            id = uuidFactory(),
            title = summary?.title.orEmpty().ifBlank { "Untitled" },
            author = summary?.authorText.orEmpty(),
            sourceUrl = summary?.workUrl.orEmpty(),
            dateAdded = clock(),
            hasEpub = false
        )

        val fandoms = canonical?.fandoms?.takeIf { it.isNotEmpty() } ?: summary?.fandoms ?: base.workFandoms
        val relationships = canonical?.relationships?.takeIf { it.isNotEmpty() } ?: summary?.relationships ?: base.workRelationships
        val characters = canonical?.characters?.takeIf { it.isNotEmpty() } ?: summary?.characters ?: base.workCharacters
        val freeforms = canonical?.freeforms?.takeIf { it.isNotEmpty() } ?: summary?.freeforms ?: base.workFreeforms
        val warnings = canonical?.warnings?.takeIf { it.isNotEmpty() } ?: summary?.warnings ?: base.workWarnings
        val categories = canonical?.categories?.takeIf { it.isNotEmpty() } ?: summary?.categories ?: base.workCategories

        return base.copy(
            title = choose(summary?.title, base.title, fallback = "Untitled"),
            author = choose(summary?.authorText, base.author),
            summary = choose(summary?.summary, base.summary),
            sourceUrl = choose(summary?.workUrl, base.sourceUrl),
            isSaved = base.isSaved || markSaved,
            hasEpub = hasEpub ?: base.hasEpub,
            isComplete = summary?.isComplete ?: base.isComplete,
            rating = choose(summary?.rating, base.rating),
            language = choose(canonical?.language, choose(summary?.language, base.language)),
            wordCount = canonical?.words ?: summary?.wordCount ?: base.wordCount,
            chapters = choose(canonical?.chapters, choose(summary?.chapters, base.chapters)),
            kudos = canonical?.kudos ?: summary?.kudos ?: base.kudos,
            comments = canonical?.comments ?: summary?.comments ?: base.comments,
            hits = canonical?.hits ?: summary?.hits ?: base.hits,
            seriesTitle = choose(summary?.seriesTitle, base.seriesTitle),
            seriesPosition = summary?.seriesPosition ?: base.seriesPosition,
            seriesUrl = choose(summary?.seriesUrl, base.seriesUrl),
            workWarnings = warnings.dedupeFirstSeen(),
            workCategories = categories.dedupeFirstSeen(),
            workFandoms = fandoms.dedupeFirstSeen(),
            workCharacters = characters.dedupeFirstSeen(),
            workRelationships = relationships.dedupeFirstSeen(),
            workFreeforms = freeforms.dedupeFirstSeen(),
            workTags = WorkTags.flattenedWorkTags(fandoms, relationships, characters, freeforms),
            workTagsFetched = if (canonical != null && !canonical.isEmpty) true else base.workTagsFetched,
            isFavorite = base.isFavorite,
            isFinished = base.isFinished,
            lastSpineIndex = base.lastSpineIndex,
            lastScrollFraction = base.lastScrollFraction,
            lastReadDate = base.lastReadDate,
            readiumLocator = base.readiumLocator,
            knownChapterCount = base.knownChapterCount,
            lastUpdateCheck = base.lastUpdateCheck
        )
    }

    private fun choose(remote: String?, local: String, fallback: String = ""): String {
        return remote?.takeIf { it.isNotBlank() } ?: local.takeIf { it.isNotBlank() } ?: fallback
    }
}
