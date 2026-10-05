package io.github.cidy02.kudos.reader

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import androidx.lifecycle.viewModelScope
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
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
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Actual menu callback → ReaderViewModel → the work page's write repository; fake transport only. */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ReaderKudosActionTest {
    private lateinit var database: KudosDatabase
    private lateinit var workRepository: WorkRepository
    private lateinit var fileStore: WorkFileStore
    private val directory = Files.createTempDirectory("kudos-reader-menu-test").toFile()
    private val models = mutableListOf<ReaderViewModel>()

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries().build()
        fileStore = WorkFileStore(directory.toPath())
        workRepository = WorkRepository(database, fileStore)
    }

    @After
    fun tearDown() {
        runBlocking { models.forEach { it.viewModelScope.coroutineContext[Job]?.cancelAndJoin() } }
        database.close()
        Dispatchers.resetMain()
        directory.deleteRecursively()
    }

    private suspend fun open(client: RecordingKudosClient, given: Boolean = false, ao3Id: Int? = 123): ReaderViewModel {
        val work = SavedWork(
            id = "22222222-2222-2222-2222-222222222222",
            title = "Imported AO3 work", author = "Author", ao3WorkID = ao3Id,
            hasGivenKudos = given, hasEpub = true, isFinished = true
        )
        workRepository.upsert(work)
        fileStore.writeWorkEpub(work.id, byteArrayOf(0x50, 0x4B, 0x03, 0x04))
        val preferences = object : DataStore<Preferences> {
            override val data = MutableStateFlow(emptyPreferences())
            override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences =
                transform(data.value).also { data.value = it }
        }
        val model = ReaderViewModel(
            repository = ReaderRepository(workRepository, fileStore, settingsProvider = { KudosSettings.Defaults }),
            readingLogService = ReadingLogService(database.readingLogDao()),
            settingsRepository = SettingsRepository(preferences),
            annotationRepository = AnnotationRepository(database.annotationDao(), database.syncTombstoneDao()),
            workId = work.id,
            writeRepository = AO3WriteRepository(client)
        )
        models += model
        withTimeout(5_000) { model.state.filterIsInstance<ReaderUiState.Reading>().first() }
        return model
    }

    private fun action(model: ReaderViewModel): ReaderFanRoundAction? {
        val state = model.state.value as ReaderUiState.Reading
        return readerKudosAction(state.endOfWork.workId, state.work.hasGivenKudos,
            model.kudosWorking.value, model::giveKudos)
    }

    @Test
    fun tapUsesExistingRepositoryOnceAndSuccessImmediatelyDisablesAndPersistsKudos() = runBlocking {
        val client = RecordingKudosClient()
        val model = open(client)
        val initial = action(model)!!
        initial.action()
        initial.action() // A stale UI callback before recomposition must also be safe.
        withTimeout(5_000) { client.postStarted.await() }
        assertTrue(model.kudosWorking.value)
        assertFalse(action(model)!!.isEnabled)
        assertEquals(1, client.gets.size)
        assertEquals(1, client.posts.size)
        assertEquals("https://archiveofourown.org/kudos.js", client.posts.single().first)
        assertTrue(client.posts.single().second.contains("kudo[commentable_id]" to "123"))
        client.response.complete(AO3Result.Success(AO3HttpResponse(
            url = "https://archiveofourown.org/kudos.js", statusCode = 200,
            headers = emptyMap(), body = "ok"
        )))
        withTimeout(5_000) { model.kudosWorking.first { !it } }
        assertEquals("Kudos left.", model.writeMessage.value)
        assertEquals("Kudos given", action(model)!!.accessibilityLabel)
        assertTrue(action(model)!!.isEmphasized)
        assertFalse(action(model)!!.isEnabled)
        val state = model.state.value as ReaderUiState.Reading
        assertTrue(workRepository.getWork(state.work.id)!!.hasGivenKudos)
        initial.action()
        assertEquals(1, client.posts.size)
    }

    @Test
    fun signedOutTapKeepsTheActionVisibleAndShowsIosWordsWithoutPosting() = runBlocking {
        val client = RecordingKudosClient(readError = AO3Error.AuthenticationRequired)
        val model = open(client)
        assertTrue(action(model)!!.isEnabled)
        action(model)!!.action()
        withTimeout(5_000) { model.kudosWorking.first { !it } }
        assertEquals("Log in to AO3 first.", model.writeMessage.value)
        assertTrue(client.posts.isEmpty())
        assertFalse((model.state.value as ReaderUiState.Reading).work.hasGivenKudos)
    }

    @Test
    fun failedWriteDoesNotRetryOrMarkKudosGivenAndAllowsAnotherExplicitTap() = runBlocking {
        val client = RecordingKudosClient()
        val model = open(client)
        action(model)!!.action()
        withTimeout(5_000) { client.postStarted.await() }
        client.response.complete(AO3Result.Failure(AO3Error.Validation("AO3 didn't accept the kudos.")))
        withTimeout(5_000) { model.kudosWorking.first { !it } }
        assertEquals("AO3 didn't accept the kudos.", model.writeMessage.value)
        assertEquals(1, client.posts.size)
        assertFalse((model.state.value as ReaderUiState.Reading).work.hasGivenKudos)
        assertTrue(action(model)!!.isEnabled)
        action(model)!!.action()
        withTimeout(5_000) { model.kudosWorking.first { !it } }
        assertEquals(2, client.posts.size)
    }

    @Test
    fun importWithoutAo3IdentityAndAlreadyGivenStateCannotDispatchEvenThroughViewModel() = runBlocking {
        val client = RecordingKudosClient()
        val imported = open(client, ao3Id = null)
        assertEquals(null, action(imported))
        imported.giveKudos()
        val given = open(client, given = true)
        assertFalse(action(given)!!.isEnabled)
        given.giveKudos()
        assertTrue(client.gets.isEmpty())
        assertTrue(client.posts.isEmpty())
    }
}

private class RecordingKudosClient(private val readError: AO3Error? = null) : AO3AuthenticatedClient {
    val gets = mutableListOf<String>()
    val posts = mutableListOf<Pair<String, List<Pair<String, String>>>>()
    val postStarted = CompletableDeferred<Unit>()
    val response = CompletableDeferred<AO3Result<AO3HttpResponse>>()

    override fun username(): String? = if (readError == AO3Error.AuthenticationRequired) null else "Reader"

    override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> {
        gets += url
        readError?.let { return AO3Result.Failure(it) }
        return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(),
            """<input name="authenticity_token" value="recording-token">"""))
    }

    override suspend fun postAuthenticated(
        url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> {
        posts += url to formFields
        postStarted.complete(Unit)
        return response.await()
    }
}
