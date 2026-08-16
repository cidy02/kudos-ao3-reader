package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.works.WorkRepository
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test
import java.time.Duration
import java.time.Instant
import org.junit.Assert.assertThrows

class BackupRestoreSecurityTest {

    @Test
    fun testAttack_PastPermanentDeletionDate_UnsignedHidesWithoutScheduling() {
        val now = Instant.now()
        val pastDate = now.minus(Duration.ofDays(10))

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
        assertNull(
            "Unsigned isDeleted must not arm a destruction clock",
            restoredWork.permanentDeletionScheduledAt
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
        assertNull(
            "Unsigned collection isDeleted must not arm a destruction clock",
            restoredCollection.permanentDeletionScheduledAt
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
        assertNull(
            "Unsigned queue isDeleted must not arm a destruction clock",
            restoredQueue.permanentDeletionScheduledAt
        )
    }

    @Test
    fun testAttack_HostileArchiveDeletionOverlay_HidesWithoutScheduling() {
        val now = Instant.now()
        val pastDate = now.minus(Duration.ofDays(10))
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

        val localWork = SavedWork(
            id = "99999999-9999-4999-8999-999999999999",
            title = "Live Work",
            author = "Author",
            sourceUrl = "https://archiveofourown.org/works/99",
            dateAdded = localCreated,
            lastModifiedAt = localCreated,
            isDeleted = false,
            isSaved = true
        )
        val hostileWork = BackupWork(
            id = localWork.id,
            title = "Live Work",
            author = "Author",
            sourceURL = localWork.sourceUrl,
            dateAdded = BackupValidator.formatInstant(localCreated),
            lastModifiedAt = BackupValidator.formatInstant(incomingNewer),
            isDeleted = true,
            deletedAt = BackupValidator.formatInstant(incomingNewer),
            permanentDeletionScheduledAt = BackupValidator.formatInstant(pastDate),
            hasEPUB = true
        )

        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(
                works = listOf(localWork),
                collections = listOf(localCollection),
                readingQueues = listOf(localQueue)
            ),
            backup = KudosBackupPackage(
                manifest = KudosBackupManifest(
                    version = BackupVersion.CURRENT,
                    exportedAt = BackupValidator.formatInstant(now),
                    works = listOf(hostileWork),
                    collections = listOf(hostileCollection),
                    readingQueues = listOf(hostileQueue)
                )
            )
        )

        val mergedCollection = result.snapshot.collections.single()
        assertTrue(mergedCollection.isDeleted)
        assertNull(
            "Unsigned collection hide must not start a schedule",
            mergedCollection.permanentDeletionScheduledAt
        )
        assertEquals(1, result.summary.collectionsUpdated)

        val mergedQueue = result.snapshot.readingQueues.single()
        assertTrue(mergedQueue.isDeleted)
        assertNull(
            "Unsigned queue hide must not start a schedule",
            mergedQueue.permanentDeletionScheduledAt
        )
        assertEquals(1, result.summary.queuesUpdated)

        val mergedWork = result.snapshot.works.single()
        assertTrue(mergedWork.isDeleted)
        assertNull(
            "Unsigned work hide must not start a schedule",
            mergedWork.permanentDeletionScheduledAt
        )
        assertEquals(1, result.summary.worksUpdated)
        assertEquals(1, result.summary.unsignedHidesApplied)
        assertEquals(0, result.summary.unsignedHidesHeld)
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

    @Test
    fun unsignedIncomingDeletionNeverSetsAScheduleEvenIfOneWasAlreadyRunning() {
        val running = Instant.parse("1970-01-01T00:08:20Z")
        val state = restoredDeletionState(
            incomingIsDeleted = true,
            localIsPendingDeletion = true,
            localScheduledAt = running,
            hasTrustedTombstone = false,
            now = Instant.parse("1970-01-01T00:16:40Z")
        )
        assertTrue(state.isDeleted)
        assertNull(state.permanentDeletionScheduledAt)
    }

    @Test
    fun trustedTombstoneStartsAFreshLocalWindow() {
        val now = Instant.parse("1970-01-01T00:16:40Z")
        val state = restoredDeletionState(
            incomingIsDeleted = true,
            localIsPendingDeletion = false,
            localScheduledAt = null,
            hasTrustedTombstone = true,
            now = now
        )
        assertTrue(state.isDeleted)
        assertEquals(now.plus(WorkRepository.RECOVERY_WINDOW), state.permanentDeletionScheduledAt)
    }

    @Test
    fun trustedTombstoneKeepsAnAlreadyRunningLocalCountdown() {
        val running = Instant.parse("1970-01-01T00:08:20Z")
        val state = restoredDeletionState(
            incomingIsDeleted = true,
            localIsPendingDeletion = true,
            localScheduledAt = running,
            hasTrustedTombstone = true,
            now = Instant.parse("1970-01-01T00:16:40Z")
        )
        assertEquals(running, state.permanentDeletionScheduledAt)
    }

    @Test
    fun incomingUndeleteClearsBothFields() {
        val state = restoredDeletionState(
            incomingIsDeleted = false,
            localIsPendingDeletion = true,
            localScheduledAt = Instant.parse("1970-01-01T00:08:20Z"),
            hasTrustedTombstone = true,
            now = Instant.parse("1970-01-01T00:16:40Z")
        )
        assertFalse(state.isDeleted)
        assertNull(state.permanentDeletionScheduledAt)
    }

    @Test
    fun mergeHidesWithoutSchedulingWhenArchiveHasNoTrustedTombstone() {
        val now = Instant.parse("2026-06-26T12:00:00Z")
        val local = SavedWork(
            id = "99999999-9999-4999-8999-999999999999",
            title = "Keep Me",
            author = "Writer",
            dateAdded = now.minusSeconds(200),
            lastModifiedAt = now.minusSeconds(200),
            isSaved = true
        )
        val incoming = BackupWork(
            id = local.id,
            title = local.title,
            author = local.author,
            dateAdded = BackupValidator.formatInstant(local.dateAdded),
            lastModifiedAt = BackupValidator.formatInstant(now),
            isDeleted = true,
            deletedAt = BackupValidator.formatInstant(now),
            hasEPUB = true
        )
        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(works = listOf(local)),
            backup = pack(works = listOf(incoming), exportedAt = now)
        )
        val stored = result.snapshot.works.single()
        assertTrue(stored.isDeleted)
        assertNull(stored.permanentDeletionScheduledAt)
        assertEquals(1, result.summary.unsignedHidesApplied)
        assertEquals(0, result.summary.unsignedHidesHeld)
    }

    @Test
    fun mergeSchedulesWhenLocalTrustedTombstoneMatches() {
        val now = Instant.parse("2026-06-26T12:00:00Z")
        val local = SavedWork(
            id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            title = "Deleted For Real",
            author = "Writer",
            sourceUrl = "https://archiveofourown.org/works/8001",
            dateAdded = now.minusSeconds(200),
            lastModifiedAt = now.minusSeconds(200),
            isSaved = true
        )
        val tombstone = SyncTombstone(
            id = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            recordID = local.id,
            recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
            createdAt = now,
            lastModifiedAt = now,
            sourceURL = local.sourceUrl,
            ao3WorkID = 8001
        )
        val incoming = BackupWork(
            id = local.id,
            title = local.title,
            author = local.author,
            sourceURL = local.sourceUrl,
            dateAdded = BackupValidator.formatInstant(local.dateAdded),
            lastModifiedAt = BackupValidator.formatInstant(now.minusSeconds(60)),
            isDeleted = true,
            deletedAt = BackupValidator.formatInstant(now),
            ao3WorkID = 8001,
            hasEPUB = true
        )
        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(works = listOf(local), tombstones = listOf(tombstone)),
            backup = pack(works = listOf(incoming), exportedAt = now)
        )
        val stored = result.snapshot.works.single()
        assertTrue(stored.isDeleted)
        assertNotNull(stored.permanentDeletionScheduledAt)
        assertEquals(0, result.summary.unsignedHidesApplied)
    }

    @Test
    fun mergeHoldsTenUnsignedHidesAndAppliesNone() {
        val now = Instant.parse("2026-06-26T12:00:00Z")
        val locals = (0 until 10).map { index ->
            SavedWork(
                id = paddedUuid(index),
                title = "Victim $index",
                author = "Writer",
                dateAdded = now.minusSeconds(200),
                lastModifiedAt = now.minusSeconds(200),
                isSaved = true
            )
        }
        val incoming = locals.map { local ->
            BackupWork(
                id = local.id,
                title = local.title,
                author = local.author,
                dateAdded = BackupValidator.formatInstant(local.dateAdded),
                lastModifiedAt = BackupValidator.formatInstant(now),
                isDeleted = true,
                deletedAt = BackupValidator.formatInstant(now),
                hasEPUB = true
            )
        }
        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(works = locals),
            backup = pack(works = incoming, exportedAt = now)
        )
        assertEquals(10, result.summary.unsignedHidesHeld)
        assertEquals(0, result.summary.unsignedHidesApplied)
        assertTrue(result.snapshot.works.all { !it.isDeleted })
        assertTrue(result.snapshot.works.all { it.permanentDeletionScheduledAt == null })
    }

    @Test
    fun mergeAppliesNineUnsignedHidesWithoutScheduling() {
        val now = Instant.parse("2026-06-26T12:00:00Z")
        val locals = (0 until 9).map { index ->
            SavedWork(
                id = paddedUuid(index),
                title = "Quiet $index",
                author = "Writer",
                dateAdded = now.minusSeconds(200),
                lastModifiedAt = now.minusSeconds(200),
                isSaved = true
            )
        }
        val incoming = locals.map { local ->
            BackupWork(
                id = local.id,
                title = local.title,
                author = local.author,
                dateAdded = BackupValidator.formatInstant(local.dateAdded),
                lastModifiedAt = BackupValidator.formatInstant(now),
                isDeleted = true,
                deletedAt = BackupValidator.formatInstant(now),
                hasEPUB = true
            )
        }
        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(works = locals),
            backup = pack(works = incoming, exportedAt = now)
        )
        assertEquals(9, result.summary.unsignedHidesApplied)
        assertEquals(0, result.summary.unsignedHidesHeld)
        assertEquals(9, result.snapshot.works.size)
        assertTrue(result.snapshot.works.all { it.isDeleted })
        assertTrue(result.snapshot.works.all { it.permanentDeletionScheduledAt == null })
    }

    @Test
    fun mergeHidesCollectionWithoutSchedulingWhenUnsigned() {
        val now = Instant.parse("2026-06-26T12:00:00Z")
        val local = WorkCollection(
            id = "77777777-7777-4777-8777-777777777777",
            name = "Shelf",
            dateAdded = now.minusSeconds(200),
            lastModifiedAt = now.minusSeconds(200)
        )
        val incoming = BackupCollection(
            id = local.id,
            name = "Shelf",
            dateAdded = BackupValidator.formatInstant(local.dateAdded),
            lastModifiedAt = BackupValidator.formatInstant(now),
            isDeleted = true,
            deletedAt = BackupValidator.formatInstant(now)
        )
        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(collections = listOf(local)),
            backup = pack(collections = listOf(incoming), exportedAt = now)
        )
        val stored = result.snapshot.collections.single()
        assertTrue(stored.isDeleted)
        assertNull(stored.permanentDeletionScheduledAt)
    }

    private fun pack(
        works: List<BackupWork> = emptyList(),
        collections: List<BackupCollection> = emptyList(),
        exportedAt: Instant
    ): KudosBackupPackage {
        return KudosBackupPackage(
            manifest = KudosBackupManifest(
                version = BackupVersion.CURRENT,
                exportedAt = BackupValidator.formatInstant(exportedAt),
                works = works,
                collections = collections
            )
        )
    }

    private fun paddedUuid(index: Int): String {
        return "11111111-1111-4111-8111-${index.toString().padStart(12, '0')}"
    }
}
