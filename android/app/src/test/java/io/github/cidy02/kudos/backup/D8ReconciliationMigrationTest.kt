package io.github.cidy02.kudos.backup

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.WorkFileStore
import java.io.File
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Production entry: [D8ReconciliationMigration.runIfNeeded] and
 * [BackupRepository.importPackage] / [BackupRepository.applyHeldUnsignedHides].
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class D8ReconciliationMigrationTest {
    private lateinit var context: Context
    private lateinit var database: KudosDatabase
    private lateinit var settingsScope: CoroutineScope
    private lateinit var settingsRepository: SettingsRepository
    private lateinit var backupRepository: BackupRepository

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        settingsScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val settingsDir = Files.createTempDirectory("kudos-d8-settings").toFile()
        settingsRepository = SettingsRepository(
            PreferenceDataStoreFactory.create(
                scope = settingsScope,
                produceFile = { File(settingsDir, "settings.preferences_pb") }
            )
        )
        val filesRoot = Files.createTempDirectory("kudos-d8-files")
        backupRepository = BackupRepository(
            database = database,
            workFileStore = WorkFileStore(filesRoot),
            fontFileStore = FontFileStore(filesRoot),
            settingsRepository = settingsRepository,
            persistenceGate = PersistenceGate(),
            clock = { CLOCK },
            uuidFactory = { "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" },
            appVersion = "test"
        )
        UnsignedDeletionReview.resetForTests()
    }

    @After
    fun tearDown() {
        database.close()
        settingsScope.cancel()
        UnsignedDeletionReview.resetForTests()
    }

    @Test
    fun runIfNeededClearsUnsignedScheduleWithoutClearingHide() = runTest {
        database.workDao().upsert(
            pendingWork(
                id = WORK_UNSIGNED,
                sourceUrl = "https://archiveofourown.org/works/8002",
                scheduledAt = CLOCK.minusSeconds(1)
            ).toEntity()
        )

        D8ReconciliationMigration.runIfNeeded(database, settingsRepository)

        val stored = database.workDao().getById(WORK_UNSIGNED)!!
        assertNull(stored.permanentDeletionScheduledAt)
        assertTrue(stored.isDeleted)
        assertTrue(settingsRepository.isD8ReconciliationComplete())
    }

    @Test
    fun runIfNeededKeepsAScheduleBackedByALocalTombstone() = runTest {
        database.workDao().upsert(
            pendingWork(
                id = WORK_TRUSTED,
                sourceUrl = "https://archiveofourown.org/works/8003",
                scheduledAt = CLOCK.plusSeconds(86_400)
            ).toEntity()
        )
        database.syncTombstoneDao().upsert(
            SyncTombstone(
                id = TOMBSTONE_ID,
                recordID = WORK_TRUSTED,
                recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                createdAt = CLOCK,
                lastModifiedAt = CLOCK,
                sourceURL = "https://archiveofourown.org/works/8003",
                ao3WorkID = 8003
            ).toEntity()
        )

        D8ReconciliationMigration.runIfNeeded(database, settingsRepository)

        val stored = database.workDao().getById(WORK_TRUSTED)!!
        assertNotNull(stored.permanentDeletionScheduledAt)
        assertTrue(stored.isDeleted)
    }

    @Test
    fun runIfNeededKeepsScheduleWhenTombstoneIsOlderThanWorkClock() = runTest {
        // Existence-only: a first-party tombstone still backs the clock even if
        // lastModifiedAt was later bumped. suppressesWorkResurrection would
        // false-negative this row.
        database.workDao().upsert(
            pendingWork(
                id = WORK_STALE_CLOCK,
                sourceUrl = "https://archiveofourown.org/works/8004",
                scheduledAt = CLOCK.plusSeconds(86_400),
                lastModifiedAt = CLOCK.plusSeconds(3_600)
            ).toEntity()
        )
        database.syncTombstoneDao().upsert(
            SyncTombstone(
                id = "33333333-3333-4333-8333-333333333334",
                recordID = WORK_STALE_CLOCK,
                recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                createdAt = CLOCK,
                lastModifiedAt = CLOCK,
                sourceURL = "https://archiveofourown.org/works/8004",
                ao3WorkID = 8004
            ).toEntity()
        )

        D8ReconciliationMigration.runIfNeeded(database, settingsRepository)

        assertNotNull(database.workDao().getById(WORK_STALE_CLOCK)!!.permanentDeletionScheduledAt)
    }

    @Test
    fun runIfNeededClearsCollectionAndQueueSchedulesWithoutLocalTombstones() = runTest {
        database.collectionDao().upsert(
            WorkCollection(
                id = COLLECTION_ID,
                name = "Shelf",
                dateAdded = CLOCK,
                isDeleted = true,
                deletedAt = CLOCK,
                permanentDeletionScheduledAt = CLOCK.minusSeconds(1)
            ).toEntity()
        )
        database.readingQueueDao().upsertQueue(
            ReadingQueue(
                id = QUEUE_ID,
                name = "Weekend",
                dateCreated = CLOCK,
                dateUpdated = CLOCK,
                isDeleted = true,
                deletedAt = CLOCK,
                permanentDeletionScheduledAt = CLOCK.minusSeconds(1)
            ).toEntity()
        )
        database.collectionDao().upsert(
            WorkCollection(
                id = COLLECTION_TRUSTED,
                name = "Kept",
                dateAdded = CLOCK,
                isDeleted = true,
                deletedAt = CLOCK,
                permanentDeletionScheduledAt = CLOCK.plusSeconds(86_400)
            ).toEntity()
        )
        database.syncTombstoneDao().upsert(
            SyncTombstone(
                id = "44444444-4444-4444-8444-444444444444",
                recordID = COLLECTION_TRUSTED,
                recordTypeRaw = SyncTombstoneRecordType.WORK_COLLECTION,
                createdAt = CLOCK,
                lastModifiedAt = CLOCK
            ).toEntity()
        )

        D8ReconciliationMigration.runIfNeeded(database, settingsRepository)

        assertNull(database.collectionDao().getById(COLLECTION_ID)!!.permanentDeletionScheduledAt)
        assertTrue(database.collectionDao().getById(COLLECTION_ID)!!.isDeleted)
        assertNull(database.readingQueueDao().getQueueById(QUEUE_ID)!!.permanentDeletionScheduledAt)
        assertTrue(database.readingQueueDao().getQueueById(QUEUE_ID)!!.isDeleted)
        assertNotNull(
            database.collectionDao().getById(COLLECTION_TRUSTED)!!.permanentDeletionScheduledAt
        )
    }

    @Test
    fun runIfNeededIsANoOpOnceComplete() = runTest {
        database.workDao().upsert(
            pendingWork(id = WORK_UNSIGNED, scheduledAt = CLOCK.minusSeconds(1)).toEntity()
        )
        D8ReconciliationMigration.runIfNeeded(database, settingsRepository)
        assertNull(database.workDao().getById(WORK_UNSIGNED)!!.permanentDeletionScheduledAt)

        database.workDao().upsert(
            pendingWork(id = WORK_UNSIGNED, scheduledAt = CLOCK.minusSeconds(1)).toEntity()
        )
        D8ReconciliationMigration.runIfNeeded(database, settingsRepository)
        assertNotNull(
            "second pass must not re-scan after the completion flag is set",
            database.workDao().getById(WORK_UNSIGNED)!!.permanentDeletionScheduledAt
        )
    }

    @Test
    fun importPackageHoldsTenUnsignedHidesAndAppliesNone() = runTest {
        val locals = (0 until 10).map { index ->
            SavedWork(
                id = paddedUuid(index),
                title = "Victim $index",
                author = "Writer",
                dateAdded = CLOCK.minusSeconds(200),
                lastModifiedAt = CLOCK.minusSeconds(200),
                isSaved = true
            )
        }
        locals.forEach { database.workDao().upsert(it.toEntity()) }

        val summary = backupRepository.importPackage(
            KudosBackupPackage(
                manifest = KudosBackupManifest(
                    version = BackupVersion.CURRENT,
                    exportedAt = BackupValidator.formatInstant(CLOCK),
                    works = locals.map { local ->
                        BackupWork(
                            id = local.id,
                            title = local.title,
                            author = local.author,
                            dateAdded = BackupValidator.formatInstant(local.dateAdded),
                            lastModifiedAt = BackupValidator.formatInstant(CLOCK),
                            isDeleted = true,
                            deletedAt = BackupValidator.formatInstant(CLOCK),
                            hasEPUB = true
                        )
                    }
                )
            )
        )

        assertEquals(10, summary.unsignedHidesHeld)
        assertEquals(0, summary.unsignedHidesApplied)
        val stored = database.workDao().getAllIncludingDeleted()
        assertTrue(stored.all { !it.isDeleted })
        assertTrue(stored.all { it.permanentDeletionScheduledAt == null })
        val hold = UnsignedDeletionReview.pendingHold.value
        assertNotNull(hold)
        assertEquals(10, hold!!.count)
        assertEquals("your Library Sync Folder", hold.sourceLabel)
    }

    @Test
    fun applyHeldUnsignedHidesHidesWithoutSchedulingOrMintingATombstone() = runTest {
        database.workDao().upsert(
            SavedWork(
                id = WORK_UNSIGNED,
                title = "Held",
                author = "Writer",
                dateAdded = CLOCK,
                lastModifiedAt = CLOCK,
                isSaved = true
            ).toEntity()
        )

        backupRepository.applyHeldUnsignedHides(listOf(WORK_UNSIGNED))

        val stored = database.workDao().getById(WORK_UNSIGNED)!!
        assertTrue(stored.isDeleted)
        assertEquals(CLOCK, stored.deletedAt)
        assertNull(stored.permanentDeletionScheduledAt)
        assertTrue(database.syncTombstoneDao().getAll().isEmpty())
    }

    private fun pendingWork(
        id: String,
        sourceUrl: String = "",
        scheduledAt: Instant,
        lastModifiedAt: Instant = CLOCK
    ): SavedWork {
        return SavedWork(
            id = id,
            title = "Hidden",
            author = "Writer",
            sourceUrl = sourceUrl,
            dateAdded = CLOCK,
            lastModifiedAt = lastModifiedAt,
            isSaved = true,
            isDeleted = true,
            deletedAt = CLOCK,
            permanentDeletionScheduledAt = scheduledAt
        )
    }

    private fun paddedUuid(index: Int): String {
        return "11111111-1111-4111-8111-${index.toString().padStart(12, '0')}"
    }

    companion object {
        private val CLOCK: Instant = Instant.parse("2026-06-26T12:00:00Z")
        private const val WORK_UNSIGNED = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1"
        private const val WORK_TRUSTED = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2"
        private const val WORK_STALE_CLOCK = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3"
        private const val TOMBSTONE_ID = "33333333-3333-4333-8333-333333333333"
        private const val COLLECTION_ID = "77777777-7777-4777-8777-777777777777"
        private const val COLLECTION_TRUSTED = "77777777-7777-4777-8777-777777777778"
        private const val QUEUE_ID = "88888888-8888-4888-8888-888888888888"
    }
}
