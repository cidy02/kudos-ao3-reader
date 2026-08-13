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
}
