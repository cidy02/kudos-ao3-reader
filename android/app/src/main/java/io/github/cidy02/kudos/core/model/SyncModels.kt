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
 * Deterministic, order-independent UUID for a collection↔work membership tombstone,
 * matching iOS `collectionMembershipID`: XOR of the two UUIDs' 16 RFC 4122
 * big-endian bytes (the same layout as [UUID.toString] / [UUID.fromString]).
 *
 * XOR is commutative, so `collectionMembershipRecordId(a, b) ==
 * collectionMembershipRecordId(b, a)`.
 */
fun collectionMembershipRecordId(collectionId: String, workId: String): String {
    val collection = UUID.fromString(collectionId)
    val work = UUID.fromString(workId)
    return UUID(
        collection.mostSignificantBits xor work.mostSignificantBits,
        collection.leastSignificantBits xor work.leastSignificantBits
    ).toString()
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

/** Matches Apple `ReadingQueueKind` raw values. */
object ReadingQueueKind {
    const val SAVED_FOR_LATER = "savedForLater"
    const val CUSTOM = "custom"
    const val SAVED_FOR_LATER_NAME = "Saved for Later"
}

data class ReadingQueue(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val kindRaw: String = ReadingQueueKind.CUSTOM,
    val sortOrder: Int = 0,
    val dateCreated: Instant = Instant.now(),
    val dateUpdated: Instant = dateCreated,
    val lastMembershipChangedAt: Instant? = null,
    val deletedAt: Instant? = null,
    val isDeleted: Boolean = false,
    val permanentDeletionScheduledAt: Instant? = null
) {
    val displayName: String
        get() = if (kindRaw == ReadingQueueKind.SAVED_FOR_LATER) {
            ReadingQueueKind.SAVED_FOR_LATER_NAME
        } else {
            name
        }
}

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
