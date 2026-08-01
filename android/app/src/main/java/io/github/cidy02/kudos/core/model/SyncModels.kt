package io.github.cidy02.kudos.core.model

import java.time.Instant
import java.util.UUID

/** Matches Apple `SyncTombstoneRecordType` raw values. */
object SyncTombstoneRecordType {
    const val SAVED_WORK = "savedWork"
    const val WORK_COLLECTION = "workCollection"
    const val READING_QUEUE = "readingQueue"
    const val READING_QUEUE_MEMBERSHIP = "readingQueueMembership"
    const val WORK_COLLECTION_MEMBERSHIP = "workCollectionMembership"
    const val READING_ANNOTATION = "readingAnnotation"
}

/**
 * Durable marker for an explicit local deletion. Backup restore consults these so
 * an older archive does not resurrect a deleted work (Apple SyncTombstone).
 */
data class SyncTombstone(
    val id: String = UUID.randomUUID().toString(),
    val recordID: String,
    val recordTypeRaw: String = SyncTombstoneRecordType.SAVED_WORK,
    val createdAt: Instant = Instant.now(),
    val lastModifiedAt: Instant = createdAt,
    val sourceURL: String = "",
    val ao3WorkID: Int? = null,
    val deletedOnDeviceID: String = "",
    val deletionReason: String = ""
)

data class ReadingQueue(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val kindRaw: String = "custom",
    val sortOrder: Int = 0,
    val dateCreated: Instant = Instant.now(),
    val dateUpdated: Instant = dateCreated,
    val lastMembershipChangedAt: Instant? = null,
    val deletedAt: Instant? = null,
    val isDeleted: Boolean = false,
    val permanentDeletionScheduledAt: Instant? = null
)

data class ReadingQueueMembership(
    val id: String = UUID.randomUUID().toString(),
    val queueID: String,
    val workID: String,
    val queuedAt: Instant = Instant.now(),
    val lastModifiedAt: Instant? = null,
    val sortOrderInQueue: Int = 0,
    val note: String = ""
)

/** In-book annotation (Apple ReadingAnnotation / BackupAnnotation). */
data class ReadingAnnotation(
    val id: String = UUID.randomUUID().toString(),
    val workID: String,
    val kindRaw: String = "bookmark",
    val colorRaw: String = "",
    val locatorString: String = "",
    val selectedText: String = "",
    val note: String = "",
    val progression: Double = 0.0,
    val spineIndex: Int = 0,
    val chapterTitle: String = "",
    val createdAt: Instant = Instant.now(),
    val lastModifiedAt: Instant? = null,
    val deletedAt: Instant? = null,
    val isPendingDeletion: Boolean = false
) {
    val effectiveLastModifiedAt: Instant
        get() = lastModifiedAt ?: createdAt
}
