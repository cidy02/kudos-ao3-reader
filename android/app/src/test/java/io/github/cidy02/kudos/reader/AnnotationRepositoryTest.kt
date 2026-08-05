package io.github.cidy02.kudos.reader

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.data.local.KudosDatabase
import java.time.Instant
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AnnotationRepositoryTest {
    private lateinit var database: KudosDatabase
    private lateinit var repository: AnnotationRepository
    private val now: Instant = Instant.parse("2026-06-26T12:00:00Z")

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        repository = AnnotationRepository(
            dao = database.annotationDao(),
            tombstoneDao = database.syncTombstoneDao(),
            clock = { now },
            uuidFactory = { "tombstone-1" }
        )
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun deletingAHighlightRecordsATombstoneSoRestoreCannotResurrectIt() = runTest {
        val annotation = repository.addOrRecolorHighlight(
            workId = "work-1",
            locatorString = "",
            selectedText = "a passage",
            color = "yellow",
            progression = 0.1,
            spineIndex = 0
        )

        repository.deleteAnnotation(annotation.id)

        val tombstones = database.syncTombstoneDao()
            .getByRecord(annotation.id, SyncTombstoneRecordType.READING_ANNOTATION)
        assertEquals(1, tombstones.size)
        assertTrue(repository.observeForWork("work-1").first().isEmpty())
    }
}
