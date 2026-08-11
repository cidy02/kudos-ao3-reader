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
        hasEpub: Boolean? = null,
        isQueuedForLater: Boolean = false
    ): SavedWork {
        val base = existing ?: SavedWork(
            id = uuidFactory(),
            title = summary?.title.orEmpty().ifBlank { "Untitled" },
            author = summary?.authorText.orEmpty(),
            sourceUrl = summary?.workUrl.orEmpty(),
            dateAdded = clock(),
            hasEpub = false
        )

        // `existing` can be a soft-deleted (Recently Deleted) row — WorkIdentityIndex's
        // lookup tiers don't filter isDeleted, by design, so the same work downloaded or
        // saved again is recognised as the same row rather than creating a duplicate.
        // Without this, `base.copy(...)` below carries isDeleted/deletedAt/
        // permanentDeletionScheduledAt straight through unchanged (Kotlin's data-class
        // copy keeps whatever a field isn't explicitly given), so the merged row kept
        // ticking toward permanent deletion — the download reported success but the
        // work never reappeared in the Library, and was later purged for good. Mirrors
        // Apple `PreservedWorkService.restore`: revival on any interaction, not only an
        // explicit "restore" tap.
        val isRevival = existing?.isDeleted == true

        val fandoms = mergeTagLists(base.workFandoms, canonical?.fandoms, summary?.fandoms)
        val relationships = mergeTagLists(base.workRelationships, canonical?.relationships, summary?.relationships)
        val characters = mergeTagLists(base.workCharacters, canonical?.characters, summary?.characters)
        val freeforms = mergeTagLists(base.workFreeforms, canonical?.freeforms, summary?.freeforms)
        val warnings = mergeTagLists(base.workWarnings, canonical?.warnings, summary?.warnings)
        val categories = mergeTagLists(base.workCategories, canonical?.categories, summary?.categories)

        return base.copy(
            title = choose(summary?.title, base.title, fallback = "Untitled"),
            author = choose(summary?.authorText, base.author),
            summary = choose(summary?.summary, base.summary),
            sourceUrl = choose(summary?.workUrl, base.sourceUrl),
            isSaved = base.isSaved || markSaved,
            isQueuedForLater = base.isQueuedForLater || isQueuedForLater,
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
            workWarnings = warnings,
            workCategories = categories,
            workFandoms = fandoms,
            workCharacters = characters,
            workRelationships = relationships,
            workFreeforms = freeforms,
            workTags = WorkTags.flattenedWorkTags(fandoms, relationships, characters, freeforms),
            workTagsFetched = if (canonical != null && !canonical.isEmpty) true else base.workTagsFetched,
            isFavorite = base.isFavorite,
            isFinished = base.isFinished,
            lastSpineIndex = base.lastSpineIndex,
            lastScrollFraction = base.lastScrollFraction,
            lastReadDate = base.lastReadDate,
            readiumLocator = base.readiumLocator,
            knownChapterCount = base.knownChapterCount,
            lastUpdateCheck = base.lastUpdateCheck,
            isDeleted = if (isRevival) false else base.isDeleted,
            deletedAt = if (isRevival) null else base.deletedAt,
            permanentDeletionScheduledAt = if (isRevival) null else base.permanentDeletionScheduledAt
        )
    }

    private fun mergeTagLists(
        existing: List<String>,
        canonical: List<String>?,
        summary: List<String>?
    ): List<String> {
        val list = mutableListOf<Iterable<String>>()
        list.add(existing)
        if (!canonical.isNullOrEmpty()) list.add(canonical)
        if (!summary.isNullOrEmpty()) list.add(summary)
        return list.flatten().dedupeFirstSeen()
    }

    private fun choose(remote: String?, local: String, fallback: String = ""): String {
        return remote?.takeIf { it.isNotBlank() } ?: local.takeIf { it.isNotBlank() } ?: fallback
    }
}
