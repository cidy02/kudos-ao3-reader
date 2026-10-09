package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields
import io.github.cidy02.kudos.network.ao3.writing.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class WritingChapterDeleteTest {
    @Test fun deleteRequiresConfirmationThenOneGetOneExactPostAndNoSubmitOrTotal() = runTest {
        val setup = workFormSetup(); val model = setup.chapter("posted").also { it.load() }
        model.deleteChapter()
        assertEquals(1, setup.client.gets.size); assertEquals(0, setup.client.posts)
        setup.client.body = workFixture("ao3_demo_chapter_995006_delete")
        model.deleteChapter(confirmed = true)
        assertEquals(listOf(AO3ChapterUrls.form(995006, 12302), AO3ChapterUrls.confirmDelete(995006, 12302)), setup.client.gets)
        val post = setup.client.recordedPosts.single()
        assertEquals(AO3ChapterUrls.chapter(995006, 12302), post.url)
        assertEquals(listOf("authenticity_token" to "demo-delete-995006==", "_method" to "delete"), post.fields)
        assertEquals(post.url, post.headers["Referer"]); assertEquals("demo-delete-995006==", post.headers["X-CSRF-Token"])
        assertTrue(model.state.value.finished); assertEquals(1, model.state.value.savedRevision)
        model.deleteChapter(confirmed = true); assertEquals(1, setup.client.posts)
    }

    @Test fun newOnlyOrUnknownCountDeletesNothing() = runTest {
        for ((kind, count) in listOf("new" to 2, "posted" to 1, "draft" to null)) {
            val setup = workFormSetup(); setup.client.body = workFixture("ao3_demo_chapter_995006_$kind")
            val model = WritingChapterFormState(995006, if (kind == "new") null else 12302, count,
                setup.repository, setup.auth, writes = setup.writes).also { it.load() }
            model.deleteChapter(confirmed = true)
            assertEquals(1, setup.client.gets.size); assertEquals(0, setup.client.posts)
        }
    }

    @Test fun refusalUnconfirmedAndPreparationFailureRetainEveryTypedFieldAndNeverRefresh() = runTest {
        for ((body, error) in listOf("<main id=main><div class='flash error'>You cannot delete the only posted chapter of a work.</div></main>" to "You cannot delete the only posted chapter of a work.",
            "<main></main>" to AO3CollectionFields.UNCONFIRMED)) {
            val setup = workFormSetup(); val model = setup.chapter("posted").also { it.load() }
            model.checkpoint(ChapterFormText.Content, "retained & 星"); val form = model.state.value.form
            setup.client.body = workFixture("ao3_demo_chapter_995006_delete"); setup.client.postBody = body
            model.deleteChapter(confirmed = true)
            assertEquals(if (error == AO3CollectionFields.UNCONFIRMED) error else "The chapter was not deleted. $error", model.state.value.saveError)
            assertFalse(model.state.value.busy)
            assertEquals(form, model.state.value.form); assertEquals(0, model.state.value.savedRevision); assertFalse(model.state.value.finished)
            assertEquals(1, setup.client.posts); assertEquals(2, setup.client.gets.size)
        }
        val setup = workFormSetup(); val model = setup.chapter("posted").also { it.load() }; val form = model.state.value.form
        setup.client.failure = AO3Error.Forbidden; model.deleteChapter(confirmed = true)
        assertEquals("The chapter was not deleted. " + workFormFailure(AO3Error.Forbidden), model.state.value.saveError)
        assertEquals(form, model.state.value.form); assertEquals(0, setup.client.posts)
    }

    @Test fun secondTapWhileConfirmReadOrPostIsHeldSendsNothingAndChangedSessionCannotDelete() = runTest {
        val setup = workFormSetup(); val model = setup.chapter("posted").also { it.load() }
        setup.client.body = workFixture("ao3_demo_chapter_995006_delete")
        val release = CompletableDeferred<Unit>(); setup.client.beforeResponse = { release.await() }
        val deletion = async { model.deleteChapter(confirmed = true) }; runCurrent()
        model.deleteChapter(confirmed = true)
        assertEquals(2, setup.client.gets.size); assertEquals(0, setup.client.posts)
        setup.auth.logout(); release.complete(Unit); deletion.await()
        assertEquals(CHAPTER_DELETE_SESSION_CHANGED, model.state.value.saveError); assertEquals(0, setup.client.posts)
        assertFalse(model.state.value.finished); assertFalse(model.state.value.busy)
    }

    /**
     * The half the test above names and never ran (audit A28-5): the delete POST is out and the writer
     * taps again. Only the confirmation read was ever held there, so a busy flag released after that
     * read, which would let a second delete go out, passed.
     */
    @Test fun secondTapWhileTheDeletePostIsHeldSendsExactlyOneDelete() = runTest {
        val setup = workFormSetup(); val model = setup.chapter("posted").also { it.load() }
        setup.client.body = workFixture("ao3_demo_chapter_995006_delete")
        setup.client.postBody = "<main id=main><div class='flash notice'>The chapter was deleted.</div></main>"
        val release = CompletableDeferred<Unit>(); setup.client.beforePostResponse = { release.await() }
        val deletion = async { model.deleteChapter(confirmed = true) }
        // The confirmation page is parsed off the test's clock: wait in real time for the POST to go out.
        for (attempt in 1..500) { runCurrent(); if (setup.client.posts == 1) break; Thread.sleep(10) }
        assertEquals(1, setup.client.posts); assertTrue(model.state.value.busy)
        val reads = setup.client.gets.size
        model.deleteChapter(confirmed = true); model.save(AO3WorkSubmitAction.Update); model.openPreview(); runCurrent()
        assertEquals(1, setup.client.posts); assertEquals(reads, setup.client.gets.size)
        release.complete(Unit); deletion.await()
        assertEquals(1, setup.client.posts); assertTrue(model.state.value.finished); assertFalse(model.state.value.busy)
    }

    @Test fun changedSessionAfterDeletePostReturnsUnconfirmedAloneAndClearsBusy() = runTest {
        val setup = workFormSetup(); val model = setup.chapter("posted").also { it.load() }
        model.checkpoint(ChapterFormText.Content, "private typed text"); val form = model.state.value.form
        setup.client.body = workFixture("ao3_demo_chapter_995006_delete")
        setup.client.beforePostResponse = { setup.auth.logout() }
        model.deleteChapter(confirmed = true)
        assertEquals(AO3CollectionFields.UNCONFIRMED, model.state.value.saveError)
        assertEquals(form, model.state.value.form); assertFalse(model.state.value.finished)
        assertFalse(model.state.value.busy); assertEquals(0, model.state.value.savedRevision)
        assertEquals(1, setup.client.posts)
    }
}
