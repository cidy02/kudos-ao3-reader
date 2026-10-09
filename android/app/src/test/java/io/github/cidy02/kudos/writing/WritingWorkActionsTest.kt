package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields
import io.github.cidy02.kudos.network.ao3.writing.*
import io.github.cidy02.kudos.network.ao3.writing.recovery.WritingTextRecovery
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.nio.file.Files

@OptIn(ExperimentalCoroutinesApi::class)
class WritingWorkActionsTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun directPostUsesOneExactIosRequestForNewDraftAndPostedAndNoPreparationRead() = runTest {
        for (id in listOf(null, 995001L, 995006L)) {
            val setup = workFormSetup(); val model = setup.model(id).also { it.load() }
            if (id == null) completeNewWork(model)
            val before = model.state.value.form!!
            model.post()
            val request = setup.client.recordedPosts.single()
            val expected = if (id == null) newPostFields() else iosFixtureSaveFields(id, submit = AO3WorkSubmitAction.Post)
            assertEquals(expected, request.fields)
            assertEquals(before.actionUrl, request.url)
            assertEquals(before.actionUrl, request.headers["Referer"])
            assertEquals(before.csrfToken, request.headers["X-CSRF-Token"])
            assertTrue(request.headers.getValue("Cookie").isNotBlank())
            assertEquals(listOf("GET ${if (id == null) AO3WorkFormUrls.newWork() else AO3WorkFormUrls.editWork(id)}",
                "POST ${before.actionUrl}"), setup.client.requests)
            assertTrue(model.state.value.saved)
            model.post(); model.save(); model.openPreview(); model.prepareDelete()
            assertEquals(1, setup.client.posts)
            assertEquals(before, model.state.value.form)
        }
    }

    @Test fun previewUsesAllIosFieldsAndAdoptsOnlyIdentityAndTokenThenSaveUpdatesThatDraft() = runTest {
        for (id in listOf(null, 995001L, 995006L)) {
            val setup = workFormSetup(); val model = setup.model(id).also { it.load() }
            model.title("Typed & 星")
            val before = model.state.value.form!!
            val created = id ?: 995007L
            setup.client.postBody = workPreviewHtml(created)
            model.openPreview()
            assertEquals(iosFixtureSaveFields(id, "Typed & 星", AO3WorkSubmitAction.Preview), setup.client.recordedPosts.single().fields)
            val adopted = model.state.value.form!!
            assertEquals(created, adopted.workID); assertEquals("preview-token==", adopted.csrfToken)
            assertEquals(before.copy(csrfToken = "preview-token==",
                workID = created, actionUrl = workActionUrl(created), methodOverride = "patch",
                kind = if (id == null) AO3WorkFormKind.Draft else before.kind), adopted)
            assertNotNull(model.state.value.preview); assertFalse(model.state.value.saved)
            assertEquals("Draft was successfully created.", model.state.value.preview!!.notice)
            assertEquals(listOf(AO3ChapterPreview.Kind.Heading, AO3ChapterPreview.Kind.Label, AO3ChapterPreview.Kind.Html),
                model.state.value.preview!!.blocks.map { it.kind })
            assertFalse(model.state.value.preview!!.blocks.any { it.text.contains("<img") || it.text.contains("landmark") })
            model.closePreview(); assertEquals(1, setup.client.posts)
            setup.client.postBody = "<main id=main><div class='flash notice'>Draft was successfully saved.</div></main>"
            model.save()
            val save = setup.client.recordedPosts.last()
            assertEquals(workActionUrl(created), save.url) // A second /works create would lose this assertion.
            assertEquals("patch", save.fields.first { it.first == "_method" }.second)
            assertEquals("preview-token==", save.headers["X-CSRF-Token"])
            assertEquals(listOf((if (adopted.isPosted) "update_button" else "save_button") to "1"),
                save.fields.filter { it.first.endsWith("_button") })
            assertEquals(1, setup.client.gets.size); assertEquals(2, setup.client.posts)
        }
    }

    @Test fun newPreviewThenPostUsesTheSameDraftAndNoSecondCreation() = runTest {
        val setup = workFormSetup(); val model = setup.model(null).also { it.load() }; completeNewWork(model)
        setup.client.postBody = workPreviewHtml(995007); model.openPreview()
        setup.client.postBody = "<main id=main><div class='flash notice'>Work was successfully posted.</div></main>"
        model.post()
        assertEquals(listOf("POST https://archiveofourown.org/works", "POST https://archiveofourown.org/works/995007"),
            setup.client.requests.drop(1))
        assertEquals(listOf("preview_button", "post_button"), setup.client.recordedPosts.map { post -> post.fields.last { it.first.endsWith("_button") }.first })
        assertTrue(model.state.value.saved); assertNull(model.state.value.preview)
    }

    @Test fun successfulNewPreviewKeepsAllFourOriginalRecoveryCopiesThenPostKeepsThemToo() = runTest {
        val setup = workFormSetup(); val model = setup.model(null).also { it.load() }; completeNewWork(model)
        val store = WritingTextRecovery(temporary.newFolder().toPath())
        val copies = WorkFormText.entries.map { field ->
            val path = store.sessionURL(store.fileURL(model.account, "work:new", field.field))
            store.save(field.text(model.state.value.form!!), "original", path); path to Files.readAllBytes(path)
        }
        setup.client.postBody = workPreviewHtml(995007); model.openPreview()
        assertEquals("work:995007", model.state.value.form!!.recoveryTarget())
        copies.forEach { (path, bytes) -> assertArrayEquals(bytes, Files.readAllBytes(path)) }
        setup.client.postBody = "<main id=main><div class='flash notice'>Posted.</div></main>"; model.post()
        assertTrue(model.state.value.saved)
        copies.forEach { (path, bytes) -> assertArrayEquals(bytes, Files.readAllBytes(path)) }
    }

    @Test fun missingFieldsAndUnidentifiedNewPreviewNeverChangeFormOrSendAnotherPost() = runTest {
        val setup = workFormSetup(); val model = setup.model(null).also { it.load() }
        val before = model.state.value.form
        model.post()
        assertEquals(listOf("Title", "Rating", "Archive Warning", "Fandoms", "Language", "Work Text"), before!!.missingRequiredFields())
        assertEquals("AO3 still needs Title and Rating and Archive Warning and Fandoms and Language and Work Text.", model.state.value.saveError)
        assertEquals(0, setup.client.posts)
        setup.client.postBody = workPreviewHtml(null); model.openPreview()
        assertEquals(AO3CollectionFields.UNCONFIRMED, model.state.value.saveError)
        assertNull(model.state.value.preview); assertEquals(before, model.state.value.form)
        assertEquals(1, setup.client.posts); assertEquals(1, setup.client.gets.size)
        // Foundation whitespace includes zero-width space/NEL but not Kotlin's extra C0 separator.
        assertTrue(before.copy(title = "\u200b\u0085").missingRequiredFields().contains("Title"))
        assertFalse(before.copy(title = "\u001c").missingRequiredFields().contains("Title"))
        assertFalse(before.copy(chapter = before.chapter!!.copy(contentServed = false)).missingRequiredFields().contains("Work Text"))
    }

    @Test fun deleteShowsServedCountsAndUsesSwiftReadOrderThenOnlyTwoPostFields() = runTest {
        for (id in listOf(995001L, 995006L)) {
            val setup = workFormSetup(); val model = setup.model(id).also { it.load() }; prepareDeletePages(setup, id)
            val before = model.state.value.form
            model.delete(); assertEquals(0, setup.client.posts); assertEquals(1, setup.client.gets.size)
            model.prepareDelete(); model.prepareDelete()
            val implications = model.state.value.deleteImplications!!
            assertEquals(workDeleteCaution, implications.cautionText)
            assertEquals(7, implications.comments); assertEquals(23, implications.kudos); assertEquals(4, implications.bookmarks)
            assertEquals(0, setup.client.posts)
            model.delete()
            val post = setup.client.recordedPosts.single()
            assertEquals(listOf("authenticity_token" to "delete-token==", "_method" to "delete"), post.fields)
            assertEquals(workActionUrl(id), post.url); assertEquals(post.url, post.headers["Referer"])
            assertEquals("delete-token==", post.headers["X-CSRF-Token"])
            // The confirmation page before the alert and again on the confirmed delete; never the work's own
            // page for counts nobody is shown (iOS reads it both times).
            val stage = listOf("GET ${workConfirmDeleteUrl(id)}")
            assertEquals(listOf("GET ${AO3WorkFormUrls.editWork(id)}") + stage + stage + "POST ${workActionUrl(id)}", setup.client.requests)
            assertEquals(before, model.state.value.form); assertTrue(model.state.value.saved)
            model.delete(); assertEquals(1, setup.client.posts)
        }
    }

    @Test fun deleteTokenFallsBackToServedInputAndVisibleOverrideWinsAsInSwift() {
        val html = workDeleteHtml(995001).replace("<meta name='csrf-token' content='delete-token=='>", "")
            .replace("<input name='_method' value='delete'>", "<input type='hidden' name='_method' value='ignored'><input name='_method' value='delete'>")
        val parsed = AO3WorkDeleteParser.parse(html, workConfirmDeleteUrl(995001), 995001)
        assertEquals("input-token", parsed.csrfToken); assertEquals("delete", parsed.methodOverride)
    }

    @Test fun confirmedDeleteUsesTheFreshSecondPageTokenAndServedMethodRatherThanTheAlertSnapshot() = runTest {
        val setup = workFormSetup(); val model = setup.model(995001).also { it.load() }; prepareDeletePages(setup, 995001)
        model.prepareDelete()
        assertEquals("delete-token==", model.state.value.deleteImplications!!.csrfToken)
        setup.client.getBodies[workConfirmDeleteUrl(995001)] = workDeleteHtml(995001)
            .replace("delete-token==", "fresh-delete-token==").replace("value='delete'", "value='destroy'")
        model.delete()
        assertEquals(listOf("authenticity_token" to "fresh-delete-token==", "_method" to "destroy"), setup.client.recordedPosts.single().fields)
        assertEquals("fresh-delete-token==", setup.client.recordedPosts.single().headers["X-CSRF-Token"])
    }

    @Test fun everyVerdictRetainsTypedFieldsAndRecoveryCopiesOnFailureWithoutRetries() = runTest {
        for (action in listOf(WorkFormAction.Post, WorkFormAction.Preview, WorkFormAction.Delete)) {
            val cases = listOf(
                200 to "<main id=main><div class='flash notice'>Confirmed.</div></main>",
                302 to "", 200 to "<main id=main></main>", 204 to "",
                422 to "<main id=main><div class='flash notice'>Old notice.</div><div id=error><ul><li>AO3's exact reason &amp; 星</li><li>Ignored second reason.</li></ul></div></main>",
                200 to "<main id=main><div id=workskin><div class='flash notice'>Writer's text</div><div class='flash error'>Fiction</div></div></main>")
            for ((status, body) in cases) {
                val setup = workFormSetup(); val model = setup.model(995001).also { it.load() }
                model.title("  Typed & 星  ")
                val recovery = WritingTextRecovery(temporary.newFolder().toPath())
                val copies = WorkFormText.entries.map { field ->
                    val text = "<p>${field.field} &amp; 星</p>\n"; model.checkpoint(field, text)
                    val path = recovery.sessionURL(recovery.fileURL(model.account, "work:995001", field.field))
                    recovery.save(text, "original", path); path to Files.readAllBytes(path)
                }
                prepareDeletePages(setup, 995001)
                if (action == WorkFormAction.Delete) model.prepareDelete()
                val before = model.state.value.form
                setup.client.postStatus = status; setup.client.postBody = body
                when (action) { WorkFormAction.Post -> model.post(); WorkFormAction.Preview -> model.openPreview(); else -> model.delete() }
                val success = action != WorkFormAction.Preview && (status == 302 || body.contains("Confirmed."))
                val expected = if (success) null else if (status == 422) "AO3's exact reason & 星"
                    else if (action == WorkFormAction.Preview) CHAPTER_PREVIEW_UNAVAILABLE else AO3CollectionFields.UNCONFIRMED
                assertEquals("$action / $status", expected, model.state.value.saveError)
                assertEquals(success, model.state.value.saved); assertFalse(model.state.value.saving)
                assertEquals(before, model.state.value.form)
                copies.forEach { (path, bytes) -> assertArrayEquals(bytes, Files.readAllBytes(path)) }
                assertEquals(1, setup.client.posts)
            }
        }
    }

    @Test fun previewPaneSuppressesAuthoredErrorAndUpdatesExistingTokenWithoutReplacingText() = runTest {
        val setup = workFormSetup(); val model = setup.model(995001).also { it.load() }
        setup.client.postBody = workPreviewHtml(995001).replace("<div id='previewpane'>", "<div class='flash error'>Not AO3 refusing</div><div id='previewpane'>")
        model.openPreview()
        assertNotNull(model.state.value.preview); assertNull(model.state.value.saveError)
    }

    @Test fun busySecondTapDuringEachReadOrWriteIsIgnoredAndSessionChangeCannotPublish() = runTest {
        for (action in WorkFormAction.entries.filter { it != WorkFormAction.Save }) {
            val setup = workFormSetup(); val model = setup.model(995001).also { it.load() }; prepareDeletePages(setup, 995001)
            if (action == WorkFormAction.Delete) model.prepareDelete()
            val before = model.state.value.form
            val release = CompletableDeferred<Unit>()
            if (action == WorkFormAction.CheckDelete || action == WorkFormAction.Delete) setup.client.beforeResponse = { release.await() }
            else setup.client.beforePostResponse = { release.await() }
            suspend fun invoke() { when (action) {
                WorkFormAction.Post -> model.post(); WorkFormAction.Preview -> model.openPreview()
                WorkFormAction.CheckDelete -> model.prepareDelete(); else -> model.delete()
            } }
            val operation = async { invoke() }; runCurrent()
            val count = setup.client.requests.size
            invoke(); model.save(); model.title("ignored"); model.checkpoint(WorkFormText.Content, "ignored")
            assertEquals(count, setup.client.requests.size); assertEquals(before, model.state.value.form)
            setup.auth.logout(); release.complete(Unit); operation.await()
            val beforeDispatch = action == WorkFormAction.CheckDelete || action == WorkFormAction.Delete
            assertEquals(if (beforeDispatch) WORK_FORM_SESSION_CHANGED else AO3CollectionFields.UNCONFIRMED, model.state.value.saveError)
            assertEquals(before, model.state.value.form); assertFalse(model.state.value.saved); assertNull(model.state.value.preview)
            assertFalse(model.state.value.saving)
            assertEquals(if (beforeDispatch) 0 else 1, setup.client.posts)
        }
    }

    @Test fun sessionMovingDuringDeletePostIsUnconfirmedAloneAndNeverLeavesTheFormBusy() = runTest {
        for (response in listOf("<main id=main><div class='flash notice'>Deleted.</div></main>",
            "<main id=main><div class='flash error'>Refused.</div></main>")) {
            val setup = workFormSetup(); val model = setup.model(995006).also { it.load() }
            model.title("Typed private title"); model.checkpoint(WorkFormText.Content, "Typed private text")
            prepareDeletePages(setup, 995006); model.prepareDelete()
            val before = model.state.value.form
            val release = CompletableDeferred<Unit>(); setup.client.beforePostResponse = { release.await() }
            setup.client.postBody = response
            val deletion = async { model.delete() }
            // The confirmation page is parsed off the test's clock: wait in real time for the POST to go out.
            for (attempt in 1..500) { runCurrent(); if (setup.client.posts == 1) break; Thread.sleep(10) }
            model.delete(); model.post(); model.save()
            assertEquals(1, setup.client.posts); assertTrue(model.state.value.saving)
            setup.auth.logout(); release.complete(Unit); deletion.await()
            assertEquals(AO3CollectionFields.UNCONFIRMED, model.state.value.saveError)
            assertEquals(before, model.state.value.form); assertFalse(model.state.value.saved)
            assertFalse(model.state.value.saving); assertNull(model.state.value.deleteImplications)
            assertEquals(1, setup.client.posts)
        }
    }

    @Test fun thrownFailureAndCancellationAlwaysClearActiveBusyStateAndKeepTheSnapshot() = runTest {
        for (action in listOf(WorkFormAction.Post, WorkFormAction.Preview, WorkFormAction.Delete)) {
            for (cancel in listOf(false, true)) {
                val setup = workFormSetup(); val model = setup.model(995001).also { it.load() }
                prepareDeletePages(setup, 995001)
                if (action == WorkFormAction.Delete) model.prepareDelete()
                val before = model.state.value.form
                setup.client.beforePostResponse = {
                    if (cancel) throw kotlinx.coroutines.CancellationException("Local cancellation")
                    else throw java.io.IOException("Local transport failure")
                }
                try {
                    when (action) { WorkFormAction.Post -> model.post(); WorkFormAction.Preview -> model.openPreview(); else -> model.delete() }
                    assertFalse(cancel)
                } catch (_: kotlinx.coroutines.CancellationException) { assertTrue(cancel) }
                assertFalse(model.state.value.saving); assertFalse(model.state.value.saved)
                assertEquals(before, model.state.value.form); assertEquals(1, setup.client.posts)
                if (!cancel) assertEquals("Couldn't reach AO3. Check your connection and try again.", model.state.value.saveError)
            }
        }
    }

    @Test fun signedOutOrChangedBeforeActionsSendsNothingAndPreparationFailureKeepsForm() = runTest {
        val out = workFormSetup(false)
        val parsed = AO3WorkFormParser().parse(workFixture("ao3_demo_work_draft_edit"), AO3WorkFormUrls.editWork(995001))
        assertEquals(AO3Result.Failure(AO3Error.Validation("Log in to AO3 first.")), out.writes.postWork(parsed, out.auth.generation.value))
        assertEquals(AO3Result.Failure(AO3Error.Validation("Log in to AO3 first.")), out.writes.previewWork(parsed, out.auth.generation.value))
        assertEquals(AO3Result.Failure(AO3Error.Validation("Log in to AO3 first.")), out.writes.loadDeleteImplications(995001, out.auth.generation.value))
        assertEquals(AO3Result.Failure(AO3Error.Validation("Log in to AO3 first.")), out.writes.deleteWork(995001, out.auth.generation.value))
        assertTrue(out.client.requests.isEmpty())
        val setup = workFormSetup(); val model = setup.model(995001).also { it.load() }
        val before = model.state.value.form
        setup.client.failure = AO3Error.Forbidden; model.prepareDelete()
        assertEquals(workFormFailure(AO3Error.Forbidden), model.state.value.saveError)
        assertEquals(before, model.state.value.form); assertEquals(0, setup.client.posts)
        setup.auth.logout(); model.post(); model.openPreview(); model.prepareDelete()
        assertEquals(WORK_FORM_SESSION_CHANGED, model.state.value.saveError); assertEquals(2, setup.client.gets.size)
    }

    @Test fun typedTransportFailuresOfEveryActionKeepTheExactFormAndNeverRetry() = runTest {
        for (action in listOf(WorkFormAction.Post, WorkFormAction.Preview, WorkFormAction.Delete)) {
            for (error in listOf(AO3Error.Forbidden, AO3Error.NotFound, AO3Error.RateLimited(null), AO3Error.Server(503),
                AO3Error.Network("offline", offline = true), AO3Error.Network("timeout", java.net.SocketTimeoutException()),
                AO3Error.Network("tls", javax.net.ssl.SSLException("tls")), AO3Error.AuthenticationRequired)) {
                val setup = workFormSetup(); val model = setup.model(995001).also { it.load() }
                model.title("Typed & 星"); WorkFormText.entries.forEach { model.checkpoint(it, "<p>${it.field} &amp; 星</p>") }
                val before = model.state.value.form
                prepareDeletePages(setup, 995001)
                if (action == WorkFormAction.Delete) model.prepareDelete()
                setup.client.postFailure = error
                when (action) { WorkFormAction.Post -> model.post(); WorkFormAction.Preview -> model.openPreview(); else -> model.delete() }
                // Each is AO3's own answer to the POST, the login page included ("session expired, log in again").
                assertEquals(workFormFailure(error), model.state.value.saveError)
                assertEquals(before, model.state.value.form); assertFalse(model.state.value.saved)
                assertEquals(1, setup.client.posts); assertFalse(model.state.value.saving)
            }
        }
    }

    @Test fun unsafeConfirmationActionCannotSendOrFetchStatsAndEmptyMethodDefaultsToDelete() = runTest {
        val setup = workFormSetup(); val model = setup.model(995006).also { it.load() }; prepareDeletePages(setup, 995006)
        setup.client.getBodies[workConfirmDeleteUrl(995006)] = workDeleteHtml(995006).replace("/works/995006", "https://example.invalid/works/995006")
        model.prepareDelete(); assertEquals(2, setup.client.gets.size); assertEquals(0, setup.client.posts)
        assertEquals("AO3's page format wasn't what the app expected.", model.state.value.saveError)
        assertEquals("delete", AO3WorkDeleteParser.parse(workDeleteHtml(995001).replace("value='delete'", "value=''"), workConfirmDeleteUrl(995001), 995001).methodOverride)
    }
}

internal fun completeNewWork(model: WritingWorkFormState) {
    model.title("New typed work"); model.choice(WorkFormChoice.Rating, "Teen And Up Audiences")
    model.toggleTag(WorkFormTags.Warnings, "No Archive Warnings Apply")
    model.writingTags(WritingTagKind.Fandom, listOf("Mill Lantern Chronicles")); model.choice(WorkFormChoice.Language, "1")
    model.checkpoint(WorkFormText.Content, "<p>Typed &amp; 星</p>")
}

private fun newPostFields(): List<Pair<String, String>> {
    val fields = iosFixtureSaveFields(null, "New typed work", AO3WorkSubmitAction.Post).filterNot { it.first == "work[rating_string]" }.toMutableList()
    fields.add(fields.indexOfFirst { it.first == "work[title]" } + 1, "work[rating_string]" to "Teen And Up Audiences")
    val replacements = mapOf("work[archive_warning_strings][]" to "No Archive Warnings Apply", "work[fandom_string]" to "Mill Lantern Chronicles",
        "work[language_id]" to "1", "work[chapter_attributes][content]" to "<p>Typed &amp; 星</p>")
    return fields.map { (name, value) -> name to (replacements[name] ?: value) }
}

internal fun workPreviewHtml(id: Long?): String = """<html><head><meta name='csrf-token' content='preview-token=='></head>
    <body><main id='main'><div class='flash notice'>Draft was successfully created.</div><div id='previewpane'>
    <h2 class='title'>Preview title</h2><div class='module'><h3 class='heading'>Summary:</h3><div class='userstuff'>
    <p>A <strong>bold</strong> paragraph &amp; 星.</p><p>Another paragraph.</p><img src='https://example.invalid/never-loaded.png'>
    </div></div><div class='landmark'>Invisible landmark</div>
    ${if (id == null) "" else "<form method='post' action='/works/$id'><input type='submit' name='edit_button' value='Edit'></form>"}
    </div></main></body></html>"""

internal const val workDeleteCaution = "Are you sure? This will delete 7 comments, 23 kudos and 4 bookmarks and cannot be undone."
internal fun workDeleteHtml(id: Long): String = """<html><head><meta name='csrf-token' content='delete-token=='></head><body><main id='main'>
    <h2 class='heading'>Delete ${if (id == 995001L) "Draft" else "Work"}</h2><p class='caution'>$workDeleteCaution</p>
    <form method='post' class='destroy' action='/works/$id'><input name='authenticity_token' value='input-token'>
    <input name='_method' value='delete'><input name='commit' value='Delete'></form></main></body></html>"""
internal fun prepareDeletePages(setup: WorkFormTestSetup, id: Long) {
    setup.client.getBodies[workConfirmDeleteUrl(id)] = workDeleteHtml(id)
}
