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
 * android-v0.2.1-alpha wrote membership tombstones as `"$collectionId:$workId"`.
 * Kept for dual-delete of those legacy rows after upgrade.
 */
fun legacyCollectionMembershipRecordId(collectionId: String, workId: String): String =
    "$collectionId:$workId"

/**
 * Canonical (XOR-UUID) form of a WORK_COLLECTION_MEMBERSHIP tombstone recordID.
 *
 * Accepts either:
 * - the current / iOS XOR-UUID form, or
 * - the legacy android-v0.2.1-alpha colon form `"$collectionId:$workId"`.
 *
 * Used on merge lookup and export so rows already persisted by the shipped
 * release keep suppressing resurrection and do not crash [canonicalUuid].
 *
 * @throws IllegalArgumentException if [recordId] is neither a UUID nor a
 * well-formed colon pair of UUIDs.
 */
fun canonicalizeCollectionMembershipRecordId(recordId: String): String {
    val trimmed = recordId.trim()
    try {
        return UUID.fromString(trimmed).toString()
    } catch (_: IllegalArgumentException) {
        // fall through — may be the shipped colon form
    }
    val separator = trimmed.indexOf(':')
    if (separator <= 0 || separator >= trimmed.lastIndex) {
        throw IllegalArgumentException(
            "Not a collection-membership record id: $recordId"
        )
    }
    val left = trimmed.substring(0, separator).trim()
    val right = trimmed.substring(separator + 1).trim()
    // Reject extra colons / garbage after the pair (UUIDs use hyphens only).
    if (right.contains(':')) {
        throw IllegalArgumentException(
            "Not a collection-membership record id: $recordId"
        )
    }
    return collectionMembershipRecordId(left, right)
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
    val deletionReason: String = "",
    val signerPublicKey: String = "",
    val signature: String = ""
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
