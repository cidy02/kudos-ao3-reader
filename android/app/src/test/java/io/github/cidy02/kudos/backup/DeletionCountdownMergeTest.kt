package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.SavedWork
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * iOS `archivedDeletionState`. A deleted record syncs round with an equal clock on every run,
 * and each merge used to set its removal date to 90 days from that moment: with regular sync
 * the record never left Recently Deleted.
 */
class DeletionCountdownMergeTest {
    private val added = Instant.parse("2026-01-01T00:00:00Z")
    private val deleted = Instant.parse("2026-02-01T00:00:00Z")
    private val scheduled = Instant.parse("2026-05-02T00:00:00Z")

    @Test
    fun aWorkAlreadyCountingDownKeepsItsCountdownWhenTheDeletionSyncsRoundAgain() {
        val local = work().copy(isDeleted = true, deletedAt = deleted, permanentDeletionScheduledAt = scheduled)
        val archived = local.toBackupWork()

        val merged = BackupMergeService.mergeWork(local, archived.toSavedWork(hasEpub = false), archived, deleted)

        assertTrue(merged.isDeleted)
        assertEquals(scheduled, merged.permanentDeletionScheduledAt)
    }

    @Test
    fun aWorkDeletedOnAnotherDeviceStartsItsCountdownHere() {
        val archived = work().copy(isDeleted = true, deletedAt = deleted).toBackupWork()

        val merged = BackupMergeService.mergeWork(work(), archived.toSavedWork(hasEpub = false), archived, deleted)

        assertTrue(merged.isDeleted)
        assertNotNull(merged.permanentDeletionScheduledAt)
        assertTrue(merged.permanentDeletionScheduledAt!!.isAfter(Instant.now()))
    }

    @Test
    fun aRecordThatIsNoLongerDeletedHasNoCountdown() {
        assertNull(keptDeletionSchedule(incoming = null, localIsDeleted = true, local = scheduled))
        assertEquals(scheduled, keptDeletionSchedule(deleted, localIsDeleted = true, local = scheduled))
        assertEquals(deleted, keptDeletionSchedule(deleted, localIsDeleted = false, local = scheduled))
    }

    private fun work() = SavedWork(
        id = "11111111-1111-1111-1111-111111111111",
        title = "Work",
        author = "Writer",
        dateAdded = added,
        hasEpub = false,
        lastModifiedAt = added
    )
}
