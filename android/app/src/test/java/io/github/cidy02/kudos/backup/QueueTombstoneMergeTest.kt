package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A deleted reading queue against a snapshot that still carries it: iOS `PersistenceSyncTests`,
 * the tests of the same names. The queue's own content decides (its edit date and its
 * memberships' dates), never the date the snapshot was written.
 */
class QueueTombstoneMergeTest {
    @Test
    fun suppressedQueueMembershipsAreNotRehomedIntoSavedForLater() {
        // The queue was deleted here; the membership's own id was never seen on this device.
        val result = restore(
            backupWithQueuedWork(queueUpdated = 100, membershipChanged = 100, exported = 100),
            tombstones = listOf(queueTombstone(QUEUE, at = 500))
        )

        assertTrue(result.readingQueues.none { it.kindRaw != ReadingQueueKind.SAVED_FOR_LATER })
        assertTrue(result.readingQueueMemberships.isEmpty())
        assertFalse(result.works.single().isQueuedForLater)
    }

    @Test
    fun newerMembershipChangeRevivesOlderQueueTombstone() {
        val result = restore(
            backupWithQueuedWork(queueUpdated = 50, membershipChanged = 200, exported = 250),
            tombstones = listOf(queueTombstone(QUEUE, at = 100))
        )

        assertEquals("Edited Elsewhere", result.readingQueues.single { it.id == QUEUE }.name)
        assertEquals(1, result.readingQueueMemberships.size)
    }

    @Test
    fun newerQueueMetadataRevivesOlderQueueTombstone() {
        val result = restore(
            backupWithQueuedWork(queueUpdated = 250, membershipChanged = 50, exported = 300),
            tombstones = listOf(queueTombstone(QUEUE, at = 100))
        )

        assertEquals("Edited Elsewhere", result.readingQueues.single { it.id == QUEUE }.name)
        assertEquals(1, result.readingQueueMemberships.size)
    }

    @Test
    fun ambiguousQueueTimestampsPreserveDataForSafety() {
        assertEquals(
            TombstoneResolution.PRESERVE_AMBIGUOUS,
            SyncMerge.tombstoneResolution(incomingModifiedAt = null, tombstoneDeletedAt = at(100))
        )
    }

    @Test
    fun newestQueueTombstoneSuppressesDeterministically() {
        // Deleted, made again, deleted again: the snapshot falls between the two deletions.
        val result = restore(
            backupWithQueuedWork(queueUpdated = 200, membershipChanged = 200, exported = 200),
            tombstones = listOf(
                queueTombstone(QUEUE, at = 50, rowId = "50505050-5050-4050-8050-505050505050"),
                queueTombstone(QUEUE, at = 300, rowId = "30303030-3030-4030-8030-303030303030")
            )
        )

        assertTrue(result.readingQueues.none { it.id == QUEUE })
        assertTrue(result.readingQueueMemberships.isEmpty())
    }

    @Test
    fun oldQueueTombstoneDoesNotSuppressFreshQueueID() {
        val result = restore(
            backupWithQueuedWork(queueUpdated = 200, membershipChanged = 200, exported = 200),
            tombstones = listOf(queueTombstone(OTHER_QUEUE, at = 300))
        )

        assertEquals("Edited Elsewhere", result.readingQueues.single { it.id == QUEUE }.name)
    }

    @Test
    fun exportedAtAloneDoesNotReviveContentStaleQueue() {
        // Written long after the deletion; what it holds predates it.
        val result = restore(
            backupWithQueuedWork(queueUpdated = 50, membershipChanged = 50, exported = 100_000),
            tombstones = listOf(queueTombstone(QUEUE, at = 500))
        )

        assertTrue(result.readingQueues.none { it.id == QUEUE })
        assertTrue(result.readingQueueMemberships.isEmpty())
    }

    @Test
    fun backupImportDoesNotResurrectExplicitlyUnfavoritedWork() {
        // The snapshot was taken while the work was a favorite; it was unfavorited here since.
        val local = SavedWork(
            id = WORK,
            title = "Shared Work",
            author = "Writer",
            sourceUrl = "https://archiveofourown.org/works/424242",
            dateAdded = at(10),
            isSaved = true,
            isFavorite = false,
            lastModifiedAt = at(200)
        )
        val backup = backupWithQueuedWork(queueUpdated = 100, membershipChanged = 100, exported = 100)
        val favorited = backup.copy(
            manifest = backup.manifest.copy(
                works = backup.manifest.works.map { it.copy(isFavorite = true) },
                readingQueues = emptyList(),
                readingQueueMemberships = emptyList()
            )
        )

        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(works = listOf(local)),
            backup = favorited
        ).snapshot

        assertFalse(result.works.single().isFavorite)
    }

    private fun restore(backup: KudosBackupPackage, tombstones: List<SyncTombstone>) =
        BackupMergeService.merge(
            current = BackupLibrarySnapshot(tombstones = tombstones),
            backup = backup
        ).snapshot

    private fun queueTombstone(
        queueId: String,
        at: Long,
        rowId: String = "99999999-9999-4999-8999-999999999999"
    ) = SyncTombstone(
        id = rowId,
        recordID = queueId,
        recordTypeRaw = SyncTombstoneRecordType.READING_QUEUE,
        createdAt = at(at),
        lastModifiedAt = at(at),
        deletionReason = "queueDeleted"
    )

    /** iOS `backupWithQueuedWork`: one work, one custom queue holding it. */
    private fun backupWithQueuedWork(queueUpdated: Long, membershipChanged: Long, exported: Long) =
        KudosBackupPackage(
            manifest = KudosBackupManifest(
                version = BackupVersion.CURRENT,
                exportedAt = at(exported).toString(),
                exportedBy = BackupExportedBy(
                    platform = "ios",
                    appVersion = "test",
                    schemaVersion = BackupVersion.CURRENT
                ),
                works = listOf(
                    BackupWork(
                        id = WORK,
                        title = "Queued Conflict Work",
                        author = "Writer",
                        summary = "",
                        sourceURL = "https://archiveofourown.org/works/424242",
                        dateAdded = at(10).toString(),
                        isFavorite = false,
                        isSaved = true,
                        isFinished = false,
                        hasEPUB = false,
                        isComplete = true,
                        lastSpineIndex = 0,
                        lastScrollFraction = 0.0,
                        lastModifiedAt = at(queueUpdated).toString(),
                        ao3WorkID = 424242
                    )
                ),
                readingQueues = listOf(
                    BackupReadingQueue(
                        id = QUEUE,
                        name = "Edited Elsewhere",
                        kindRaw = "custom",
                        dateCreated = at(10).toString(),
                        dateUpdated = at(queueUpdated).toString(),
                        lastMembershipChangedAt = at(membershipChanged).toString()
                    )
                ),
                readingQueueMemberships = listOf(
                    BackupReadingQueueMembership(
                        id = "77777777-7777-4777-8777-777777777777",
                        queueID = QUEUE,
                        workID = WORK,
                        queuedAt = at(20).toString(),
                        lastModifiedAt = at(membershipChanged).toString()
                    )
                ),
                settings = BackupSettingsPayload()
            ),
            epubFilesByWorkId = emptyMap(),
            fontFilesByFileName = emptyMap()
        )

    private fun at(seconds: Long): Instant = BASE.plusSeconds(seconds)

    private companion object {
        const val WORK = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        const val QUEUE = "0000bbbb-0000-4000-8000-00000000bbbb"
        const val OTHER_QUEUE = "0000eeee-0000-4000-8000-00000000eeee"
        val BASE: Instant = Instant.parse("2026-01-01T00:00:00Z")
    }
}
