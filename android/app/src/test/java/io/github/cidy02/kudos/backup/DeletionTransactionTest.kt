package io.github.cidy02.kudos.backup

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.google.crypto.tink.subtle.Ed25519Sign
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueMembership
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.core.model.collectionMembershipRecordId
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.CollectionWorkCrossRef
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.reader.AnnotationRepository
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Real DAO statements: an SQLite trigger throws from the delete AFTER verifying tombstone-first. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class DeletionTransactionTest {
    private lateinit var db: KudosDatabase
    private lateinit var root: Path
    private lateinit var files: WorkFileStore
    private lateinit var works: WorkRepository
    private val now = Instant.parse("2026-01-01T00:00:00Z")

    @Before
    fun setUp() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), KudosDatabase::class.java)
            .allowMainThreadQueries().build()
        root = Files.createTempDirectory("kudos-delete-transaction")
        files = WorkFileStore(root)
        works = WorkRepository(db, files, clock = { now })
        val key = Ed25519Sign.KeyPair.newKeyPair()
        TombstoneSigning.initializeWithRawKeyPair(key.privateKey, key.publicKey)
    }

    @After
    fun tearDown() {
        db.close()
        root.toFile().deleteRecursively()
        TombstoneSigning.resetForTests()
    }

    @Test
    fun highlightDeleteIsTombstoneFirstAndRollsBackBothDaoStatements() = runTest {
        seed()
        val repository = AnnotationRepository(db.annotationDao(), db.syncTombstoneDao(), clock = { now })
        failDelete("annotations", "id", ANN, "readingAnnotation", ANN)
        expectSecondStatementFailure { repository.deleteAnnotation(ANN) }
        assertNotNull(db.annotationDao().getById(ANN))
        assertTrue(db.syncTombstoneDao().getAll().isEmpty())
        requireTombstoneBeforeDelete("annotations", "id", ANN, "readingAnnotation", ANN)
        repository.deleteAnnotation(ANN)
        assertNull(db.annotationDao().getById(ANN))
        assertEquals(1, db.syncTombstoneDao().getByRecord(ANN, "readingAnnotation").size)
    }

    @Test
    fun queueMembershipDeleteIsTombstoneFirstAndRollsBackItsQueueAndWorkEdits() = runTest {
        seed()
        val repository = ReadingQueueRepository(db, clock = { now.plusSeconds(1) })
        val beforeQueue = db.readingQueueDao().getQueueById(QUEUE)
        val beforeWork = db.workDao().getById(WORK)
        failDelete("reading_queue_memberships", "id", MEMBER, "readingQueueMembership", MEMBER)
        expectSecondStatementFailure { repository.removeWork(QUEUE, WORK) }
        assertNotNull(db.readingQueueDao().getMembershipForWork(QUEUE, WORK))
        assertEquals(beforeQueue, db.readingQueueDao().getQueueById(QUEUE))
        assertEquals(beforeWork, db.workDao().getById(WORK))
        assertTrue(db.syncTombstoneDao().getAll().isEmpty())
        requireTombstoneBeforeDelete("reading_queue_memberships", "id", MEMBER, "readingQueueMembership", MEMBER)
        repository.removeWork(QUEUE, WORK)
        assertNull(db.readingQueueDao().getMembershipForWork(QUEUE, WORK))
        assertEquals(1, db.syncTombstoneDao().getByRecord(MEMBER, "readingQueueMembership").size)
    }

    @Test
    fun workHardDeleteRollsBackEveryDependentAndKeepsEpubWhenFinalDaoDeleteThrows() = runTest {
        seed()
        files.writeWorkEpub(WORK, io.github.cidy02.kudos.works.converters.EpubBuilder.buildEpub("Work", "<p>Text.</p>"))
        failDelete("works", "id", WORK, "savedWork", WORK)
        expectSecondStatementFailure { works.hardDelete(WORK) }
        assertNotNull(db.workDao().getById(WORK))
        assertNotNull(db.annotationDao().getById(ANN))
        assertNotNull(db.readingQueueDao().getMembershipForWork(QUEUE, WORK))
        assertEquals(listOf(WORK), db.collectionDao().getWorkIdsForCollection(COLLECTION))
        assertTrue(db.syncTombstoneDao().getAll().isEmpty())
        assertTrue(files.workEpubExists(WORK))
        requireTombstoneBeforeDelete("works", "id", WORK, "savedWork", WORK)
        // Dependents also require a tombstone before their individual delete.
        orderTrigger("ann_order", "annotations", "id", ANN, "readingAnnotation", ANN, false)
        orderTrigger("member_order", "reading_queue_memberships", "id", MEMBER, "readingQueueMembership", MEMBER, false)
        works.hardDelete(WORK)
        assertNull(db.workDao().getById(WORK))
        assertNull(db.annotationDao().getById(ANN))
        assertNull(db.readingQueueDao().getMembershipForWork(QUEUE, WORK))
        assertTrue(db.collectionDao().getWorkIdsForCollection(COLLECTION).isEmpty())
        assertFalse(files.workEpubExists(WORK))
        assertEquals(setOf("savedWork", "readingAnnotation", "readingQueueMembership"), db.syncTombstoneDao().getAll().map { it.recordTypeRaw }.toSet())
    }

    @Test
    fun workHardDeleteRollsBackWhenItsSecondTombstoneDaoStatementThrows() = runTest {
        seed()
        db.openHelper.writableDatabase.execSQL("""
            CREATE TRIGGER second_write BEFORE INSERT ON sync_tombstones
            WHEN NEW.recordTypeRaw = 'readingQueueMembership'
            BEGIN
                SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM sync_tombstones WHERE recordTypeRaw = 'savedWork' AND recordID = '$WORK')
                    THEN RAISE(ABORT, 'tombstoneMissing') END;
                SELECT RAISE(ABORT, 'secondStatement');
            END
        """.trimIndent())
        expectSecondStatementFailure { works.hardDelete(WORK) }
        assertNotNull(db.workDao().getById(WORK))
        assertNotNull(db.annotationDao().getById(ANN))
        assertNotNull(db.readingQueueDao().getMembershipForWork(QUEUE, WORK))
        assertTrue(db.syncTombstoneDao().getAll().isEmpty())
    }

    @Test
    fun collectionMembershipDeleteIsTombstoneFirstAndRollsBackBothDaoStatements() = runTest {
        seed()
        val before = db.collectionDao().getById(COLLECTION)
        val record = collectionMembershipRecordId(COLLECTION, WORK)
        failDelete("collection_work_cross_refs", "workId", WORK, "workCollectionMembership", record)
        expectSecondStatementFailure { works.removeFromCollection(WORK, COLLECTION) }
        assertEquals(listOf(WORK), db.collectionDao().getWorkIdsForCollection(COLLECTION))
        assertEquals(before, db.collectionDao().getById(COLLECTION))
        assertTrue(db.syncTombstoneDao().getAll().isEmpty())
        requireTombstoneBeforeDelete("collection_work_cross_refs", "workId", WORK, "workCollectionMembership", record)
        works.removeFromCollection(WORK, COLLECTION)
        assertTrue(db.collectionDao().getWorkIdsForCollection(COLLECTION).isEmpty())
        assertEquals(1, db.syncTombstoneDao().getByRecord(record, "workCollectionMembership").size)
    }

    private suspend fun seed() {
        db.workDao().upsert(SavedWork(id = WORK, title = "Work", author = "Writer", dateAdded = now, isSaved = true).toEntity())
        db.annotationDao().upsert(ReadingAnnotation(id = ANN, workID = WORK, kindRaw = "highlight", createdAt = now).toEntity())
        db.readingQueueDao().upsertQueue(ReadingQueue(id = QUEUE, name = "Queue", dateCreated = now).toEntity())
        db.readingQueueDao().upsertMembership(ReadingQueueMembership(id = MEMBER, queueID = QUEUE, workID = WORK, queuedAt = now).toEntity())
        db.collectionDao().upsert(WorkCollection(id = COLLECTION, name = "Collection", dateAdded = now).toEntity())
        db.collectionDao().addWork(CollectionWorkCrossRef(COLLECTION, WORK))
    }

    private suspend fun expectSecondStatementFailure(block: suspend () -> Unit) {
        val failure = runCatching { block() }.exceptionOrNull()
        assertNotNull("the DAO delete must throw", failure)
        val messages = generateSequence(failure) { it.cause }.map { it.message.orEmpty() }.joinToString(" ")
        assertTrue("tombstone must exist inside transaction before delete: $messages", messages.contains("secondStatement"))
        assertFalse(messages.contains("tombstoneMissing"))
    }

    private fun failDelete(table: String, column: String, id: String, type: String, record: String) =
        orderTrigger("delete_gate", table, column, id, type, record, true)

    private fun requireTombstoneBeforeDelete(table: String, column: String, id: String, type: String, record: String) {
        db.openHelper.writableDatabase.execSQL("DROP TRIGGER delete_gate")
        orderTrigger("delete_gate", table, column, id, type, record, false)
    }

    private fun orderTrigger(name: String, table: String, column: String, id: String, type: String, record: String, fail: Boolean) {
        val present = "EXISTS(SELECT 1 FROM sync_tombstones WHERE recordTypeRaw = '$type' AND recordID = '$record')"
        db.openHelper.writableDatabase.execSQL("""
            CREATE TRIGGER $name BEFORE DELETE ON $table WHEN OLD.$column = '$id'
            BEGIN
                SELECT CASE WHEN NOT $present THEN RAISE(ABORT, 'tombstoneMissing') END;
                ${if (fail) "SELECT RAISE(ABORT, 'secondStatement');" else ""}
            END
        """.trimIndent())
    }

    private companion object {
        const val WORK = "11111111-1111-4111-8111-111111111111"
        const val QUEUE = "22222222-2222-4222-8222-222222222222"
        const val COLLECTION = "33333333-3333-4333-8333-333333333333"
        const val MEMBER = "44444444-4444-4444-8444-444444444444"
        const val ANN = "55555555-5555-4555-8555-555555555555"
    }
}
