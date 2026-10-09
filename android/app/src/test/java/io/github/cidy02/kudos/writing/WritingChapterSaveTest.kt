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
class WritingChapterSaveTest {
    @Test fun saveDirectPostAndPostedUpdateEachSendOneExactLoadedRequestAndNoExtraReads() = runTest {
        for ((kind, submit) in listOf("new" to AO3WorkSubmitAction.SaveDraft, "draft" to AO3WorkSubmitAction.SaveDraft,
            "new" to AO3WorkSubmitAction.PostWithoutPreview, "draft" to AO3WorkSubmitAction.PostWithoutPreview,
            "posted" to AO3WorkSubmitAction.Update)) {
            val setup = workFormSetup()
            val model = setup.chapter(kind).also { it.load() }
            model.title("  kept & 星  ")
            val form = model.state.value.form!!
            model.save(submit)
            val sent = setup.client.recordedPosts.single()
            assertEquals(form.actionUrl, sent.url); assertEquals(form.actionUrl, sent.headers["Referer"])
            assertEquals(form.csrfToken, sent.headers["X-CSRF-Token"]); assertTrue(sent.headers.getValue("Cookie").isNotEmpty())
            assertEquals(literalChapterFields(form, submit) + chapterReplay(form, submit), sent.fields)
            assertEquals(1, setup.client.gets.size); assertEquals(1, model.state.value.savedRevision)
            assertTrue(model.state.value.finished); assertEquals(form, model.state.value.form)
            model.save(submit); assertEquals(1, setup.client.posts)
        }
    }

    @Test fun everyVerdictKeepsTheExactFormAndUsesIosWordsWithRefusalFirst() = runTest {
        for ((status, body, reason) in listOf(
            Triple(200, "<main id=main><div class='flash notice'>Saved.</div></main>", null),
            Triple(302, "", null),
            Triple(422, "<main id=main><form><div id=error><ul><li>Content can't be blank</li><li>Second reason</li></ul></div></form></main>", "Content can't be blank"),
            Triple(302, "<main id=main><div class='flash notice'>Old preview notice</div><div id=error><ul><li>Title is too long</li></ul></div></main>", "Title is too long"),
            Triple(200, "<main id=main><form><textarea>successfully saved</textarea></form></main>", AO3CollectionFields.UNCONFIRMED),
            Triple(204, "", AO3CollectionFields.UNCONFIRMED),
            Triple(200, "<main id=main><div class=userstuff><div class='flash error'>Fiction</div><div class='flash notice'>Fiction</div></div></main>", AO3CollectionFields.UNCONFIRMED),
            Triple(418, "", "AO3 didn't accept the change.")
        )) {
            val setup = workFormSetup(); val model = setup.chapter("draft").also { it.load() }
            for (field in ChapterFormText.entries) model.checkpoint(field, " ${field.field} & 星\n")
            val form = model.state.value.form
            setup.client.postStatus = status; setup.client.postBody = body
            model.save(AO3WorkSubmitAction.SaveDraft)
            assertEquals(reason, model.state.value.saveError); assertEquals(reason == null, model.state.value.finished)
            assertEquals(form, model.state.value.form); assertEquals(1, setup.client.posts); assertEquals(1, setup.client.gets.size)
            assertEquals(if (reason == null) 1 else 0, model.state.value.savedRevision)
        }
    }

    @Test fun lastChapterWritesChapterThenReadsWorkThenWritesOnlyItsChangedTotal() = runTest {
        for (work in listOf(995006L, 995001L)) {
            val setup = workFormSetup(); val model = setup.chapter("draft", work).also { it.load() }
            val events = mutableListOf<String>()
            setup.client.beforePostResponse = { events += "POST ${setup.client.recordedPosts.last().url}" }
            setup.client.beforeResponse = {
                events += "GET ${setup.client.gets.last()}"
                setup.client.body = workFixture(if (work == 995006L) "ao3_demo_work_posted_edit" else "ao3_demo_work_draft_edit")
            }
            model.afterChapter("12"); model.lastChapter(true)
            val form = model.state.value.form!!
            model.save(AO3WorkSubmitAction.SaveDraft)
            assertEquals(listOf("POST ${form.actionUrl}", "GET ${AO3WorkFormUrls.editWork(work)}", "POST https://archiveofourown.org/works/$work"), events)
            assertEquals(2, setup.client.posts); assertEquals(2, setup.client.gets.size)
            val total = setup.client.recordedPosts.last()
            val fresh = AO3WorkFormParser().parse(workFixture(if (work == 995006L) "ao3_demo_work_posted_edit" else "ao3_demo_work_draft_edit"))
            val names = fresh.servedControls.filterNot { it.disabled }.map { it.name }.toSet()
            assertEquals(fresh.copy(chapterTotal = "13").parameters(if (fresh.isPosted) AO3WorkSubmitAction.Update else AO3WorkSubmitAction.SaveDraft)
                .filter { it.first in names }, total.fields)
            assertTrue(total.fields.none { it.first == "work[chaptersPosted]" })
            assertTrue(model.state.value.finished)
        }
    }

    @Test fun aFailedTotalIsReportedAndExplicitRetryNeverRepeatsTheChapter() = runTest {
        val setup = workFormSetup(); val model = setup.chapter("draft").also { it.load() }
        model.lastChapter(true)
        setup.client.beforeResponse = { setup.client.body = workFixture("ao3_demo_work_posted_edit") }
        setup.client.beforePostResponse = {
            setup.client.postBody = if (setup.client.posts == 1) "<main id=main><div class='flash notice'>Chapter saved.</div></main>"
                else "<main id=main><div id=error><ul><li>Total is locked</li></ul></div></main>"
        }
        val form = model.state.value.form
        model.save(AO3WorkSubmitAction.SaveDraft)
        assertEquals("The chapter was saved, but the work total was not updated. Total is locked", model.state.value.saveError)
        assertTrue(model.state.value.chapterSaved); assertFalse(model.state.value.finished); assertEquals(1, model.state.value.savedRevision)
        model.title("disabled"); assertEquals(form, model.state.value.form)
        setup.client.beforePostResponse = { setup.client.postBody = "<main id=main><div class='flash notice'>Updated.</div></main>" }
        model.save(AO3WorkSubmitAction.Update)
        assertEquals(3, setup.client.posts); assertEquals(3, setup.client.gets.size)
        assertEquals(1, setup.client.recordedPosts.count { "/chapters/" in it.url })
        assertTrue(model.state.value.finished); assertEquals(2, model.state.value.savedRevision)
    }

    @Test fun noTotalAfterUnconfirmedChapterAndInvalidLastPositionSendsNothing() = runTest {
        val setup = workFormSetup(); val model = setup.chapter("draft").also { it.load() }
        model.lastChapter(true); setup.client.postBody = "<main></main>"
        model.save(AO3WorkSubmitAction.SaveDraft)
        assertEquals(1, setup.client.posts); assertEquals(1, setup.client.gets.size)
        assertEquals(AO3CollectionFields.UNCONFIRMED, model.state.value.saveError)
        model.afterChapter("?"); model.save(AO3WorkSubmitAction.SaveDraft)
        assertEquals("Enter this chapter’s position to mark it as the last chapter.", model.state.value.saveError)
        assertEquals(1, setup.client.posts)
    }

    @Test fun newPreviewAdoptsTheDraftAndPostUpdatesItWithoutAnotherCreate() = runTest {
        val setup = workFormSetup(); val model = setup.chapter("new").also { it.load() }
        setup.client.postBody = chapterPreviewHtml()
        model.openPreview()
        assertEquals(1, setup.client.posts); assertEquals("preview_button" to "1", setup.client.recordedPosts.single().fields.first { it.first == "preview_button" })
        assertEquals(12303L, model.state.value.form!!.chapterID); assertEquals(1, model.state.value.savedRevision)
        assertNotNull(model.state.value.preview)
        setup.client.postBody = "<main id=main><div class='flash notice'>Posted.</div></main>"
        model.save(AO3WorkSubmitAction.Post)
        assertEquals(AO3ChapterUrls.chapter(995006, 12303), setup.client.recordedPosts.last().url)
        assertEquals(listOf("_method" to "patch"), setup.client.recordedPosts.last().fields.filter { it.first == "_method" })
        assertEquals(listOf("post_button" to "1"), setup.client.recordedPosts.last().fields.filter { it.first == "post_button" })
        assertEquals(2, setup.client.posts); assertEquals(1, setup.client.gets.size); assertTrue(model.state.value.finished)
    }

    @Test fun missingPreviewIdentityOrPaneRetainsTheFormAndExistingPreviewDoesNotRefresh() = runTest {
        for ((kind, html, reason, revision) in listOf(
            PreviewCase("new", "<main id=main><div id=previewpane></div></main>", AO3CollectionFields.UNCONFIRMED, 0),
            PreviewCase("new", "<main id=main><form><div id=error><ul><li>Content can't be blank</li></ul></div></form></main>", "Content can't be blank", 0),
            PreviewCase("new", "<main></main>", CHAPTER_PREVIEW_UNAVAILABLE, 0),
            PreviewCase("draft", chapterPreviewHtml(12302), null, 0)
        )) {
            val setup = workFormSetup(); val model = setup.chapter(kind).also { it.load() }; val form = model.state.value.form
            setup.client.postBody = html; model.openPreview()
            assertEquals(reason, model.state.value.saveError); assertEquals(revision, model.state.value.savedRevision)
            if (reason != null) assertEquals(form, model.state.value.form)
            assertEquals(1, setup.client.posts); assertEquals(1, setup.client.gets.size)
        }
    }

    @Test fun duplicateBusyTapsTransportFailuresAndChangedSessionNeverLoseTypedFieldsOrRetry() = runTest {
        val setup = workFormSetup(); val model = setup.chapter("draft").also { it.load() }
        model.title("typed")
        val form = model.state.value.form
        val release = CompletableDeferred<Unit>()
        setup.client.beforePostResponse = { release.await() }
        val save = async { model.save(AO3WorkSubmitAction.SaveDraft) }; runCurrent()
        model.save(AO3WorkSubmitAction.SaveDraft); model.openPreview(); model.title("disabled")
        assertEquals(1, setup.client.posts); assertEquals(form, model.state.value.form); assertFalse(model.state.value.finished)
        setup.client.postFailure = AO3Error.RateLimited(null); release.complete(Unit); save.await()
        assertEquals(workFormFailure(AO3Error.RateLimited(null)), model.state.value.saveError); assertEquals(form, model.state.value.form)
        setup.auth.logout(); model.save(AO3WorkSubmitAction.SaveDraft)
        assertEquals(WORK_FORM_SESSION_CHANGED, model.state.value.saveError); assertEquals(1, setup.client.posts)
    }

    @Test fun allTypedAndThrownFailuresKeepEveryFieldAndSessionDuringPostCannotPublishSuccess() = runTest {
        for (failure in listOf(AO3Error.Forbidden, AO3Error.NotFound, AO3Error.AuthenticationRequired,
            AO3Error.Server(503), AO3Error.RateLimited(null), AO3Error.Network("offline", offline = true),
            AO3Error.Network("timeout", java.net.SocketTimeoutException()), AO3Error.Validation("Invalid authenticity token"))) {
            val setup = workFormSetup(); val model = setup.chapter("draft").also { it.load() }
            for (field in ChapterFormText.entries) model.checkpoint(field, "${field.field} typed 星")
            val form = model.state.value.form; setup.client.postFailure = failure
            model.save(AO3WorkSubmitAction.SaveDraft)
            assertEquals(form, model.state.value.form); assertFalse(model.state.value.finished)
            // Each is AO3's own answer to the POST, the login page included ("session expired, log in again").
            assertEquals(workFormFailure(failure), model.state.value.saveError)
            assertEquals(1, setup.client.posts); assertEquals(1, setup.client.gets.size)
        }
        val setup = workFormSetup(); val model = setup.chapter("draft").also { it.load() }; val form = model.state.value.form
        setup.client.beforePostResponse = { throw java.io.IOException("local") }
        model.save(AO3WorkSubmitAction.SaveDraft)
        assertEquals("Couldn't reach AO3. Check your connection and try again.", model.state.value.saveError); assertEquals(form, model.state.value.form)
        // The request had gone out when the session ended: AO3 may hold the chapter, so the truthful
        // answer is "didn't confirm", not a sentence that says to reopen the form "before saving" (A26-1).
        setup.client.beforePostResponse = { setup.auth.logout() }; model.save(AO3WorkSubmitAction.SaveDraft)
        assertEquals(io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields.UNCONFIRMED, model.state.value.saveError)
        assertFalse(model.state.value.finished); assertFalse(model.state.value.busy)
        assertEquals(2, setup.client.posts)
    }

    /**
     * Audit A26-1. Previewing a new chapter makes AO3 create its draft. The answer used to be thrown away
     * when the session had moved on meanwhile, so the form forgot the draft and said "reopen this form
     * before saving": the writer's next Preview created a second chapter.
     */
    @Test fun aPreviewAnsweredAfterTheSessionMovedOnStillAdoptsTheDraftAo3Created() = runTest {
        val setup = workFormSetup(); val model = setup.chapter("new").also { it.load() }
        setup.client.postBody = chapterPreviewHtml()
        setup.client.beforePostResponse = { setup.auth.logout() }
        model.openPreview()
        assertEquals(12303L, model.state.value.form!!.chapterID); assertNotNull(model.state.value.preview)
        assertEquals(null, model.state.value.saveError); assertFalse(model.state.value.busy)
        // The form is no longer this session's, so nothing more leaves it.
        setup.client.beforePostResponse = {}
        model.save(AO3WorkSubmitAction.Post)
        assertEquals(WORK_FORM_SESSION_CHANGED, model.state.value.saveError); assertEquals(1, setup.client.posts)
    }

    /** The same answer with nothing in it to adopt is "didn't confirm", never "session changed". */
    @Test fun aPreviewThatConfirmsNothingAfterTheSessionMovedOnIsUnconfirmed() = runTest {
        val setup = workFormSetup(); val model = setup.chapter("new").also { it.load() }
        setup.client.postBody = "<main id=main><p>Nothing a preview has.</p></main>"
        setup.client.beforePostResponse = { setup.auth.logout() }
        model.openPreview()
        assertEquals(io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields.UNCONFIRMED, model.state.value.saveError)
        assertEquals(null, model.state.value.form!!.chapterID); assertFalse(model.state.value.busy)
    }

    private data class PreviewCase(val kind: String, val html: String, val reason: String?, val revision: Int)
}

internal fun WorkFormTestSetup.chapter(kind: String, work: Long = 995006): WritingChapterFormState {
    client.body = workFixture("ao3_demo_chapter_${work}_$kind")
    return WritingChapterFormState(work, if (kind == "new") null else if (work == 995006L) 12302 else 12311,
        if (kind == "new") null else 2, repository, auth, writes = writes)
}
private fun chapterReplay(form: AO3ChapterForm, submit: AO3WorkSubmitAction): List<Pair<String, String>> {
    val names = literalChapterFields(form, submit).map { it.first }.toSet()
    return browserControls(workFixture("ao3_demo_chapter_995006_${if (form.chapterID == null) "new" else if (form.isDraft) "draft" else "posted"}")
        .replace("chapter-form", "work-form"), submit).filterNot { it.first in names }
}
internal fun chapterPreviewHtml(chapter: Long = 12303) = "<meta name=csrf-token content='fresh=='><main id=main><div class='flash notice'>Draft saved.</div><div id=previewpane><h3 class=title>New Tide</h3><div class=userstuff><p>Original text</p></div></div><form method=post action='/works/995006/chapters/$chapter'><input name=authenticity_token value='fresh=='><input name=_method value=patch><input name=edit_button type=submit><input name=post_button type=submit></form></main>"
