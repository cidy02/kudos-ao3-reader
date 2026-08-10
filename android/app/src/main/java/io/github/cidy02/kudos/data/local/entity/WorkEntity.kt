package io.github.cidy02.kudos.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant

@Entity(
    tableName = "works",
    indices = [
        Index("sourceUrl"),
        Index("title"),
        Index("author")
    ]
)
data class WorkEntity(
    @PrimaryKey val id: String,
    val title: String,
    val author: String,
    val summary: String,
    val sourceUrl: String,
    val dateAdded: Instant,
    val isFavorite: Boolean,
    val isSaved: Boolean,
    val isFinished: Boolean,
    val hasEpub: Boolean,
    val isComplete: Boolean,
    val rating: String,
    val language: String,
    val wordCount: Int,
    val chapters: String,
    val kudos: Int,
    val seriesTitle: String,
    val seriesPosition: Int,
    val seriesUrl: String,
    val lastSpineIndex: Int,
    val lastScrollFraction: Double,
    val lastReadDate: Instant?,
    val workWarnings: List<String>,
    val workCategories: List<String>,
    val workTags: List<String>,
    val workFandoms: List<String>,
    val workCharacters: List<String>,
    val workRelationships: List<String>,
    val workFreeforms: List<String>,
    val workTagsFetched: Boolean,
    val readiumLocator: String?,
    val comments: Int?,
    val hits: Int?,
    val knownChapterCount: Int?,
    val lastUpdateCheck: Instant?,
    val lastModifiedAt: Instant? = null,
    val progressModifiedAt: Instant? = null,
    val ao3Unavailable: Boolean = false,
    val lastAvailabilityCheck: Instant? = null,
    val isDeleted: Boolean = false,
    val deletedAt: Instant? = null,
    val permanentDeletionScheduledAt: Instant? = null,
    val isQueuedForLater: Boolean = false,
    val searchText: String = "",
    val searchIndexVersion: Int = 0,

    val lastTagRefreshAttemptAt: Instant? = null,
    /**
     * Cross-platform backup pass-through only (see [io.github.cidy02.kudos.core.model.SavedWork]).
     * Nullable with no backfill — existing rows simply have no preservation history.
     * Android must not act on these values.
     */
    val epubPreservationStatusRaw: String? = null,
    val preservedAt: Instant? = null,
    val lastPreservationAttemptAt: Instant? = null
)
