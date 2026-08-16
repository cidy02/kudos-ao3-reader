package io.github.cidy02.kudos.reader

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.backup.BackupAnnotation
import io.github.cidy02.kudos.backup.BackupExportedBy
import io.github.cidy02.kudos.backup.BackupImportMode
import io.github.cidy02.kudos.backup.BackupRepository
import io.github.cidy02.kudos.backup.BackupSettingsPayload
import io.github.cidy02.kudos.backup.BackupVersion
import io.github.cidy02.kudos.backup.BackupWork
import io.github.cidy02.kudos.backup.KudosBackupManifest
import io.github.cidy02.kudos.backup.KudosBackupPackage
import io.github.cidy02.kudos.backup.PersistenceGate
import io.github.cidy02.kudos.backup.TombstoneSigning
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
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
 * Production-entry coverage for annotation delete tombstones.
 *
 * [AnnotationRepository.deleteAnnotation] is the reader delete path.
 * Folder sync ingest is [BackupRepository.importPackage] (default RECONCILE).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AnnotationTombstoneTest {
    private lateinit var context: Context
    private lateinit var database: KudosDatabase
    private lateinit var settingsScope: CoroutineScope
    private lateinit var settingsRepository: SettingsRepository
    private lateinit var backupRepository: BackupRepository
    private lateinit var annotationRepository: AnnotationRepository

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        settingsScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val settingsDir = Files.createTempDirectory("kudos-ann-settings").toFile()
        settingsRepository = SettingsRepository(
            PreferenceDataStoreFactory.create(
                scope = settingsScope,
                produceFile = { File(settingsDir, "settings.preferences_pb") }
            )
        )
        val filesRoot = Files.createTempDirectory("kudos-ann-files")
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
        annotationRepository = AnnotationRepository(
            dao = database.annotationDao(),
            tombstoneDao = database.syncTombstoneDao(),
            clock = { CLOCK },
            uuidFactory = { TOMBSTONE_ID }
        )
    }

    @After
    fun tearDown() {
        database.close()
        settingsScope.cancel()
        TombstoneSigning.resetForTests()
    }

    @Test
    fun deleteAnnotationMintsTombstoneAndFolderSyncDoesNotResurrect() = runTest {
        database.workDao().upsert(
            SavedWork(
                id = WORK_ID,
                title = "Work",
                author = "Author",
                sourceUrl = "https://archiveofourown.org/works/4242",
                dateAdded = ANNOTATION_CREATED,
                lastModifiedAt = ANNOTATION_CREATED,
                isSaved = true
            ).toEntity()
        )
        database.annotationDao().upsert(
            ReadingAnnotation(
                id = ANN_ID,
                workID = WORK_ID,
                kindRaw = "highlight",
                colorRaw = "yellow",
                locatorString = """{"href":"ch1"}""",
                selectedText = "deleted later",
                note = "keep me gone",
                createdAt = ANNOTATION_CREATED,
                lastModifiedAt = ANNOTATION_CREATED
            ).toEntity()
        )

        annotationRepository.deleteAnnotation(ANN_ID)

        assertNull(
            "deleteAnnotation must remove the highlight",
            database.annotationDao().getById(ANN_ID)
        )

        val summary = backupRepository.importPackage(
            packageWithWorkAndAnnotation(),
            BackupImportMode.RECONCILE
        )

        assertNull(
            "folder-sync RECONCILE must not resurrect a locally deleted highlight",
            database.annotationDao().getById(ANN_ID)
        )
        assertEquals(
            "deleted highlight must be suppressed by the minted tombstone",
            1,
            summary.annotationsSuppressed
        )
        val minted = database.syncTombstoneDao().getAll().filter {
            it.recordTypeRaw == SyncTombstoneRecordType.READING_ANNOTATION &&
                it.recordID == ANN_ID
        }
        assertEquals(
            "deleteAnnotation must mint a readingAnnotation tombstone",
            1,
            minted.size
        )
        assertEquals(TOMBSTONE_ID, minted.single().id)
        assertEquals(CLOCK, minted.single().createdAt)
        assertEquals(CLOCK, minted.single().lastModifiedAt)
        assertTrue(minted.single().signature.isNotEmpty())
    }

    private fun packageWithWorkAndAnnotation(): KudosBackupPackage {
        return KudosBackupPackage(
            manifest = KudosBackupManifest(
                version = BackupVersion.CURRENT,
                exportedAt = "2026-06-01T00:00:00Z",
                exportedBy = BackupExportedBy(
                    platform = "android",
                    appVersion = "test",
                    schemaVersion = BackupVersion.CURRENT
                ),
                works = listOf(
                    BackupWork(
                        id = WORK_ID,
                        title = "Work",
                        author = "Author",
                        sourceURL = "https://archiveofourown.org/works/4242",
                        dateAdded = "2026-01-01T00:00:00Z",
                        isSaved = true,
                        hasEPUB = true,
                        lastModifiedAt = "2026-01-01T00:00:00Z",
                        ao3WorkID = 4242
                    )
                ),
                annotations = listOf(
                    BackupAnnotation(
                        id = ANN_ID,
                        workID = WORK_ID,
                        kindRaw = "highlight",
                        colorRaw = "yellow",
                        locatorString = """{"href":"ch1"}""",
                        selectedText = "deleted later",
                        note = "keep me gone",
                        createdAt = "2026-01-01T00:00:00Z",
                        lastModifiedAt = "2026-01-01T00:00:00Z"
                    )
                ),
                settings = BackupSettingsPayload()
            ),
            epubFilesByWorkId = mapOf(WORK_ID to "epub".toByteArray())
        )
    }

    companion object {
        private val CLOCK: Instant = Instant.parse("2026-06-26T12:00:00Z")
        private val ANNOTATION_CREATED: Instant = Instant.parse("2026-01-01T00:00:00Z")
        private const val WORK_ID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        private const val ANN_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        private const val TOMBSTONE_ID = "33333333-3333-4333-8333-333333333333"
    }
}
