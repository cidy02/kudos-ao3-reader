package io.github.cidy02.kudos.reader

import android.content.Context
import android.graphics.PointF
import android.graphics.RectF
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextReplacement
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import androidx.lifecycle.viewModelScope
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.dao.AnnotationDao
import io.github.cidy02.kudos.data.local.entity.AnnotationEntity
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.reader.readium.ReaderHighlightDecorationListener
import io.github.cidy02.kudos.reader.readium.ReadiumNavigatorController
import io.github.cidy02.kudos.ui.subject.KudosTokens
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import java.util.Collections
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.navigator.DecorableNavigator
import org.readium.r2.navigator.Decoration
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Real editor/ViewModel/repository, recording DAO calls; no navigator or WebView. */
@OptIn(ExperimentalCoroutinesApi::class, ExperimentalReadiumApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w411dp-h1200dp")
class ReaderHighlightEditorTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var database: KudosDatabase
    private lateinit var recording: RecordingAnnotations
    private lateinit var model: ReaderViewModel
    private val directory = Files.createTempDirectory("kudos-highlight-editor-test").toFile()
    private val annotation = ReadingAnnotation(
        id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        workID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        kindRaw = "highlight", colorRaw = "yellow", selectedText = "A highlighted passage",
        locatorString = checkNotNull(ReaderLocatorCodec.encodeEnvelope(
            """{"href":"one.xhtml","type":"application/xhtml+xml","locations":{"position":1}}"""
        ))
    )

    @Before
    fun setUp() = runBlocking {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries().build()
        val files = WorkFileStore(directory.toPath())
        val works = WorkRepository(database, files)
        works.upsert(SavedWork(id = annotation.workID, title = "Local book", author = "Author", hasEpub = true))
        files.writeWorkEpub(annotation.workID, byteArrayOf(0x50, 0x4B, 0x03, 0x04))
        database.annotationDao().upsert(annotation.toEntity())
        recording = RecordingAnnotations(database.annotationDao())
        val preferences = object : DataStore<Preferences> {
            override val data = MutableStateFlow(emptyPreferences())
            override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences =
                transform(data.value).also { data.value = it }
        }
        model = ReaderViewModel(
            ReaderRepository(works, files, settingsProvider = { KudosSettings.Defaults }),
            ReadingLogService(database.readingLogDao()), SettingsRepository(preferences),
            AnnotationRepository(recording, database.syncTombstoneDao()), annotation.workID
        )
        awaitReading { it.highlights.any { mark -> mark.id == annotation.id } }
        Unit
    }

    @After
    fun tearDown() {
        runBlocking { model.viewModelScope.coroutineContext[Job]?.cancelAndJoin() }
        database.close()
        Dispatchers.resetMain()
        directory.deleteRecursively()
    }

    @Test
    fun knownDecorationOpensThatEditorAndConsumesTheChromeTap() {
        val listener = ReaderHighlightDecorationListener(model::openHighlight)
        var chromeVisible = false
        // Readium's cached page script calls decoration handling || ordinary tap handling.
        if (!listener.onDecorationActivated(event(annotation.id))) chromeVisible = !chromeVisible
        assertEquals(annotation.id, reading().editingAnnotationId)
        assertFalse(chromeVisible)
        assertTrue(recording.reads.isEmpty())
        assertTrue(recording.writes.isEmpty())
    }

    @Test
    fun unknownIdDoesNothingAndOtherGroupsLeaveOrdinaryTapsAvailable() {
        val listener = ReaderHighlightDecorationListener(model::openHighlight)
        var chromeVisible = false
        if (!listener.onDecorationActivated(event("missing"))) chromeVisible = !chromeVisible
        assertFalse(chromeVisible)
        assertNull(reading().editingAnnotationId)
        model.openHighlight(annotation.id)
        assertTrue(listener.onDecorationActivated(event("missing")))
        assertEquals(annotation.id, reading().editingAnnotationId)
        model.closeNoteEditor()
        assertFalse(listener.onDecorationActivated(event(annotation.id, "speech")))
        assertNull(reading().editingAnnotationId)
        assertTrue(recording.reads.isEmpty())
        assertTrue(recording.writes.isEmpty())
        assertTrue(recording.deletes.isEmpty())
    }

    @Test
    fun plainHighlightFromContentsCanBeEditedButBookmarkOnlyNavigates() = runBlocking {
        val bookmark = annotation.copy(id = "bookmark", kindRaw = "bookmark")
        database.annotationDao().upsert(bookmark.toEntity())
        awaitReading { it.bookmarks.any { mark -> mark.id == bookmark.id } }
        model.openHighlight(bookmark.id)
        assertNull(reading().editingAnnotationId)
        model.openHighlight(annotation.id)
        assertEquals(annotation.id, reading().editingAnnotationId)
        model.closeNoteEditor()
        val note = annotation.copy(id = "note", kindRaw = "note", note = "Existing note")
        database.annotationDao().upsert(note.toEntity())
        awaitReading { it.highlights.any { mark -> mark.id == note.id } }
        model.openHighlight(note.id)
        assertEquals(note.id, reading().editingAnnotationId)
    }

    @Test
    fun editorColourNoteAndConfirmedDeleteEachUseRepositoryOnceForTheSameId() {
        model.openHighlight(annotation.id)
        var pendingDelete: String? = null
        compose.setContent {
            val state by model.state.collectAsState()
            val reading = state as? ReaderUiState.Reading
            val mark = reading?.highlights?.firstOrNull { it.id == reading?.editingAnnotationId }
            if (mark != null) {
                CompositionLocalProvider(LocalKudosTokens provides
                    KudosTokens.of(ReaderTheme.Sepia, androidx.compose.ui.graphics.Color.Red)) {
                    ReaderNoteEditor(
                        mark, onCancel = model::closeNoteEditor,
                        onDone = { model.updateNote(mark.id, it); model.closeNoteEditor() },
                        onColorChange = { model.recolorHighlight(mark.id, it) },
                        onDelete = { pendingDelete = mark.id; model.closeNoteEditor() }
                    )
                }
            }
        }
        compose.onNodeWithText("Add Note").assertExists()
        compose.onNodeWithText(annotation.selectedText).assertExists()
        compose.onNodeWithText("Highlighted").assertExists()
        compose.onNodeWithText("Colour").assertExists()
        compose.onNodeWithContentDescription("Blue").performClick()
        runBlocking { awaitReading { it.highlights.single().colorRaw == "blue" } }
        assertEquals(listOf(annotation.id), recording.reads)
        assertEquals(listOf(annotation.id), recording.writes.map { it.id })
        assertEquals("blue", recording.writes.single().colorRaw)
        assertEquals(annotation.locatorString, recording.writes.single().locatorString)
        recording.clear()

        compose.onNodeWithContentDescription("Note").performTextReplacement("  My note \n")
        compose.onNodeWithContentDescription("Done").performClick()
        runBlocking { awaitReading { it.highlights.single().note == "My note" } }
        assertNull(reading().editingAnnotationId)
        assertEquals(listOf(annotation.id), recording.reads)
        assertEquals(listOf(annotation.id), recording.writes.map { it.id })
        assertEquals("blue", recording.writes.single().colorRaw)
        recording.clear()

        compose.runOnIdle { model.openHighlight(annotation.id) }
        compose.onNodeWithText("Edit Note").assertExists()
        compose.onNodeWithContentDescription("Note").performTextReplacement("Discard this draft")
        compose.onNodeWithText("Cancel").performClick()
        assertTrue(recording.reads.isEmpty())
        assertTrue(recording.writes.isEmpty())
        assertEquals("My note", reading().highlights.single().note)

        compose.runOnIdle { model.openHighlight(annotation.id) }
        compose.onNodeWithText("Delete Highlight").performClick()
        assertEquals(annotation.id, pendingDelete)
        assertTrue(recording.deletes.isEmpty()) // Existing confirmation owns the actual delete.
        compose.runOnIdle { model.deleteAnnotation(pendingDelete!!) }
        runBlocking {
            awaitReading { it.highlights.isEmpty() }
            withTimeout(5_000) {
                while (database.syncTombstoneDao().getAll().isEmpty()) delay(10)
            }
            val tombstone = database.syncTombstoneDao().getAll().single()
            assertEquals(annotation.id, tombstone.recordID)
            assertEquals(SyncTombstoneRecordType.READING_ANNOTATION, tombstone.recordTypeRaw)
            assertTrue(tombstone.signature.isNotEmpty())
        }
        assertEquals(listOf(annotation.id), recording.reads)
        assertEquals(listOf(annotation.id), recording.deletes)
        assertTrue(recording.writes.isEmpty())
        assertNull(reading().editingAnnotationId)
    }

    @Test
    fun rapidColourThenDonePreservesBothFields() = runBlocking {
        val releaseColourRead = CompletableDeferred<Unit>()
        recording.blockNextRead = releaseColourRead
        model.recolorHighlight(annotation.id, "green")
        model.updateNote(annotation.id, "Saved immediately after colour")
        assertEquals(listOf(annotation.id), recording.reads)
        releaseColourRead.complete(Unit)
        awaitReading {
            it.highlights.single().colorRaw == "green" &&
                it.highlights.single().note == "Saved immediately after colour"
        }
        assertEquals(listOf(annotation.id, annotation.id), recording.reads)
        assertEquals(listOf(annotation.id, annotation.id), recording.writes.map { it.id })
        assertTrue(recording.deletes.isEmpty())
    }

    @Test
    fun recolourDoesNotMatchAnotherIdenticalPassageOrResurrectADeletedId() = runBlocking {
        val duplicate = annotation.copy(id = "duplicate", colorRaw = "pink", note = "Keep this")
        database.annotationDao().upsert(duplicate.toEntity())
        model.recolorHighlight(annotation.id, "green")
        awaitReading { it.highlights.any { mark -> mark.id == annotation.id && mark.colorRaw == "green" } }
        assertEquals("pink", database.annotationDao().getById(duplicate.id)!!.colorRaw)
        assertEquals(listOf(annotation.id), recording.reads)
        assertEquals(listOf(annotation.id), recording.writes.map { it.id })
        database.annotationDao().deleteById(annotation.id)
        recording.clear()
        val repository = AnnotationRepository(recording, database.syncTombstoneDao())
        repository.addOrRecolorHighlight(id = annotation.id, color = "purple")
        assertEquals(listOf(annotation.id), recording.reads)
        assertTrue(recording.writes.isEmpty())
    }

    private fun reading() = model.state.value as ReaderUiState.Reading

    private suspend fun awaitReading(predicate: (ReaderUiState.Reading) -> Boolean) =
        withTimeout(5_000) { model.state.filterIsInstance<ReaderUiState.Reading>().first(predicate) }

    private fun event(id: String, group: String = ReadiumNavigatorController.DECORATION_GROUP_HIGHLIGHTS) =
        DecorableNavigator.OnActivatedEvent(
            Decoration(id, Locator.fromJSON(org.json.JSONObject(
                """{"href":"one.xhtml","type":"application/xhtml+xml"}"""
            ))!!, Decoration.Style.Highlight(android.graphics.Color.YELLOW, false)),
            group, RectF(), PointF()
        )

    private class RecordingAnnotations(private val dao: AnnotationDao) : AnnotationDao by dao {
        @Volatile var blockNextRead: CompletableDeferred<Unit>? = null
        val reads: MutableList<String> = Collections.synchronizedList(mutableListOf())
        val writes: MutableList<AnnotationEntity> = Collections.synchronizedList(mutableListOf())
        val deletes: MutableList<String> = Collections.synchronizedList(mutableListOf())

        override suspend fun getById(id: String): AnnotationEntity? {
            reads += id
            val gate = blockNextRead
            blockNextRead = null
            gate?.await()
            return dao.getById(id)
        }

        override suspend fun upsert(annotation: AnnotationEntity) {
            writes += annotation
            dao.upsert(annotation)
        }

        override suspend fun deleteById(id: String) {
            deletes += id
            dao.deleteById(id)
        }

        fun clear() { reads.clear(); writes.clear(); deletes.clear() }
    }
}
