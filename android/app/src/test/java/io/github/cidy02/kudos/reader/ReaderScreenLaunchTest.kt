package io.github.cidy02.kudos.reader

import android.app.Application
import android.content.Context
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.lifecycle.ViewModelStore
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.work.Configuration
import androidx.work.WorkManager
import io.github.cidy02.kudos.app.ReaderLaunchRequest
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.FileWriteResult
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.reader.readium.ReadiumOpenResult
import io.github.cidy02.kudos.reader.speech.SpeechStatus
import io.github.cidy02.kudos.reader.speech.TTSDownloadWorker
import io.github.cidy02.kudos.reader.speech.TTSService
import io.github.cidy02.kudos.reader.speech.TTSVoice
import io.github.cidy02.kudos.works.WorkRepository
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Manifest
import org.readium.r2.shared.publication.Metadata
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.content.Content
import org.readium.r2.shared.publication.services.content.ContentService
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1200dp")
@OptIn(ExperimentalReadiumApi::class)
class ReaderScreenLaunchTest {
    @get:Rule val compose = createComposeRule()

    private lateinit var context: Context
    private lateinit var tempDir: File
    private lateinit var database: KudosDatabase
    private lateinit var fileStore: WorkFileStore
    private lateinit var workRepository: WorkRepository
    private lateinit var settingsScope: CoroutineScope
    private lateinit var settingsRepository: SettingsRepository
    private lateinit var readerRepository: ReaderRepository
    private lateinit var readingLogService: ReadingLogService
    private lateinit var annotationRepository: AnnotationRepository

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        try {
            WorkManager.getInstance(context)
        } catch (_: IllegalStateException) {
            WorkManager.initialize(context, Configuration.Builder().build())
        }
        TTSDownloadWorker.modelDirectory(context).deleteRecursively()
        tempDir = Files.createTempDirectory("kudos-reader-launch-test").toFile()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries().build()
        fileStore = WorkFileStore(File(tempDir, "files").toPath())
        workRepository = WorkRepository(database, fileStore)
        settingsScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        settingsRepository = SettingsRepository(
            PreferenceDataStoreFactory.create(scope = settingsScope) {
                File(tempDir, "settings.preferences_pb")
            }
        )
        readerRepository = ReaderRepository(workRepository, fileStore, { KudosSettings.Defaults })
        readingLogService = ReadingLogService(database.readingLogDao())
        annotationRepository = AnnotationRepository(database.annotationDao(), database.syncTombstoneDao())
    }

    private val workIdVoice = "00000000-0000-4000-8000-000000000001"
    private val workIdNoVoice = "00000000-0000-4000-8000-000000000002"
    private val workIdClosePub = "00000000-0000-4000-8000-000000000003"
    private val workIdCloseTts = "00000000-0000-4000-8000-000000000004"
    private val workIdCloseError = "00000000-0000-4000-8000-000000000005"

    @After
    fun tearDown() {
        ReaderLaunchRequest.consume(workIdVoice)
        ReaderLaunchRequest.consume(workIdNoVoice)
        ReaderLaunchRequest.consume(workIdClosePub)
        ReaderLaunchRequest.consume(workIdCloseTts)
        ReaderLaunchRequest.consume(workIdCloseError)
        database.close()
        settingsScope.cancel()
        tempDir.deleteRecursively()
    }

    @Test
    fun readerScreenWaitsForLateTtsWithVoiceThenStartsReadingOnce() {
        val workId = workIdVoice
        prepareWork(workId)
        val tts = LateFakeTTSService()
        val viewModel = newViewModel(workId)
        var shown by mutableStateOf(true)
        var opened by mutableStateOf(false)
        val opener: suspend (File) -> ReadiumOpenResult = {
            opened = true
            ReadiumOpenResult.Success(fakePublication("First paragraph."))
        }
        ReaderLaunchRequest.request(workId, startReadAloud = true)

        try {
            compose.setContent {
                MaterialTheme {
                    if (shown) {
                        ReaderScreen(
                            viewModel = viewModel,
                            onBack = { shown = false },
                            onOpenComments = { _, _ -> },
                            onOpenWorkDetail = {},
                            settingsRepository = settingsRepository,
                            openPublication = opener,
                            ttsService = tts
                        )
                    }
                }
            }
            awaitReaderOpened { opened }

            // Still resolving: launch request stays pending and speech has not started or prompted.
            assertEquals(0, tts.spoken.size)
            assertNotNull(ReaderLaunchRequest.peek(workId))
            compose.onNodeWithText("High-quality voice model needed (~45MB)").assertDoesNotExist()

            // Device voice binds late: ReaderScreen consumes the request and speaks once.
            compose.runOnIdle { tts.status.value = SpeechStatus.STOPPED }
            awaitCondition { tts.spoken.size == 1 && ReaderLaunchRequest.peek(workId) == null }
            compose.waitForIdle()
            assertEquals(listOf("First paragraph."), tts.spoken)
            assertNull(ReaderLaunchRequest.peek(workId))
            compose.onNodeWithText("High-quality voice model needed (~45MB)").assertDoesNotExist()
        } finally {
            compose.runOnIdle { shown = false }
            compose.waitForIdle()
        }
    }

    @Test
    fun readerScreenWaitsForLateTtsWithoutVoiceThenShowsModelPrompt() {
        val workId = workIdNoVoice
        prepareWork(workId)
        val tts = LateFakeTTSService()
        val viewModel = newViewModel(workId)
        var shown by mutableStateOf(true)
        var opened by mutableStateOf(false)
        val opener: suspend (File) -> ReadiumOpenResult = {
            opened = true
            ReadiumOpenResult.Success(fakePublication("Story text."))
        }
        ReaderLaunchRequest.request(workId, startReadAloud = true)

        try {
            compose.setContent {
                MaterialTheme {
                    if (shown) {
                        ReaderScreen(
                            viewModel = viewModel,
                            onBack = { shown = false },
                            onOpenComments = { _, _ -> },
                            onOpenWorkDetail = {},
                            settingsRepository = settingsRepository,
                            openPublication = opener,
                            ttsService = tts
                        )
                    }
                }
            }
            awaitReaderOpened { opened }

            // Still resolving: neither spoken nor prompted yet.
            assertEquals(0, tts.spoken.size)
            assertNotNull(ReaderLaunchRequest.peek(workId))
            compose.onNodeWithText("High-quality voice model needed (~45MB)").assertDoesNotExist()

            // System TTS finishes binding without an on-device voice -> MODEL_NOT_DOWNLOADED.
            compose.runOnIdle { tts.status.value = SpeechStatus.UNAVAILABLE }
            compose.waitUntil(5_000) {
                compose.onAllNodesWithText("High-quality voice model needed (~45MB)")
                    .fetchSemanticsNodes().isNotEmpty()
            }
            assertEquals(0, tts.spoken.size)
            assertNull(ReaderLaunchRequest.peek(workId))
        } finally {
            compose.runOnIdle { shown = false }
            compose.waitForIdle()
        }
    }

    @Test
    fun closingReaderBeforePublicationOpensClearsLaunchRequestAndNeverStartsLater() {
        val workId = workIdClosePub
        prepareWork(workId)
        val openGate = CompletableDeferred<ReadiumOpenResult>()
        val tts = LateFakeTTSService(SpeechStatus.STOPPED)
        val firstStore = ViewModelStore()
        val reopenedStore = ViewModelStore()
        val firstVm = newViewModel(workId)
        firstStore.put("first-$workId", firstVm)
        val reopenedVm = newViewModel(workId)
        reopenedStore.put("reopened-$workId", reopenedVm)
        var firstOpenStarted by mutableStateOf(false)
        var reopenedOpened by mutableStateOf(false)
        val firstOpener: suspend (File) -> ReadiumOpenResult = {
            firstOpenStarted = true
            openGate.await()
        }
        val reopenedOpener: suspend (File) -> ReadiumOpenResult = {
            reopenedOpened = true
            ReadiumOpenResult.Success(fakePublication("Reopened."))
        }
        var active by mutableStateOf<Pair<ReaderViewModel, suspend (File) -> ReadiumOpenResult>?>(
            firstVm to firstOpener
        )
        ReaderLaunchRequest.request(workId, startReadAloud = true)

        try {
            compose.setContent {
                MaterialTheme {
                    active?.let { (vm, opener) ->
                        ReaderScreen(
                            viewModel = vm,
                            onBack = { active = null },
                            onOpenComments = { _, _ -> },
                            onOpenWorkDetail = {},
                            settingsRepository = settingsRepository,
                            openPublication = opener,
                            ttsService = tts
                        )
                    }
                }
            }
            compose.waitUntil(5_000) {
                compose.onAllNodesWithContentDescription("Opening “Work $workId”…")
                    .fetchSemanticsNodes().isNotEmpty() && firstOpenStarted
            }

            // Simulate system back popping the NavBackStackEntry before Readium finishes opening.
            compose.runOnIdle {
                active = null
                firstStore.clear()
            }
            compose.waitForIdle()
            openGate.complete(ReadiumOpenResult.Success(fakePublication("Late chapter.")))
            compose.waitForIdle()

            assertNull(ReaderLaunchRequest.peek(workId))
            assertEquals(0, tts.spoken.size)

            // Re-opening the same work later without Read Aloud must not fire the stale request.
            compose.runOnIdle {
                active = reopenedVm to reopenedOpener
            }
            awaitReaderOpened { reopenedOpened }
            assertEquals(0, tts.spoken.size)
            compose.onNodeWithText("High-quality voice model needed (~45MB)").assertDoesNotExist()
        } finally {
            openGate.cancel()
            compose.runOnIdle { active = null }
            compose.waitForIdle()
            firstStore.clear()
            reopenedStore.clear()
        }
    }

    @Test
    fun closingReaderWhileTtsIsStillResolvingClearsLaunchRequestAndNeverSpeaksLater() {
        val workId = workIdCloseTts
        prepareWork(workId)
        val tts = LateFakeTTSService(SpeechStatus.RESOLVING)
        val store = ViewModelStore()
        val viewModel = newViewModel(workId)
        store.put(workId, viewModel)
        var shown by mutableStateOf(true)
        var opened by mutableStateOf(false)
        val opener: suspend (File) -> ReadiumOpenResult = {
            opened = true
            ReadiumOpenResult.Success(fakePublication("Should not speak."))
        }
        ReaderLaunchRequest.request(workId, startReadAloud = true)

        try {
            compose.setContent {
                MaterialTheme {
                    if (shown) {
                        ReaderScreen(
                            viewModel = viewModel,
                            onBack = { shown = false },
                            onOpenComments = { _, _ -> },
                            onOpenWorkDetail = {},
                            settingsRepository = settingsRepository,
                            openPublication = opener,
                            ttsService = tts
                        )
                    }
                }
            }
            awaitReaderOpened { opened }
            assertNotNull(ReaderLaunchRequest.peek(workId))
            assertEquals(0, tts.spoken.size)

            compose.runOnIdle {
                shown = false
                store.clear()
            }
            compose.waitForIdle()

            // Late TTS resolution after reader left must never trigger speech or leave a request behind.
            tts.status.value = SpeechStatus.STOPPED
            compose.waitForIdle()
            assertNull(ReaderLaunchRequest.peek(workId))
            assertEquals(0, tts.spoken.size)
        } finally {
            store.clear()
        }
    }

    @Test
    fun backingOutFromReaderErrorClearsLaunchRequestViaOnBack() {
        val workId = workIdCloseError
        prepareWork(workId)
        val tts = LateFakeTTSService(SpeechStatus.STOPPED)
        val viewModel = newViewModel(workId)
        var shown by mutableStateOf(true)
        val opener: suspend (File) -> ReadiumOpenResult = {
            ReadiumOpenResult.Failure(ReaderError.OpenFailed("Corrupt EPUB"))
        }
        ReaderLaunchRequest.request(workId, openContents = true, startReadAloud = true)

        try {
            compose.setContent {
                MaterialTheme {
                    if (shown) {
                        ReaderScreen(
                            viewModel = viewModel,
                            onBack = { shown = false },
                            onOpenComments = { _, _ -> },
                            onOpenWorkDetail = {},
                            settingsRepository = settingsRepository,
                            openPublication = opener,
                            ttsService = tts
                        )
                    }
                }
            }
            compose.waitUntil(5_000) {
                compose.onAllNodesWithText("Corrupt EPUB").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("Back").performClick()
            compose.waitForIdle()

            assertNull(ReaderLaunchRequest.peek(workId))
            assertEquals(0, tts.spoken.size)
        } finally {
            compose.runOnIdle { shown = false }
            compose.waitForIdle()
        }
    }

    private fun awaitCondition(condition: () -> Boolean) {
        compose.waitUntil(5_000) {
            compose.onAllNodes(isRoot()).fetchSemanticsNodes()
            condition()
        }
    }

    private fun awaitReaderOpened(opened: () -> Boolean) {
        awaitCondition {
            compose.onAllNodesWithContentDescription("Opening", substring = true)
                .fetchSemanticsNodes().isEmpty() && opened()
        }
        compose.waitForIdle()
    }

    private fun prepareWork(workId: String) {
        runBlocking {
            workRepository.upsert(
                SavedWork(
                    id = workId,
                    title = "Work $workId",
                    author = "Author",
                    hasEpub = true,
                    isSaved = true
                )
            )
            val result = fileStore.writeWorkEpub(workId, byteArrayOf(0x50, 0x4B, 0x03, 0x04, 1, 2, 3))
            assertTrue(result is FileWriteResult.Success)
        }
    }

    private fun newViewModel(workId: String) = ReaderViewModel(
        repository = readerRepository,
        readingLogService = readingLogService,
        settingsRepository = settingsRepository,
        annotationRepository = annotationRepository,
        workId = workId
    )

    private fun fakePublication(paragraph: String): Publication {
        val location = Locator.fromJSON(
            org.json.JSONObject("""{"href":"ch1.xhtml","type":"application/xhtml+xml"}""")
        )!!
        val element = Content.TextElement(
            locator = location,
            role = Content.TextElement.Role.Body,
            segments = listOf(Content.TextElement.Segment(location, paragraph, emptyList())),
            attributes = emptyList()
        )
        return Publication(
            manifest = Manifest(metadata = Metadata()),
            servicesBuilder = Publication.ServicesBuilder(
                content = {
                    object : ContentService {
                        override fun content(from: Locator?): Content = object : Content {
                            override fun iterator(): Content.Iterator = object : Content.Iterator {
                                var index = 0
                                override suspend fun hasNext(): Boolean = index == 0
                                override fun next(): Content.Element {
                                    index++
                                    return element
                                }
                                override suspend fun hasPrevious(): Boolean = index > 0
                                override fun previous(): Content.Element {
                                    index--
                                    return element
                                }
                            }
                        }
                    }
                }
            )
        )
    }

    private class LateFakeTTSService(
        initialStatus: SpeechStatus = SpeechStatus.RESOLVING
    ) : TTSService {
        override val status = MutableStateFlow(initialStatus)
        override val spokenText = MutableStateFlow("")
        override val availableVoices = MutableStateFlow(emptyList<TTSVoice>())
        val spoken = mutableListOf<String>()

        override suspend fun speak(text: String) {
            spoken += text
            spokenText.value = text
            status.value = SpeechStatus.PLAYING
            status.value = SpeechStatus.STOPPED
        }

        override fun pause() {
            status.value = SpeechStatus.PAUSED
        }

        override fun resume() {
            status.value = SpeechStatus.PLAYING
        }

        override fun stop() {
            if (status.value != SpeechStatus.UNAVAILABLE && status.value != SpeechStatus.RESOLVING) {
                status.value = SpeechStatus.STOPPED
            }
        }

        override fun setVoice(id: String) = Unit
        override fun setRate(rate: Float) = Unit
        override fun setPitch(pitch: Float) = Unit
    }
}
