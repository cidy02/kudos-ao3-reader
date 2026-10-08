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
    /** Captured once when AO3 finishes downloading or when a file is imported. */
    val downloadedAt: Instant? = null,
    /** Apple sync creation clock; nullable for Android rows created before backup parity. */
    val createdAt: Instant? = null,
    val isFavorite: Boolean = false,
    val hasGivenKudos: Boolean = false,
    val isSaved: Boolean = false,
    /**
     * Added to a reading queue without being explicitly saved (iOS
     * `SavedWork.isQueuedForLater`). Kept distinct from [isSaved] so a
     * queue-only work stays out of Home/Library "saved" shelves until the
     * user explicitly saves or favorites it.
     */
    val isQueuedForLater: Boolean = false,
    val isFinished: Boolean = false,
    val hasEpub: Boolean = true,
    /** Device-local promise of an EPUB not yet received; never a manifest key. */
    val remoteEpubPending: Boolean = false,
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
    val ao3Unavailable: Boolean = false,
    val lastAvailabilityCheck: Instant? = null,
    /** Soft-delete / Recently Deleted (Apple `isPendingDeletion`). */
    val isDeleted: Boolean = false,
    val deletedAt: Instant? = null,
    val permanentDeletionScheduledAt: Instant? = null,
    /**
     * Derived, normalized search blob (title/author/tags/…). Not source of truth —
     * rebuilt from fields via [io.github.cidy02.kudos.works.WorkSearchIndex].
     * Excluded from backup export (rebuilt on restore/launch).
     */
    val searchText: String = "",
    /** Stamp for [io.github.cidy02.kudos.works.WorkSearchIndex.currentVersion]; 0 = never indexed. */
    val searchIndexVersion: Int = 0,
    val lastTagRefreshAttemptAt: Instant? = null,
    /**
     * EPUB preservation state shared with cross-platform backup (iOS
     * `SavedWork.epubPreservationStatusRaw` / `preservedAt` /
     * `lastPreservationAttemptAt`).
     *
     * Explicit Android queue/series preservation stamps these existing fields.
     * Imported rows retain their nullable state until an actual attempt; no backfill.
     * Never use a failed/cancelled status to remove an EPUB or a membership.
     */
    val epubPreservationStatusRaw: String? = null,
    val metadataSyncStatusRaw: String? = null,
    val preservedAt: Instant? = null,
    val lastPreservationAttemptAt: Instant? = null,
    // v11 iOS-parity fields (see WorkEntity).
    val keepInProgressOverride: Boolean = false,
    val hiddenFromHistoryAt: Instant? = null,
    val freedAt: Instant? = null,
    val datePublished: String = "",
    val dateUpdated: String = "",
    val bookmarks: Int? = null,
    val ao3SeriesID: Int? = null,
    val ao3WorkID: Int? = null,
    val legacyReaderProgress: Double? = null,
    val authorIdentitiesJSON: String = "",
    val epubDigest: String = "",
    val assetIdentifier: String = "",
    /** Repository-derived; queue nil means on, collection nil means off, matching iOS. */
    val isKeptOffline: Boolean = false,
    /** First active keep-offline queue or collection, for the `.keptBy` action. */
    val keptOfflineBy: String? = null,
    /** Repository-derived from the shared AO3 identity matcher. Local imports have no AO3 id. */
    val hasAo3WorkId: Boolean = sourceUrl.isNotBlank()
) {
    /** iOS `SavedWork.isDownloaded`: a file on-device that the reader chose to keep. */
    val isDownloaded: Boolean
        get() = WorkDownloadSemantics.isDownloaded(
            hasEpub = hasEpub,
            isSaved = isSaved,
            isKeptOffline = isKeptOffline,
            hasAo3WorkId = hasAo3WorkId
        )

    /** Last-copy and local-import protection stays independent of the Downloaded label. */
    val isProtected: Boolean
        get() = isSaved || isFavorite || isKeptOffline || !hasAo3WorkId || ao3Unavailable

    val needsAO3Refresh: Boolean
        get() = (System.currentTimeMillis() - (lastTagRefreshAttemptAt?.toEpochMilli() ?: 0)) > 86400000L

    /** iOS `SavedWork.isQueueOnlyWork`: queued but not otherwise protected. */
    val isQueueOnlyWork: Boolean
        get() = isQueuedForLater && !isSaved && !isFavorite

    val hasStartedReading: Boolean
        get() = lastReadDate != null ||
            !readiumLocator.isNullOrBlank() ||
            lastSpineIndex > 0 ||
            lastScrollFraction > 0.0

    val isInProgress: Boolean
        get() = hasEpub && !isFinished && hasStartedReading

    /**
     * Posted-chapter count parsed from the `chapters` stats string ("5/10" → 5, "3" → 3).
     * Mirrors Apple `SavedWork.postedChapterCount`.
     */
    val postedChapterCount: Int
        get() = chapters
            .substringBefore('/')
            .trim()
            .toIntOrNull()
            ?: 0

    /**
     * AO3 has new chapters the user hasn't seen (live posted count exceeds the
     * baseline). Drives Home → Recently Updated. Mirrors Apple `SavedWork.hasUpdate`
     * with nullable Android [knownChapterCount].
     */
    val hasUpdate: Boolean
        get() {
            val known = knownChapterCount ?: return false
            return known > 0 && postedChapterCount > known
        }

    /** Effective record modification time for LWW flag/metadata merge. */
    val effectiveLastModifiedAt: Instant
        get() = lastModifiedAt ?: dateAdded

    /** Effective progress modification time for LWW progress merge. */
    val effectiveProgressModifiedAt: Instant?
        get() = progressModifiedAt ?: lastReadDate
}
