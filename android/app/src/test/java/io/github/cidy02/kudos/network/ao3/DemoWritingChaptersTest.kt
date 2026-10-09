package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.auth.*
import io.github.cidy02.kudos.network.ao3.writes.*
import io.github.cidy02.kudos.network.ao3.writing.*
import io.github.cidy02.kudos.writing.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class DemoWritingChaptersTest {
    private val source = FixtureSource { name ->
        listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
            .map { File("$it/fixtures/$name.html") }.firstOrNull(File::isFile)?.readBytes()
    }

    @Test fun bothWorksSaveUpdatePostPreviewAndDeleteLocallyAndTheIndexReflectsEachConfirmation() = runTest {
        for (work in listOf(995006L, 995001L)) {
            val setup = setup()
            val original = (setup.repository.loadChapters(work) as AO3Result.Success).value
            if (work == 995001L) {
                // AO3 refuses deleting the only posted chapter, even alongside a draft.
                val first = setup.model(work, original.single().chapterId).also { it.load() }
                first.save(AO3WorkSubmitAction.PostWithoutPreview)
                assertTrue(first.state.value.finished)
            }
            val new = setup.model(work, null).also { it.load() }
            new.title("Original midnight tide")
            new.openPreview()
            assertNotNull(new.state.value.preview); assertNotNull(new.state.value.form!!.chapterID)
            assertEquals(original.size + 1, (setup.repository.loadChapters(work) as AO3Result.Success).value.size)
            val id = new.state.value.form!!.chapterID!!
            new.save(AO3WorkSubmitAction.Post)
            assertTrue(new.state.value.finished)
            val posted = setup.model(work, id).also { it.load() }
            assertFalse(posted.state.value.form!!.isDraft)
            posted.title("Changed midnight tide"); posted.save(AO3WorkSubmitAction.Update)
            assertTrue(posted.state.value.finished)
            assertTrue((setup.repository.loadChapters(work) as AO3Result.Success).value.any { "Changed midnight tide" in it.displayName })
            val deletion = setup.model(work, id).also { it.load() }
            deletion.deleteChapter(confirmed = true)
            assertTrue(deletion.state.value.finished)
            assertEquals(original.size, (setup.repository.loadChapters(work) as AO3Result.Success).value.size)
            assertTrue((setup.repository.loadChapters(work) as AO3Result.Success).value.none { it.chapterId == id })
        }
    }

    @Test fun refusalKeepsBothServerAndFormAndWorkTotalFailureRetriesOnlyTheTotal() = runTest {
        val setup = setup()
        val new = setup.model(995006, null).also { it.load() }
        new.title("Refuse this chapter")
        val before = new.state.value.form
        new.save(AO3WorkSubmitAction.SaveDraft)
        assertEquals("Title is too long (maximum is 255 characters)", new.state.value.saveError)
        assertEquals(before, new.state.value.form)
        assertEquals(2, (setup.repository.loadChapters(995006) as AO3Result.Success).value.size)
        new.title("Fail total once"); new.lastChapter(true)
        new.save(AO3WorkSubmitAction.SaveDraft)
        assertEquals("The chapter was saved, but the work total was not updated. Expected chapter total could not be updated.", new.state.value.saveError)
        assertFalse(new.state.value.finished); assertTrue(new.state.value.chapterSaved)
        assertEquals(3, (setup.repository.loadChapters(995006) as AO3Result.Success).value.size)
        new.save(AO3WorkSubmitAction.Update)
        assertTrue(new.state.value.finished)
        assertEquals(3, (setup.repository.loadChapters(995006) as AO3Result.Success).value.size)
        assertEquals("3", (setup.repository.loadWorkForm(995006) as AO3Result.Success).value.chapterTotal)
    }

    @Test fun totalsSucceedForDraftAndPostedWorkAndAProcessRestartResetsLocalChapters() = runTest {
        for (work in listOf(995006L, 995001L)) {
            val setup = setup()
            val model = setup.model(work, null).also { it.load() }
            model.title("Last lantern"); model.lastChapter(true); model.save(AO3WorkSubmitAction.SaveDraft)
            assertTrue(model.state.value.finished)
            assertEquals(model.state.value.form!!.position, (setup.repository.loadWorkForm(work) as AO3Result.Success).value.chapterTotal)
            val reset = setup()
            assertEquals(if (work == 995006L) 2 else 1, (reset.repository.loadChapters(work) as AO3Result.Success).value.size)
        }
    }

    @Test fun missingAssetsAndInvalidTokenTerminateLocally() = runTest {
        val missing = setup(FixtureSource { null })
        assertTrue(missing.repository.loadChapterForm(995006, null) is AO3Result.Failure)
        val setup = setup()
        val form = (setup.repository.loadChapterForm(995006, null) as AO3Result.Success).value
        assertEquals(AO3Result.Failure(AO3Error.Validation("Invalid authenticity token")),
            setup.writes.saveChapter(form.copy(csrfToken = "wrong"), AO3WorkSubmitAction.SaveDraft, setup.auth.generation.value))
        assertEquals(2, (setup.repository.loadChapters(995006) as AO3Result.Success).value.size)
    }

    private suspend fun setup(fixtures: FixtureSource = source): DemoChapterSetup {
        val http = OkHttpClient.Builder().addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = { fixtures }))
            .addInterceptor { error("Demo chapters must never reach a socket") }.build()
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore()).also { it.restoreSession() }
        val client = OkHttpAO3Client(http, AO3NetworkConfig(minDelayBetweenRequestsMillis = 0))
        val authenticated = DefaultAO3AuthenticatedClient(client, client, auth)
        return DemoChapterSetup(auth, AO3WorkFormRepository(authenticated, auth, parseDispatcher = Dispatchers.Unconfined), AO3WriteRepository(authenticated))
    }
}

private data class DemoChapterSetup(val auth: AO3AuthRepository, val repository: AO3WorkFormRepository, val writes: AO3WriteRepository) {
    fun model(work: Long, chapter: Long?) = WritingChapterFormState(work, chapter, if (chapter == null) null else 3, repository, auth, writes = writes)
}
