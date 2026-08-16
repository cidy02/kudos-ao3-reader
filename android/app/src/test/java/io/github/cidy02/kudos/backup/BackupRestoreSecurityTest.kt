package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.works.WorkRepository
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test
import java.time.Instant
import java.time.Duration
import org.junit.Assert.assertThrows

class BackupRestoreSecurityTest {

    @Test
    fun testAttack_PastPermanentDeletionDate_IsIgnoredAndRecomputed() {
        val now = Instant.now()
        val pastDate = now.minus(Duration.ofDays(10))
        val expectedRecoveryDate = now.plus(WorkRepository.RECOVERY_WINDOW)

        // Work
        val maliciousWork = BackupWork(
            id = "11111111-1111-1111-1111-111111111111",
            title = "Test",
            author = "Author",
            sourceURL = "https://archiveofourown.org/works/1",
            dateAdded = BackupValidator.formatInstant(now),
            isDeleted = true,
            deletedAt = BackupValidator.formatInstant(now),
            permanentDeletionScheduledAt = BackupValidator.formatInstant(pastDate),
            hasEPUB = true
        )
        val restoredWork = maliciousWork.toSavedWork(hasEpub = true)

        assertTrue(restoredWork.isDeleted)
        assertNotNull(restoredWork.permanentDeletionScheduledAt)
        // Since we use Instant.now() internally it might differ by a few ms, so check it's after `now`
        assertTrue(
            "Permanent deletion schedule must be recomputed to the future",
            restoredWork.permanentDeletionScheduledAt!!.isAfter(now)
        )
        assertApproximatelyEqual(
            expectedRecoveryDate,
            restoredWork.permanentDeletionScheduledAt,
            "Work permanent deletion schedule must be approximately now + RECOVERY_WINDOW"
        )
        
        // Collection
        val maliciousCollection = BackupCollection(
            id = "22222222-2222-2222-2222-222222222222",
            name = "My Collection",
            dateAdded = BackupValidator.formatInstant(now),
            isDeleted = true,
            deletedAt = BackupValidator.formatInstant(now),
            permanentDeletionScheduledAt = BackupValidator.formatInstant(pastDate)
        )
        val restoredCollection = maliciousCollection.toWorkCollection()
        
        assertTrue(restoredCollection.isDeleted)
        assertNotNull(restoredCollection.permanentDeletionScheduledAt)
        assertTrue(
            "Collection permanent deletion schedule must be recomputed to the future",
            restoredCollection.permanentDeletionScheduledAt!!.isAfter(now)
        )
        assertApproximatelyEqual(
            expectedRecoveryDate,
            restoredCollection.permanentDeletionScheduledAt,
            "Collection permanent deletion schedule must be approximately now + RECOVERY_WINDOW"
        )

        // Queue
        val maliciousQueue = BackupReadingQueue(
            id = "33333333-3333-3333-3333-333333333333",
            name = "My Queue",
            kindRaw = "custom",
            sortOrder = 0,
            dateCreated = BackupValidator.formatInstant(now),
            dateUpdated = BackupValidator.formatInstant(now),
            isDeleted = true,
            deletedAt = BackupValidator.formatInstant(now),
            permanentDeletionScheduledAt = BackupValidator.formatInstant(pastDate)
        )
        val restoredQueue = maliciousQueue.toReadingQueue()

        assertTrue(restoredQueue.isDeleted)
        assertNotNull(restoredQueue.permanentDeletionScheduledAt)
        assertTrue(
            "Queue permanent deletion schedule must be recomputed to the future",
            restoredQueue.permanentDeletionScheduledAt!!.isAfter(now)
        )
        assertApproximatelyEqual(
            expectedRecoveryDate,
            restoredQueue.permanentDeletionScheduledAt,
            "Queue permanent deletion schedule must be approximately now + RECOVERY_WINDOW"
        )
    }

    @Test
    fun testAttack_HostileArchiveDeletionOverlay_DoesNotScheduleImmediateWipe() {
        val now = Instant.now()
        val pastDate = now.minus(Duration.ofDays(10))
        val expectedRecoveryDate = now.plus(WorkRepository.RECOVERY_WINDOW)
        val localCreated = now.minus(Duration.ofDays(30))
        val incomingNewer = now.minus(Duration.ofMinutes(1))

        val localCollection = WorkCollection(
            id = "77777777-7777-4777-8777-777777777777",
            name = "Live Collection",
            dateAdded = localCreated,
            lastModifiedAt = localCreated,
            isDeleted = false
        )
        val hostileCollection = BackupCollection(
            id = localCollection.id,
            name = "Live Collection",
            dateAdded = BackupValidator.formatInstant(localCreated),
            lastModifiedAt = BackupValidator.formatInstant(incomingNewer),
            isDeleted = true,
            deletedAt = BackupValidator.formatInstant(incomingNewer),
            permanentDeletionScheduledAt = BackupValidator.formatInstant(pastDate)
        )

        val localQueue = ReadingQueue(
            id = "88888888-8888-4888-8888-888888888888",
            name = "Live Queue",
            kindRaw = "custom",
            dateCreated = localCreated,
            dateUpdated = localCreated,
            isDeleted = false
        )
        val hostileQueue = BackupReadingQueue(
            id = localQueue.id,
            name = "Live Queue",
            kindRaw = "custom",
            dateCreated = BackupValidator.formatInstant(localCreated),
            dateUpdated = BackupValidator.formatInstant(incomingNewer),
            isDeleted = true,
            deletedAt = BackupValidator.formatInstant(incomingNewer),
            permanentDeletionScheduledAt = BackupValidator.formatInstant(pastDate)
        )

        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(
                collections = listOf(localCollection),
                readingQueues = listOf(localQueue)
            ),
            backup = KudosBackupPackage(
                manifest = KudosBackupManifest(
                    version = BackupVersion.CURRENT,
                    exportedAt = BackupValidator.formatInstant(now),
                    collections = listOf(hostileCollection),
                    readingQueues = listOf(hostileQueue)
                )
            )
        )

        val mergedCollection = result.snapshot.collections.single()
        assertTrue(mergedCollection.isDeleted)
        assertNotNull(mergedCollection.permanentDeletionScheduledAt)
        assertTrue(
            "Merged collection permanent deletion schedule must be recomputed to the future",
            mergedCollection.permanentDeletionScheduledAt!!.isAfter(now)
        )
        assertApproximatelyEqual(
            expectedRecoveryDate,
            mergedCollection.permanentDeletionScheduledAt,
            "Merged collection must not keep the archive's past wipe deadline"
        )
        assertEquals(1, result.summary.collectionsUpdated)

        val mergedQueue = result.snapshot.readingQueues.single()
        assertTrue(mergedQueue.isDeleted)
        assertNotNull(mergedQueue.permanentDeletionScheduledAt)
        assertTrue(
            "Merged queue permanent deletion schedule must be recomputed to the future",
            mergedQueue.permanentDeletionScheduledAt!!.isAfter(now)
        )
        assertApproximatelyEqual(
            expectedRecoveryDate,
            mergedQueue.permanentDeletionScheduledAt,
            "Merged queue must not keep the archive's past wipe deadline"
        )
        assertEquals(1, result.summary.queuesUpdated)
    }

    @Test
    fun testIsDeletedFalse_ClearsPermanentDeletionSchedule() {
        val now = Instant.now()
        val futureDate = now.plus(Duration.ofDays(10))

        // Work
        val harmlessWork = BackupWork(
            id = "44444444-4444-4444-4444-444444444444",
            title = "Test 2",
            author = "Author",
            sourceURL = "https://archiveofourown.org/works/2",
            dateAdded = BackupValidator.formatInstant(now),
            isDeleted = false,
            deletedAt = BackupValidator.formatInstant(now),
            permanentDeletionScheduledAt = BackupValidator.formatInstant(futureDate),
            hasEPUB = true
        )
        val restoredWork = harmlessWork.toSavedWork(hasEpub = true)
        
        assertFalse(restoredWork.isDeleted)
        assertNull(restoredWork.deletedAt)
        assertNull(restoredWork.permanentDeletionScheduledAt)

        // Collection
        val harmlessCollection = BackupCollection(
            id = "55555555-5555-5555-5555-555555555555",
            name = "My Collection 2",
            dateAdded = BackupValidator.formatInstant(now),
            isDeleted = false,
            deletedAt = BackupValidator.formatInstant(now),
            permanentDeletionScheduledAt = BackupValidator.formatInstant(futureDate)
        )
        val restoredCollection = harmlessCollection.toWorkCollection()

        assertFalse(restoredCollection.isDeleted)
        assertNull(restoredCollection.deletedAt)
        assertNull(restoredCollection.permanentDeletionScheduledAt)

        // Queue
        val harmlessQueue = BackupReadingQueue(
            id = "66666666-6666-6666-6666-666666666666",
            name = "My Queue 2",
            kindRaw = "custom",
            sortOrder = 0,
            dateCreated = BackupValidator.formatInstant(now),
            dateUpdated = BackupValidator.formatInstant(now),
            isDeleted = false,
            deletedAt = BackupValidator.formatInstant(now),
            permanentDeletionScheduledAt = BackupValidator.formatInstant(futureDate)
        )
        val restoredQueue = harmlessQueue.toReadingQueue()

        assertFalse(restoredQueue.isDeleted)
        assertNull(restoredQueue.deletedAt)
        assertNull(restoredQueue.permanentDeletionScheduledAt)
    }

    private fun assertApproximatelyEqual(
        expected: Instant,
        actual: Instant?,
        message: String,
        tolerance: Duration = Duration.ofSeconds(5)
    ) {
        assertNotNull(message, actual)
        val drift = Duration.between(expected, actual!!).abs()
        assertTrue(
            "$message (expected ~$expected, was $actual, drift=${drift.toMillis()}ms)",
            drift <= tolerance
        )
    }

    @Test
    fun testM2b_BlankOrUnknownTombstoneRejected() {
        val blankTombstone = BackupTombstone(
            id = "11111111-1111-1111-1111-111111111111",
            recordID = "22222222-2222-2222-2222-222222222222",
            recordTypeRaw = "   "
        )
        assertThrows(IllegalArgumentException::class.java) {
            blankTombstone.toSyncTombstone()
        }

        val unknownTombstone = BackupTombstone(
            id = "33333333-3333-3333-3333-333333333333",
            recordID = "44444444-4444-4444-4444-444444444444",
            recordTypeRaw = "maliciousType"
        )
        assertThrows(IllegalArgumentException::class.java) {
            unknownTombstone.toSyncTombstone()
        }
    }

    @Test
    fun testM2b_MergeRejectsBlankOrUnknownTombstone() {
        val now = Instant.now()
        val nowStr = BackupValidator.formatInstant(now)

        val blankPack = KudosBackupPackage(
            manifest = KudosBackupManifest(
                version = BackupVersion.CURRENT,
                exportedAt = nowStr,
                tombstones = listOf(
                    BackupTombstone(
                        id = "11111111-1111-1111-1111-111111111111",
                        recordID = "22222222-2222-2222-2222-222222222222",
                        recordTypeRaw = "   ",
                        createdAt = nowStr,
                        lastModifiedAt = nowStr
                    )
                )
            )
        )
        assertThrows(IllegalArgumentException::class.java) {
            BackupMergeService.merge(BackupLibrarySnapshot(), blankPack)
        }

        val unknownPack = KudosBackupPackage(
            manifest = KudosBackupManifest(
                version = BackupVersion.CURRENT,
                exportedAt = nowStr,
                tombstones = listOf(
                    BackupTombstone(
                        id = "33333333-3333-3333-3333-333333333333",
                        recordID = "44444444-4444-4444-4444-444444444444",
                        recordTypeRaw = "maliciousType",
                        createdAt = nowStr,
                        lastModifiedAt = nowStr
                    )
                )
            )
        )
        val thrown = assertThrows(IllegalArgumentException::class.java) {
            BackupMergeService.merge(BackupLibrarySnapshot(), unknownPack)
        }
        assertTrue(
            thrown.message?.contains("recordTypeRaw") == true ||
                thrown.message?.contains("maliciousType") == true
        )
    }
}
