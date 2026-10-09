package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields
import io.github.cidy02.kudos.network.ao3.writing.*
import io.github.cidy02.kudos.network.ao3.writing.recovery.WritingTextRecovery
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.nio.file.Files

class WritingWorkSaveTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun threeSaveRequestsUseTheLoadedIosTokenActionSubmitAndEveryOrderedEncoderField() = runTest {
        for ((id, token) in listOf(null to "draft-csrf==", 995001L to "demo-work-995001==", 995006L to "demo-work-995006==")) {
            val setup = workFormSetup()
            val model = setup.model(id).also { it.load() }
            assertEquals(0, setup.client.posts)
            val form = model.state.value.form!!
            val submit = if (id == 995006L) AO3WorkSubmitAction.Update else AO3WorkSubmitAction.SaveDraft
            model.save()
            val request = setup.client.recordedPosts.single()
            assertEquals(form.actionUrl, request.url)
            assertEquals(mapOf("X-CSRF-Token" to token, "Referer" to form.actionUrl,
                "Cookie" to request.headers.getValue("Cookie")), request.headers)
            assertTrue(request.headers.getValue("Cookie").isNotEmpty())
            assertEquals(form.parameters(submit), request.fields)
            assertEquals(iosFixtureSaveFields(id), request.fields)
            // 3bb: iOS's modeled pairs followed by the unchanged browser-successful controls.
            assertEquals(AO3WorkFormEncoder.iosParameters(form, submit) +
                AO3WorkFormEncoder.carriedParameters(form, submit), request.fields)
            assertEquals(listOf(submit.fieldName to "1"), request.fields.filter {
                it.first in AO3WorkSubmitAction.entries.map { action -> action.fieldName }
            })
            assertEquals(1, setup.client.gets.size) // Opening only. No token/verification read.
            assertTrue(model.state.value.saved)
            model.save()
            assertEquals(1, setup.client.posts)
        }
    }

    @Test fun emptyNewWorkIsSavedWithoutPostValidation() = runTest {
        val setup = workFormSetup()
        val model = setup.model(null).also { it.load() }
        assertEquals("", model.state.value.form!!.title)
        model.save()
        assertTrue(model.state.value.saved)
        assertEquals(1, setup.client.posts)
    }

    @Test fun loadedMetaTokenWinsOverTheInputAndNoFreshPageIsFetched() = runTest {
        val setup = workFormSetup()
        val doc = Jsoup.parse(workFixture("ao3_demo_work_draft_edit"))
        doc.selectFirst("meta[name=csrf-token]")!!.attr("content", "  loaded-meta==  ")
        doc.selectFirst("input[name=authenticity_token]")!!.attr("value", "different-input")
        setup.client.body = doc.outerHtml()
        val model = setup.model(995001L).also { it.load() }
        model.save()
        val request = setup.client.recordedPosts.single()
        assertEquals("loaded-meta==", request.headers["X-CSRF-Token"])
        assertEquals(listOf(AO3WorkFormField.authenticityToken to "loaded-meta=="),
            request.fields.filter { it.first == AO3WorkFormField.authenticityToken })
        assertEquals(1, setup.client.gets.size)
    }

    @Test fun thrownTransportErrorIsNotRetriedAndAnExplicitLaterSuccessClearsItsAlert() = runTest {
        val setup = workFormSetup()
        val model = setup.model(995001L).also { it.load() }
        model.title("Retained through thrown failure")
        val before = model.state.value.form
        setup.client.beforePostResponse = { throw java.io.IOException("local transport failure") }
        model.save()
        assertEquals("Couldn't reach AO3. Check your connection and try again.", model.state.value.saveError)
        assertEquals(before, model.state.value.form); assertEquals(1, setup.client.posts)
        setup.client.beforePostResponse = {}
        model.save() // Another explicit tap, never an automatic retry.
        assertTrue(model.state.value.saved); assertNull(model.state.value.saveError)
        assertEquals(2, setup.client.posts); assertEquals(1, setup.client.gets.size)
    }

    @Test fun changedFormSendsAllCurrentFieldsExactlyAndKeepsRecoveryCopiesEvenOnSuccess() = runTest {
        val setup = workFormSetup()
        val model = setup.model(995001L).also { it.load() }
        model.title("  Tide & 星 \"new\"  ")
        model.choice(WorkFormChoice.Rating, "Mature")
        model.writingTags(WritingTagKind.Fandom, listOf("Original Work", "Demo Fandom & 星"))
        val store = WritingTextRecovery(temporary.newFolder().toPath())
        val copies = WorkFormText.entries.map { field ->
            val text = " <p>${field.title} &amp; 星</p>\n"
            model.checkpoint(field, text)
            val copy = store.sessionURL(store.fileURL(model.account, "work:995001", field.field))
            store.save(text, "original", copy)
            copy to Files.readAllBytes(copy)
        }
        val form = model.state.value.form!!
        model.save()
        assertEquals(form.parameters(AO3WorkSubmitAction.SaveDraft), setup.client.recordedPosts.single().fields)
        for ((copy, bytes) in copies) assertArrayEquals(bytes, Files.readAllBytes(copy))
        assertEquals(form, model.state.value.form)
    }

    @Test fun errorNoticeRedirectAndUnjudgedVerdictsHaveIosWordsAndPriority() = runTest {
        val refusal = "Title is too long (maximum is 255 characters)"
        for ((status, body, error) in listOf(
            Triple(200, "<main id=main><div class='flash notice'>Saved by AO3.</div></main>", null),
            Triple(302, "", null),
            Triple(422, "<main id=main><form><div id=error><ul><li>$refusal</li><li>Second reason</li></ul></div></form></main>", refusal),
            Triple(302, "<main id=main><div class='flash error'>$refusal</div><div class='flash notice'>Saved.</div></main>", refusal),
            Triple(200, "<main id=main><form><textarea>successfully saved</textarea></form></main>", AO3CollectionFields.UNCONFIRMED),
            Triple(204, "", AO3CollectionFields.UNCONFIRMED),
            Triple(200, "<main id=main><div id=workskin><div class='flash notice'>Saved.</div><div class='flash error'>Writer's fiction</div></div></main>", AO3CollectionFields.UNCONFIRMED),
            Triple(200, "<main id=main><div class=userstuff><div id=error><ul><li>Writer's fiction</li></ul></div></div></main>", AO3CollectionFields.UNCONFIRMED),
            Triple(200, "<main id=main><div id=previewpane></div><div class='flash error'>Preview text</div></main>", AO3CollectionFields.UNCONFIRMED),
            Triple(200, "<div class='flash notice'>Outside main</div>", AO3CollectionFields.UNCONFIRMED),
            Triple(418, "", "AO3 didn't accept the change.")
        )) {
            val setup = workFormSetup()
            setup.client.postBody = body; setup.client.postStatus = status
            val model = setup.model(995001L).also { it.load() }
            model.title("Keep exactly this & 星")
            val before = model.state.value.form
            model.save()
            assertEquals("HTTP $status / $body", error, model.state.value.saveError)
            assertEquals(error == null, model.state.value.saved)
            assertEquals(before, model.state.value.form)
            assertFalse(model.state.value.saving)
            assertEquals(1, setup.client.posts); assertEquals(1, setup.client.gets.size)
        }
    }

    @Test fun everyTransportTokenAndHttpFailureKeepsFieldsAndFourRecoveryCopiesWithoutRetry() = runTest {
        val errors = listOf(AO3Error.Forbidden, AO3Error.NotFound, AO3Error.BadRequest,
            AO3Error.RateLimited(null), AO3Error.Server(503), AO3Error.Overloaded(503, null),
            AO3Error.Parse("bad response"), AO3Error.Http(418), AO3Error.Network("offline", offline = true),
            AO3Error.Network("timeout", java.net.SocketTimeoutException()),
            AO3Error.Network("tls", javax.net.ssl.SSLException("tls")), AO3Error.Network("connection"),
            AO3Error.Validation("Invalid authenticity token"), AO3Error.AuthenticationRequired)
        for (error in errors) {
            val setup = workFormSetup()
            setup.client.postFailure = error
            val model = setup.model(995001L).also { it.load() }
            model.title("Retained title")
            val store = WritingTextRecovery(temporary.newFolder().toPath())
            val copies = WorkFormText.entries.map { field ->
                val text = "  <p>${field.title} &amp; 星</p>\n"
                model.checkpoint(field, text)
                val path = store.sessionURL(store.fileURL(model.account, "work:995001", field.field))
                store.save(text, "original", path)
                path to Files.readAllBytes(path)
            }
            val before = model.state.value.form
            model.save()
            assertFalse(model.state.value.saved); assertFalse(model.state.value.saving)
            // Each is AO3's own answer to the POST, the login page included ("session expired, log in again").
            assertEquals(workFormFailure(error), model.state.value.saveError)
            assertEquals(before, model.state.value.form)
            for ((path, bytes) in copies) assertArrayEquals(bytes, Files.readAllBytes(path))
            assertEquals(1, setup.client.posts); assertEquals(1, setup.client.gets.size)
        }
    }

    @Test fun busySaveRejectsSecondTapAndEditsAndDoesNotPublishBeforeConfirmation() = runTest {
        val setup = workFormSetup()
        val release = CompletableDeferred<Unit>()
        setup.client.beforePostResponse = { release.await() }
        val model = setup.model(995001L).also { it.load() }
        val before = model.state.value.form
        val save = async { model.save() }
        runCurrent()
        assertTrue(model.state.value.saving); assertFalse(model.state.value.saved)
        model.save(); model.title("While disabled"); model.checkpoint(WorkFormText.Content, "While disabled")
        assertEquals(1, setup.client.posts); assertEquals(before, model.state.value.form)
        release.complete(Unit); save.await()
        assertTrue(model.state.value.saved)
    }

    @Test fun changedSessionBeforeAndDuringSaveKeepsFormAndNeverUsesReplacementSession() = runTest {
        for (during in listOf(false, true)) {
            val setup = workFormSetup()
            val model = setup.model(995001L).also { it.load() }
            model.title("Retained private draft")
            val before = model.state.value.form
            if (during) setup.client.beforePostResponse = { setup.auth.logout() } else setup.auth.logout()
            model.save()
            assertEquals(if (during) AO3CollectionFields.UNCONFIRMED else WORK_FORM_SESSION_CHANGED, model.state.value.saveError)
            assertEquals(before, model.state.value.form); assertFalse(model.state.value.saved); assertFalse(model.state.value.saving)
            assertEquals(if (during) 1 else 0, setup.client.posts)
            assertEquals(1, setup.client.gets.size)
            model.dismissSaveError(); model.save()
            assertEquals(WORK_FORM_SESSION_CHANGED, model.state.value.saveError)
            assertEquals(if (during) 1 else 0, setup.client.posts)
        }
    }

    @Test fun multiChapterDraftSendsChapterTitleButNoContent() = runTest {
        val setup = workFormSetup()
        val doc = Jsoup.parse(workFixture("ao3_demo_work_draft_edit"))
        doc.select("textarea[name='work[chapter_attributes][content]']").remove()
        setup.client.body = doc.outerHtml()
        val model = setup.model(995001L).also { it.load() }
        assertFalse(model.state.value.form!!.chapter!!.contentServed)
        model.title("Several chapters")
        model.save()
        val fields = setup.client.recordedPosts.single().fields
        assertEquals(listOf(AO3WorkFormField.chapterTitle to "First Lantern"), fields.filter { it.first == AO3WorkFormField.chapterTitle })
        assertTrue(fields.none { it.first == AO3WorkFormField.chapterContent })
    }

    @Test fun signedOutAndUntrustedActionSendNothing() = runTest {
        val setup = workFormSetup(false)
        val form = AO3WorkFormParser().parse(workFixture("ao3_demo_work_draft_edit"))
        assertEquals(AO3Result.Failure(AO3Error.Validation("Log in to AO3 first.")),
            setup.writes.saveWork(form, setup.auth.generation.value))
        val signedIn = workFormSetup()
        assertTrue(signedIn.writes.saveWork(form.copy(actionUrl = "https://example.invalid/works"),
            signedIn.auth.generation.value) is AO3Result.Failure)
        assertEquals(0, setup.client.posts); assertEquals(0, signedIn.client.posts)
        assertTrue(setup.client.gets.isEmpty()); assertTrue(signedIn.client.gets.isEmpty())
    }
}

/** Literal iOS parameters order/values for the three served fixtures, independent of the encoder.
 * Only the authorized 3bb browser replay is derived from the independent DOM test oracle. */
internal fun iosFixtureSaveFields(id: Long?, title: String? = null,
    submit: AO3WorkSubmitAction = if (id == 995006L) AO3WorkSubmitAction.Update else AO3WorkSubmitAction.SaveDraft): List<Pair<String, String>> {
    val posted = id == 995006L
    val existing = id != null
    val fixture = if (posted) "ao3_demo_work_posted_edit" else if (existing) "ao3_demo_work_draft_edit" else "ao3_work_new_draft"
    val ios = buildList {
        add("authenticity_token" to if (existing) "demo-work-$id==" else "draft-csrf==")
        if (existing) add("_method" to "patch")
        add("work[title]" to (title ?: if (posted) "The Cartographer’s \"Second\" Tide & 星" else if (existing) "Lanterns Above the Mill" else ""))
        if (existing) add("work[rating_string]" to "Teen And Up Audiences")
        add("work[archive_warning_strings][]" to if (existing) "No Archive Warnings Apply" else "")
        add("work[category_strings][]" to if (existing) "Gen" else "")
        if (existing) add("work[category_strings][]" to "Multi")
        add("work[fandom_string]" to if (existing) "Mill Lantern Chronicles, 星の地図" else "")
        add("work[relationship_string]" to if (existing) "Mira & Sol, 河 / 海" else "")
        add("work[character_string]" to if (existing) "Mira \"Mapmaker\", Sol & Echo" else "")
        add("work[freeform_string]" to if (existing) "Maps, \"Wait & See\", 夜の約束" else "")
        add("work[language_id]" to if (existing) "1" else "")
        add("work[summary]" to if (existing) "<p>A map for the tide, a promise for the night. 星 & light.</p>" else "")
        add("work[notes]" to if (existing) "<p>For the keepers of the mill.</p>" else "")
        add("work[endnotes]" to if (existing) "<p>The next lantern waits.</p>" else "")
        add("work[collection_names]" to if (posted) "lantern_exchange, star_atlas" else "")
        add("work[recipients]" to if (posted) "PaperNavigator" else "")
        add("work[series_attributes][id]" to "")
        add("work[series_attributes][title]" to "")
        if (posted) {
            add("work[parent_work_relationships_attributes][0][url]" to "https://archiveofourown.org/works/990001")
            add("work[parent_work_relationships_attributes][0][title]" to "A Small \"North\" & 南")
            add("work[parent_work_relationships_attributes][0][author]" to "QuietNavigator")
            add("work[parent_work_relationships_attributes][0][language_id]" to "1")
        }
        add("work[wip_length]" to if (posted) "5" else "1")
        add("work[backdate]" to if (posted) "1" else "0")
        add("work[restricted]" to "0")
        add("work[moderated_commenting_enabled]" to if (posted) "1" else "0")
        add("work[comment_permissions]" to if (posted) "disable_anon" else "enable_all")
        add("work[anonymous]" to "0")
        add("work[collection_inbox]" to "1")
        add("work[work_skin_id]" to if (posted) "55" else "")
        if (!posted) {
            add("work[chapter_attributes][title]" to if (existing) "First Lantern" else "")
            add("work[chapter_attributes][summary]" to "")
            add("work[chapter_attributes][content]" to if (existing) "<p>The mill woke before the sun. A lantern answered.</p>" else "")
            add("work[chapter_attributes][published_at(1i)]" to "2026")
            add("work[chapter_attributes][published_at(2i)]" to "10")
            add("work[chapter_attributes][published_at(3i)]" to "5")
        }
        add("work[author_attributes][ids][]" to "101")
        add("work[parent_work_relationships_attributes][0][translation]" to "0")
        add(submit.fieldName to "1")
    }
    val modeledNames = ios.map { it.first }.toSet()
    return ios + browserControls(workFixture(fixture), submit).filterNot { it.first in modeledNames }
}
