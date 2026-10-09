package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields
import io.github.cidy02.kudos.network.ao3.writing.*
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test

class WritingEditTagsTest {
    private fun fixture() = workFixture("ao3_demo_work_edit_tags")
    private fun parse(html: String = fixture()) = AO3WorkFormParser().parse(html, AO3WorkFormUrls.editTags(995006))

    /**
     * Audit A23-1: AO3 may give the token only in the page's meta tag, which is no form
     * control. The body must still begin with it, as iOS's does; the encoder used to drop it.
     */
    @Test fun theTokenGoesInTheBodyEvenWhenOnlyTheMetaTagCarriesIt() {
        val html = fixture().replace("<input type=\"hidden\" name=\"authenticity_token\" value=\"demo-tags-995006==\">", "")
        assertTrue("the fixture's hidden token is gone", "name=\"authenticity_token\"" !in html)
        val form = parse(html)
        assertEquals("demo-tags-995006==", form.csrfToken)
        val body = form.parameters(AO3WorkSubmitAction.Update)
        assertEquals(AO3WorkFormField.authenticityToken to "demo-tags-995006==", body.first())
        assertEquals(1, body.count { it.first == AO3WorkFormField.authenticityToken })
        assertTrue(body.any { it.first == AO3WorkFormField.methodOverride && it.second == "patch" })
        assertTrue(body.any { it.first == AO3WorkSubmitAction.Update.fieldName })
    }

    @Test fun tagsOnlyFixtureParsesWithoutTitleOrTextAndReplaysUntouchedBrowserFields() {
        val form = parse()
        assertEquals(AO3WorkFormKind.EditTags, form.kind)
        assertEquals(995006L, form.workID)
        assertEquals("https://archiveofourown.org/works/995006/update_tags", form.actionUrl)
        assertEquals("demo-tags-995006==", form.csrfToken)
        assertEquals("patch", form.methodOverride)
        assertEquals("Teen And Up Audiences", form.rating)
        assertEquals(listOf("No Archive Warnings Apply"), form.warnings)
        assertEquals(listOf("Gen", "Multi"), form.categories)
        assertEquals(listOf("Mill Lantern Chronicles", "星の地図"), form.fandoms)
        assertEquals(listOf("Mira & Sol", "河 / 海"), form.relationships)
        assertEquals(listOf("Mira \"Mapmaker\"", "Sol & Echo"), form.characters)
        assertEquals(listOf("Maps", "\"Wait & See\"", "夜の約束"), form.additionalTags)
        assertEquals(6, form.warningOptions.size); assertEquals(6, form.categoryOptions.size)
        assertEquals(6, form.ratingOptions.size); assertEquals("1", form.languageID)
        assertEquals("", form.title); assertNull(form.chapter)
        val encoded = form.parameters(AO3WorkSubmitAction.Update)
        // Parameter order is iOS modeled fields then browser replay, while per-name order is browser-exact.
        assertEquals(browserControls(fixture(), AO3WorkSubmitAction.Update).map { pair ->
                if (pair.first == "update_button") pair.first to "1" else pair
            }.groupBy({ it.first }, { it.second }),
            encoded.groupBy({ it.first }, { it.second }))
        assertEquals(iosTags(form), encoded)
        assertEquals(listOf("first", "星 & second"), encoded.filter { it.first == "work[served_only][]" }.map { it.second })
        assertTrue(form.servedControls.any { it.name == "served_disabled" })
        assertTrue(form.servedControls.any { it.name == "served_unchecked" })
        assertTrue(encoded.none { it.first in listOf("served_disabled", "served_unchecked", AO3WorkFormField.title, AO3WorkFormField.chapterContent) })
    }

    @Test fun eachKindAndEveryClearUsesTheIosEncoderAndRetainsAllOtherControls() {
        val original = parse()
        val variants = listOf(
            original.copy(rating = "Mature"), original.copy(rating = ""),
            original.copy(warnings = listOf("Major Character Death", "Rape/Non-Con")), original.copy(warnings = emptyList()),
            original.copy(categories = listOf("F/F", "Other")), original.copy(categories = emptyList()),
            original.copy(fandoms = listOf("  星\u200b", "Maps & Mills")), original.copy(fandoms = emptyList()),
            original.copy(relationships = listOf("Z/A", "A/B")), original.copy(relationships = emptyList()),
            original.copy(characters = listOf("A", "B")), original.copy(characters = emptyList()),
            original.copy(additionalTags = listOf("One, whole chip", "Two")), original.copy(additionalTags = emptyList())
        )
        variants.forEach { form ->
            assertEquals(iosTags(form), form.parameters(AO3WorkSubmitAction.Update))
            assertEquals(original.servedControls, form.servedControls)
        }
        val empty = original.copy(warnings = emptyList(), categories = emptyList(), fandoms = emptyList(),
            relationships = emptyList(), characters = emptyList(), additionalTags = emptyList())
        for (name in listOf(AO3WorkFormField.warnings, AO3WorkFormField.categories, AO3WorkFormField.fandoms,
            AO3WorkFormField.relationships, AO3WorkFormField.characters, AO3WorkFormField.additionalTags)) {
            assertEquals(listOf(""), empty.parameters(AO3WorkSubmitAction.Update).filter { it.first == name }.map { it.second })
        }
    }

    @Test fun anAbsentOrDisabledModeledFieldIsNeverSentAndUnknownControlsReplayBrowserSemantics() {
        val doc = Jsoup.parse(fixture())
        doc.select("input[name='work[relationship_string]']").remove()
        doc.select("select[name='work[language_id]']").remove()
        doc.select("input[name=update_button]").remove()
        doc.select("input[name='work[character_string]']").attr("disabled", "disabled")
        doc.selectFirst("form")!!.append("""
            <input type=hidden name=future value=0><input type=checkbox name=future value=1 checked>
            <select name='future_many[]' multiple><option value=a selected>A</option><option value=b selected>B</option></select>
            <textarea name=future_text>  &lt;p&gt;keep 星&lt;/p&gt;  </textarea>
            <input form=work-form name=external value=kept>
        """)
        val form = parse(doc.outerHtml()).copy(relationships = listOf("invented"), characters = listOf("disabled"), languageID = "999")
        val fields = form.parameters(AO3WorkSubmitAction.Update)
        assertTrue(fields.none { it.first in listOf(AO3WorkFormField.relationships, AO3WorkFormField.characters, AO3WorkFormField.languageID) })
        // The action is always named, as on iOS, whether or not the page drew its button
        // (audit A23-1: the served-name rule is for the tag fields, not for the token, the
        // method or the submit).
        assertEquals(listOf("update_button" to "1"), fields.filter { it.first == "update_button" })
        assertEquals(browserControls(doc.outerHtml(), AO3WorkSubmitAction.Update).filter { it.first.startsWith("future") || it.first == "external" },
            fields.filter { it.first.startsWith("future") || it.first == "external" })
    }

    @Test fun oneOpeningReadNoOpeningPostAndSaveUsesFreshTokenActionMethodAndLanguage() = runTest {
        val setup = workFormSetup()
        val parent = setup.model(995006).also { it.load() }
        val model = parent.editTagsModel()!!
        model.load(); model.load(); model.load(retry = true)
        assertEquals(listOf(AO3WorkFormUrls.editWork(995006), AO3WorkFormUrls.editTags(995006)), setup.client.gets)
        assertEquals(0, setup.client.posts)
        model.writingTags(WritingTagKind.Freeform, listOf(" New & 星 ", "Two"))
        val fresh = Jsoup.parse(fixture()).apply {
            selectFirst("meta[name=csrf-token]")!!.attr("content", "fresh==")
            selectFirst("input[name=authenticity_token]")!!.attr("value", "stale-input")
            selectFirst("input[name=_method]")!!.attr("value", "put")
            selectFirst("form")!!.attr("action", "/works/995006/edit_tags")
            select("select[name='work[language_id]'] option").removeAttr("selected")
            select("select[name='work[language_id]'] option[value=3]").attr("selected", "selected")
        }.outerHtml()
        setup.client.body = fresh
        model.save()
        val request = setup.client.recordedPosts.single()
        assertEquals("https://archiveofourown.org/works/995006/edit_tags", request.url)
        assertEquals("fresh==", request.headers["X-CSRF-Token"])
        assertEquals(AO3WorkFormUrls.editTags(995006), request.headers["Referer"])
        assertTrue(request.headers.getValue("Cookie").isNotEmpty())
        assertEquals(iosTags(parse(fresh).withTagsFrom(model.state.value.form!!)), request.fields)
        assertEquals(3, setup.client.gets.size); assertEquals(1, setup.client.posts)
        assertTrue(model.state.value.saved)
        model.save(); assertEquals(1, setup.client.posts)
    }

    @Test fun everyVerdictKeepsTheTypedFormUntilConfirmedAndUsesIosWords() = runTest {
        val refusal = "Please select at least one warning"
        val replies = listOf(
            Triple(200, "<main id=main><div class='flash notice'>Tags saved.</div></main>", null),
            Triple(302, "", null),
            Triple(422, "<div id=error><ul><li>$refusal</li></ul></div>", refusal),
            Triple(302, "<div id=error><ul><li>$refusal</li></ul></div><main id=main><div class='flash notice'>Saved.</div></main>", refusal),
            Triple(200, "<form><textarea>successfully updated</textarea></form>", AO3CollectionFields.UNCONFIRMED),
            Triple(204, "", AO3CollectionFields.UNCONFIRMED),
            Triple(400, "", "AO3 didn't accept the change.")
        )
        for ((status, body, error) in replies) {
            val setup = workFormSetup()
            val parent = setup.model(995006).also { it.load() }
            val parentBefore = parent.state.value.form
            val model = parent.editTagsModel()!!.also { it.load() }
            model.writingTags(WritingTagKind.Freeform, listOf("keep typed 星"))
            model.toggleTag(WorkFormTags.Warnings, "No Archive Warnings Apply")
            val before = model.state.value.form
            setup.client.postStatus = status; setup.client.postBody = body
            model.save()
            assertEquals(before, model.state.value.form)
            assertEquals(error == null, model.state.value.saved)
            assertEquals(error, model.state.value.saveError)
            assertEquals(parentBefore, parent.state.value.form)
            assertEquals(1, setup.client.posts); assertEquals(3, setup.client.gets.size)
            model.load(); assertEquals(3, setup.client.gets.size)
        }
    }

    @Test fun readAndWriteFailuresKeepTheDraftWithoutRetriesAndBestEffortAttemptsStayAttempted() = runTest {
        for (error in listOf(AO3Error.Forbidden, AO3Error.NotFound, AO3Error.RateLimited(1000), AO3Error.Network("offline"))) {
            val setup = workFormSetup()
            val parent = setup.model(995006).also { it.load() }
            val model = parent.editTagsModel()!!.also { it.load() }
            model.writingTags(WritingTagKind.Fandom, listOf("typed"))
            val before = model.state.value.form
            setup.client.failure = error
            model.save()
            assertEquals(before, model.state.value.form); assertFalse(model.state.value.saved)
            assertEquals(workFormFailure(error), model.state.value.saveError)
            assertEquals(0, setup.client.posts); assertEquals(3, setup.client.gets.size)
            setup.client.failure = null; setup.client.postFailure = error
            model.dismissSaveError(); model.save()
            assertEquals(before, model.state.value.form); assertEquals(workFormFailure(error), model.state.value.saveError)
            assertEquals(1, setup.client.posts); assertEquals(4, setup.client.gets.size)
        }
        val setup = workFormSetup()
        val parent = setup.model(995006).also { it.load() }
        val model = parent.editTagsModel()!!
        setup.client.failure = AO3Error.Forbidden
        model.load(); model.load()
        assertEquals(2, setup.client.gets.size); assertNull(model.state.value.form)
        setup.client.failure = null; model.load(retry = true)
        assertNotNull(model.state.value.form); assertEquals(3, setup.client.gets.size)
    }

    @Test fun editsMadeDuringSaveStayEditableAndAreRetainedOnRefusalWhileTheRequestKeepsItsSnapshot() = runTest {
        val setup = workFormSetup()
        val parent = setup.model(995006).also { it.load() }
        val model = parent.editTagsModel()!!.also { it.load() }
        model.writingTags(WritingTagKind.Freeform, listOf("Sent snapshot"))
        val entered = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
        setup.client.beforePostResponse = { entered.complete(Unit); release.await() }
        setup.client.postStatus = 422
        setup.client.postBody = "<div id=error><ul><li>Refused</li></ul></div>"
        val save = async { model.save() }
        entered.await()
        model.writingTags(WritingTagKind.Freeform, listOf("Edited while waiting"))
        model.choice(WorkFormChoice.Rating, "Mature")
        val latest = model.state.value.form
        assertEquals(listOf("Sent snapshot"), setup.client.recordedPosts.single().fields
            .filter { it.first == AO3WorkFormField.additionalTags }.map { it.second })
        release.complete(Unit); save.await()
        assertEquals(latest, model.state.value.form)
        assertEquals("Refused", model.state.value.saveError)
        assertFalse(model.state.value.saving); assertFalse(model.state.value.saved)
        assertEquals(1, setup.client.posts); assertEquals(3, setup.client.gets.size)
    }

    @Test fun thrownTransportAndSessionChangeDuringPostRetainTheDraftAndDoNotRefreshOrRetry() = runTest {
        for (sessionChange in listOf(false, true)) {
            val setup = workFormSetup()
            val parent = setup.model(995006).also { it.load() }
            val model = parent.editTagsModel()!!.also { it.load() }
            model.writingTags(WritingTagKind.Freeform, listOf("typed after opening"))
            val before = model.state.value.form
            setup.client.beforePostResponse = {
                if (sessionChange) setup.auth.logout() else throw java.io.IOException("local transport failure")
            }
            model.save()
            assertEquals(before, model.state.value.form); assertFalse(model.state.value.saved)
            assertEquals(if (sessionChange) WORK_FORM_SESSION_CHANGED else "Couldn't reach AO3. Check your connection and try again.",
                model.state.value.saveError)
            assertFalse(parent.state.value.tagsNeedRefresh)
            assertEquals(3, setup.client.gets.size); assertEquals(1, setup.client.posts)
        }
    }

    @Test fun secondTapDuringPreparationOrPostSendsNothingAndClosedScreenIgnoresLateReply() = runTest {
        for (holdRead in listOf(true, false)) {
            val setup = workFormSetup()
            val parent = setup.model(995006).also { it.load() }
            val model = parent.editTagsModel()!!.also { it.load() }
            val entered = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
            val hold: suspend () -> Unit = { entered.complete(Unit); release.await() }
            if (holdRead) setup.client.beforeResponse = hold else setup.client.beforePostResponse = hold
            val first = async { model.save() }
            entered.await()
            val before = model.state.value.form
            assertTrue(model.state.value.saving)
            model.save()
            assertEquals(if (holdRead) 0 else 1, setup.client.posts)
            assertEquals(3, setup.client.gets.size)
            if (!holdRead) model.close()
            release.complete(Unit); first.await()
            assertEquals(1, setup.client.posts); assertEquals(before, model.state.value.form)
            assertEquals(holdRead, model.state.value.saved)
        }
    }

    @Test fun confirmedSaveReloadsOnlyTagsAndRefreshFailureBlocksTheWorkSaveUntilExplicitRetry() = runTest {
        val setup = workFormSetup()
        val parent = setup.model(995006).also { it.load() }
        parent.title("Unsaved title"); parent.checkpoint(WorkFormText.Summary, "Unsaved summary")
        val original = parent.state.value.form!!
        val model = parent.editTagsModel()!!.also { it.load() }
        model.writingTags(WritingTagKind.Fandom, listOf("New fandom")); model.save()
        assertTrue(model.state.value.saved)
        parent.tagsSaved()
        setup.client.failure = AO3Error.Forbidden
        parent.refreshTags(); parent.refreshTags()
        assertTrue(parent.state.value.tagsNeedRefresh)
        assertEquals("Reload tags before saving this work. " + workFormFailure(AO3Error.Forbidden), parent.state.value.saveError)
        assertEquals(original, parent.state.value.form)
        parent.save(); assertEquals(1, setup.client.posts)
        assertEquals(4, setup.client.gets.size)
        setup.client.failure = null
        setup.client.body = Jsoup.parse(workFixture("ao3_demo_work_posted_edit")).apply {
            select("input[name='work[fandom_string]']").attr("value", "New fandom")
            select("input[name='work[freeform_string]']").attr("value", "New tag")
            select("input[name='work[relationship_string]']").attr("value", "New relationship")
            select("input[name='work[character_string]']").attr("value", "New character")
            select("input[name='work[archive_warning_strings][]']").removeAttr("checked")
            select("input[name='work[archive_warning_strings][]'][value='Major Character Death']").attr("checked", "checked")
            select("input[name='work[category_strings][]']").removeAttr("checked")
            select("input[name='work[category_strings][]'][value='F/F']").attr("checked", "checked")
            select("select[name='work[rating_string]'] option").removeAttr("selected")
            select("select[name='work[rating_string]'] option[value=Mature]").attr("selected", "selected")
            select("input[name='work[title]']").attr("value", "Server title")
        }.outerHtml()
        parent.refreshTags(retry = true)
        val fresh = AO3WorkFormParser().parse(setup.client.body!!)
        assertEquals(original.withTagsFrom(fresh), parent.state.value.form)
        assertFalse(parent.state.value.tagsNeedRefresh); assertNull(parent.state.value.saveError)
        assertEquals(5, setup.client.gets.size); assertEquals(1, setup.client.posts)
        parent.refreshTags(); assertEquals(5, setup.client.gets.size)
    }

    @Test fun signedOutDraftNewUnsafeAndChangedSessionSendNothing() = runTest {
        val out = workFormSetup(false)
        assertEquals(AO3Result.Failure(AO3Error.Validation("Log in to AO3 first.")), out.writes.editWorkTags(parse(), out.auth.generation.value))
        assertTrue(out.client.gets.isEmpty()); assertEquals(0, out.client.posts)
        for (id in listOf(null, 995001L)) {
            val setup = workFormSetup(); val parent = setup.model(id).also { it.load() }
            assertNull(parent.editTagsModel()); assertEquals(1, setup.client.gets.size)
            assertTrue(setup.writes.editWorkTags(parent.state.value.form!!, setup.auth.generation.value) is AO3Result.Failure)
            assertEquals(1, setup.client.gets.size); assertEquals(0, setup.client.posts)
        }
        for (during in listOf(false, true)) {
            val setup = workFormSetup()
            val parent = setup.model(995006).also { it.load() }
            val model = parent.editTagsModel()!!.also { it.load() }
            val before = model.state.value.form
            if (during) setup.client.beforeResponse = { setup.auth.logout() } else setup.auth.logout()
            model.save()
            assertEquals(before, model.state.value.form); assertEquals(WORK_FORM_SESSION_CHANGED, model.state.value.saveError)
            assertEquals(0, setup.client.posts)
        }
        val unsafe = workFormSetup()
        unsafe.client.body = fixture().replace("/works/995006/update_tags", "https://example.invalid/works/995006/update_tags")
        assertTrue(unsafe.writes.editWorkTags(parse(), unsafe.auth.generation.value) is AO3Result.Failure)
        assertEquals(1, unsafe.client.gets.size); assertEquals(0, unsafe.client.posts)
    }
}

/** Independent literal iOS AO3EditTagsForm encoder + authorized browser replay. */
private fun iosTags(form: AO3WorkForm): List<Pair<String, String>> {
    val modeled = buildList {
        add("authenticity_token" to form.csrfToken)
        form.methodOverride?.takeIf { it.isNotEmpty() }?.let { add("_method" to it) }
        if (form.rating.isNotEmpty()) add("work[rating_string]" to form.rating)
        form.warnings.ifEmpty { listOf("") }.forEach { add("work[archive_warning_strings][]" to it) }
        form.categories.ifEmpty { listOf("") }.forEach { add("work[category_strings][]" to it) }
        fun joined(names: List<String>) = names.map { it.trim { c -> c.isWhitespace() || c == '\u200b' || c == '\u0085' } }
            .filter { it.isNotEmpty() }.joinToString(", ")
        add("work[fandom_string]" to joined(form.fandoms))
        add("work[relationship_string]" to joined(form.relationships))
        add("work[character_string]" to joined(form.characters))
        add("work[freeform_string]" to joined(form.additionalTags))
        if (form.languageID.isNotEmpty()) add("work[language_id]" to form.languageID)
        add("update_button" to "1")
    }
    val names = modeled.map { it.first }.toSet()
    // This fixture has only these three successful unmodeled pairs; no production encoder oracle.
    val carry = listOf("utf8" to "✓", "work[served_only][]" to "first", "work[served_only][]" to "星 & second") +
        if (form.rating.isEmpty()) listOf("work[rating_string]" to "Teen And Up Audiences") else emptyList()
    // Browser carry is in DOM order: rating precedes served_only.
    return modeled + carry.filter { it.first == "utf8" } + carry.filter { it.first == "work[rating_string]" } +
        carry.filter { it.first !in names && it.first !in listOf("utf8", "work[rating_string]") }
}
