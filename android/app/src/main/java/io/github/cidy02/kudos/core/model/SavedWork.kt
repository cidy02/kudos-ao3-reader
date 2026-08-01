package io.github.cidy02.kudos.core.model

import java.time.Instant
import java.util.UUID

data class SavedWork(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val author: String,
    val summary: String = "",
    val sourceUrl: String = "",
    val dateAdded: Instant = Instant.now(),
    val isFavorite: Boolean = false,
    val isSaved: Boolean = false,
    val isFinished: Boolean = false,
    val hasEpub: Boolean = true,
    val isComplete: Boolean = false,
    val rating: String = "",
    val language: String = "",
    val wordCount: Int = 0,
    val chapters: String = "",
    val kudos: Int = 0,
    val seriesTitle: String = "",
    val seriesPosition: Int = 0,
    val seriesUrl: String = "",
    val lastSpineIndex: Int = 0,
    val lastScrollFraction: Double = 0.0,
    val lastReadDate: Instant? = null,
    val workWarnings: List<String> = emptyList(),
    val workCategories: List<String> = emptyList(),
    val workTags: List<String> = emptyList(),
    val workFandoms: List<String> = emptyList(),
    val workCharacters: List<String> = emptyList(),
    val workRelationships: List<String> = emptyList(),
    val workFreeforms: List<String> = emptyList(),
    val workTagsFetched: Boolean = false,
    val readiumLocator: String? = null,
    val comments: Int? = null,
    val hits: Int? = null,
    val knownChapterCount: Int? = null,
    val lastUpdateCheck: Instant? = null,
    /** Sync LWW metadata (Apple `lastModifiedAt`). Defaults to [dateAdded]. */
    val lastModifiedAt: Instant? = null,
    /** Progress LWW clock (Apple `progressModifiedAt`). Falls back to [lastReadDate]. */
    val progressModifiedAt: Instant? = null,
    /** Soft-delete / Recently Deleted (Apple `isPendingDeletion`). */
    val isDeleted: Boolean = false,
    val deletedAt: Instant? = null,
    val permanentDeletionScheduledAt: Instant? = null
) {
    val isProtected: Boolean
        get() = isSaved || isFavorite

    val hasStartedReading: Boolean
        get() = lastReadDate != null ||
            !readiumLocator.isNullOrBlank() ||
            lastSpineIndex > 0 ||
            lastScrollFraction > 0.0

    val isInProgress: Boolean
        get() = hasEpub && !isFinished && hasStartedReading

    /** Effective record modification time for LWW flag/metadata merge. */
    val effectiveLastModifiedAt: Instant
        get() = lastModifiedAt ?: dateAdded

    /** Effective progress modification time for LWW progress merge. */
    val effectiveProgressModifiedAt: Instant?
        get() = progressModifiedAt ?: lastReadDate
}
