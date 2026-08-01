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
            lastUpdateCheck = base.lastUpdateCheck,
            isDeleted = if (isRevival) false else base.isDeleted,
            deletedAt = if (isRevival) null else base.deletedAt,
            permanentDeletionScheduledAt = if (isRevival) null else base.permanentDeletionScheduledAt
        )
    }

    private fun choose(remote: String?, local: String, fallback: String = ""): String {
        return remote?.takeIf { it.isNotBlank() } ?: local.takeIf { it.isNotBlank() } ?: fallback
    }
}
