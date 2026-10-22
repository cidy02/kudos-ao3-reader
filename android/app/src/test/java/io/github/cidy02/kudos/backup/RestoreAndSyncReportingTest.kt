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
 * Ports of iOS `IncompleteBackupReportingTests` and
 * `FolderSyncTests.folderSyncResultAbsorbsAnotherResultsCountsRatherThanDiscardingThem`.
 */
class RestoreAndSyncReportingTest {
    private val exportedAt = "2026-06-26T12:00:00Z"
    private val workId = "11111111-1111-4111-8111-111111111111"

    @Test
    fun aWorkWhosePromisedEPUBNeverArrivesIsCounted() {
        val result = restore(
            works = listOf(work(workId, hasEpub = true)),
            epubFiles = emptyMap()
        )

        assertEquals(1, result.summary.worksMissingPromisedEPUB)
        assertEquals(1, result.summary.worksRestored)
        assertTrue(
            result.summary.toUserMessage().contains(
                "1 work restored without its EPUB — the backup listed the file " +
                    "but did not contain readable bytes for it"
            )
        )
    }

    @Test
    fun aWorkThatNeverHadAnEPUBIsNotCounted() {
        val result = restore(works = listOf(work(workId, hasEpub = false)))

        assertEquals(0, result.summary.worksMissingPromisedEPUB)
        assertFalse(result.summary.toUserMessage().contains("restored without"))
    }

    @Test
    fun twoWorksWhosePromisedEpubsNeverArriveUseThePlural() {
        val second = "11111111-1111-4111-8111-111111111112"
        val result = restore(
            works = listOf(work(workId, hasEpub = true), work(second, hasEpub = true))
        )

        assertEquals(2, result.summary.worksMissingPromisedEPUB)
        assertTrue(
            result.summary.toUserMessage().contains(
                "2 works restored without their EPUB — the backup listed the file " +
                    "but did not contain readable bytes for it"
            )
        )
    }

    @Test
    fun unreadableBytesAreNotAMissingPromisedEpub() {
        val result = restore(
            works = listOf(work(workId, hasEpub = true)),
            epubFiles = mapOf(workId to "not-an-epub".toByteArray())
        )

        assertEquals(0, result.summary.worksMissingPromisedEPUB)
        assertEquals(1, result.summary.worksRestored)
        assertTrue(result.snapshot.works.single().remoteEpubPending)
    }

    @Test
    fun aPromisedEpubAlreadyOnDiskIsNotCounted() {
        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(
                works = listOf(SavedWork(id = workId, title = "Here", author = "Author"))
            ),
            backup = pack(works = listOf(work(workId, hasEpub = true))),
            mode = BackupImportMode.MERGE
        )

        assertEquals(0, result.summary.worksMissingPromisedEPUB)
        assertEquals(1, result.summary.worksRestored)
    }

    @Test
    fun aSuppressedWorkIsNotCountedAsRestored() {
        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(
                tombstones = listOf(
                    SyncTombstone(
                        recordID = workId,
                        recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                        lastModifiedAt = Instant.parse("2026-06-01T00:00:00Z")
                    )
                )
            ),
            backup = pack(
                works = listOf(
                    work(workId, hasEpub = true).copy(
                        dateAdded = "2020-01-01T00:00:00Z",
                        lastModifiedAt = "2020-01-01T00:00:00Z"
                    )
                )
            ),
            mode = BackupImportMode.MERGE
        )

        assertEquals(0, result.summary.worksRestored)
        assertEquals(1, result.summary.worksSuppressed)
        assertEquals(0, result.summary.worksMissingPromisedEPUB)
    }

    /**
     * A tombstone decision the merge already makes is what the summary counts.
     * Suppress drops the queue. Revive and an ambiguous clock still install it.
     * An ambiguous membership is kept and counted.
     */
    @Test
    fun queueTombstoneDecisionsAreCounted() {
        val stale = "22222222-2222-4222-8222-222222222222"
        val revived = "33333333-3333-4333-8333-333333333333"
        val ambiguous = "44444444-4444-4444-8444-444444444444"
        val membership = "55555555-5555-4555-8555-555555555555"
        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(
                tombstones = listOf(
                    queueTombstone(stale, "2026-01-01T00:00:00Z"),
                    queueTombstone(revived, "2020-01-01T00:00:00Z"),
                    queueTombstone(ambiguous, "2020-01-01T00:00:00Z"),
                    SyncTombstone(
                        recordID = membership,
                        recordTypeRaw = SyncTombstoneRecordType.READING_QUEUE_MEMBERSHIP,
                        lastModifiedAt = Instant.parse("2020-01-01T00:00:00Z")
                    )
                )
            ),
            backup = pack(
                works = listOf(work(workId, hasEpub = false)),
                queues = listOf(
                    queue(stale, dateUpdated = "2020-01-01T00:00:00Z"),
                    queue(revived, dateUpdated = "2026-06-01T00:00:00Z"),
                    queue(ambiguous, dateUpdated = "")
                ),
                memberships = listOf(
                    BackupReadingQueueMembership(id = membership, queueID = revived, workID = workId)
                )
            ),
            mode = BackupImportMode.MERGE
        )

        assertEquals(1, result.summary.suppressedQueues)
        assertEquals(1, result.summary.revivedQueues)
        assertEquals(2, result.summary.ambiguousQueueConflicts)
        assertFalse(result.snapshot.readingQueues.any { it.id == stale })
        assertTrue(result.snapshot.readingQueues.any { it.id == revived })
        assertTrue(result.snapshot.readingQueues.any { it.id == ambiguous })
        assertTrue(result.snapshot.readingQueueMemberships.any { it.id == membership })
    }

    @Test
    fun folderSyncResultAbsorbsAnotherResultsCountsRatherThanDiscardingThem() {
        val total = SyncResult.Success(restoredWorks = 1, suppressedQueues = 1).absorb(
            SyncResult.Success(
                restoredWorks = 2,
                suppressedQueues = 3,
                revivedQueues = 1,
                ambiguousQueueConflicts = 1,
                foldedConflicts = 2
            )
        )

        assertEquals(3, total.restoredWorks)
        assertEquals(4, total.suppressedQueues)
        assertEquals(1, total.revivedQueues)
        assertEquals(1, total.ambiguousQueueConflicts)
        assertEquals(2, total.foldedConflicts)
        assertEquals(
            listOf(
                "Merged 2 conflicting copies from other devices.",
                "Restored 3 works from other devices.",
                "Skipped 4 previously deleted queues.",
                "Restored 1 queue with newer changes than a previous deletion.",
                "Preserved 1 queue conflict because the state was ambiguous."
            ),
            total.footnoteLines()
        )
    }

    private fun restore(
        works: List<BackupWork>,
        epubFiles: Map<String, ByteArray> = emptyMap()
    ): BackupMergeResult = BackupMergeService.merge(
        current = BackupLibrarySnapshot(),
        backup = pack(works = works, epubFiles = epubFiles),
        mode = BackupImportMode.MERGE
    )

    private fun pack(
        works: List<BackupWork>,
        epubFiles: Map<String, ByteArray> = emptyMap(),
        queues: List<BackupReadingQueue> = emptyList(),
        memberships: List<BackupReadingQueueMembership> = emptyList()
    ) = KudosBackupPackage(
        manifest = KudosBackupManifest(
            version = BackupVersion.CURRENT,
            exportedAt = exportedAt,
            works = works,
            readingQueues = queues,
            readingQueueMemberships = memberships
        ),
        epubFilesByWorkId = epubFiles
    )

    private fun work(id: String, hasEpub: Boolean) = BackupWork(
        id = id,
        title = "Promised Book",
        author = "Author",
        dateAdded = exportedAt,
        hasEPUB = hasEpub
    )

    private fun queue(id: String, dateUpdated: String) = BackupReadingQueue(
        id = id,
        name = "Shelf",
        kindRaw = ReadingQueueKind.CUSTOM,
        dateCreated = dateUpdated,
        dateUpdated = dateUpdated
    )

    private fun queueTombstone(id: String, deletedAt: String) = SyncTombstone(
        recordID = id,
        recordTypeRaw = SyncTombstoneRecordType.READING_QUEUE,
        lastModifiedAt = Instant.parse(deletedAt)
    )
}
