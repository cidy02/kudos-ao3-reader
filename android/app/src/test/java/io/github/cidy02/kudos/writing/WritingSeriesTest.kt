package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.auth.*
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields
import io.github.cidy02.kudos.network.ao3.writing.*
import io.github.cidy02.kudos.network.ao3.writes.*
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File

@OptIn(ExperimentalCoroutinesApi::class)
class WritingSeriesTest {
    private val parser = AO3SeriesFormParser()
    private fun form() = parser.parse(seriesFixture("ao3_demo_series_edit"), AO3SeriesFormUrls.edit(321))

    @Test fun parserKeepsPseudsBylineHtmlMethodAndEveryControl() {
        val form = form()
        assertEquals(321L, form.seriesID)
        assertEquals(AO3SeriesFormUrls.show(321), form.actionUrl)
        assertEquals("put", form.methodOverride)
        assertEquals("demo-series-token", form.csrfToken)
        assertEquals("The Dawn Cycle", form.title)
        assertTrue(form.isComplete)
        assertEquals("<p>Leave a lamp in the window for the next traveller.</p>", form.notes)
        assertEquals(listOf("123"), form.creators.selectedPseudIDs)
        assertEquals(listOf("Avery Writes", "Dawn Keeper"), form.creators.availablePseuds.map { it.title })
        assertEquals(15, form.servedControls.size)
        assertTrue(form.servedControls.any { it.disabled })
        val rows = parser.parseManage(seriesFixture("ao3_demo_series_manage"), AO3SeriesFormUrls.manage(321))
        assertEquals(listOf(3211L, 3212L, 3213L), rows.map { it.serialWorkID })
        assertEquals(listOf(1, 2, 3), rows.map { it.position })
        assertTrue(rows.last().isDraft)
        assertTrue(rows.all { it.workID == null })
    }

    @Test fun untouchedPayloadMatchesSuccessfulBrowserControlsAndRetainsDuplicates() {
        val form = form()
        // Independent browser payload for this fixture, with no native Save submitter.
        val browser = listOf("utf8" to "✓", "authenticity_token" to "demo-series-token", "_method" to "put",
            "series[title]" to "The Dawn Cycle", "series[author_attributes][ids][]" to "123",
            "series[author_attributes][byline]" to "", "series[summary]" to "Three stories about a difficult sunrise.",
            "series[series_notes]" to "<p>Leave a lamp in the window for the next traveller.</p>", "series[complete]" to "1",
            "series[private_note]" to "Keep this served value", "series[unknown][]" to "first", "series[unknown][]" to "second")
        assertEquals(browser.groupBy({ it.first }, { it.second }), form.parameters().groupBy({ it.first }, { it.second }))
        assertEquals(listOf("first", "second"), form.parameters().filter { it.first == "series[unknown][]" }.map { it.second })
        assertTrue(form.parameters().none { it.first in setOf("commit", "not_sent", "not_checked") })
    }

    @Test fun eachChangeUsesIosRepresentationIncludingLiteralBylineAndNoAbsentField() {
        val old = form()
        val changes = listOf(
            old.copy(title = "  New & 星  ") to (AO3SeriesField.title to listOf("  New & 星  ")),
            old.copy(summary = "<p>summary & text</p>") to (AO3SeriesField.summary to listOf("<p>summary & text</p>")),
            old.copy(notes = "") to (AO3SeriesField.notes to listOf("")),
            old.copy(isComplete = false) to (AO3SeriesField.complete to listOf("0")),
            old.copy(creators = old.creators.copy(selectedPseudIDs = listOf("124", "123"))) to (AO3SeriesField.ids to listOf("124", "123")),
            old.copy(creators = old.creators.copy(coauthorByline = "  friend (pseud)  ")) to (AO3SeriesField.byline to listOf("  friend (pseud)  ")))
        for ((changed, delta) in changes) {
            assertEquals(delta.second, changed.parameters().filter { it.first == delta.first }.map { it.second })
            assertEquals(changed.iosParameters().filter { it.first == delta.first }, changed.parameters().filter { it.first == delta.first })
            assertEquals(old.parameters().filterNot { it.first == delta.first }, changed.parameters().filterNot { it.first == delta.first })
            assertEquals(old.servedControls, changed.servedControls)
        }
        val absent = old.copy(servedControls = old.servedControls.filterNot { it.name in setOf(AO3SeriesField.byline, AO3SeriesField.notes) },
            notes = "do not send", creators = old.creators.copy(coauthorByline = "do not invite"))
        assertTrue(absent.parameters().none { it.first in setOf(AO3SeriesField.byline, AO3SeriesField.notes) })
    }

    @Test fun exactIosModeledOrderAndMetaPrecedenceHiddenPseudFallbackAndBylineCarry() {
        val form = form()
        assertEquals(listOf("authenticity_token" to "demo-series-token", "_method" to "put",
            "series[title]" to "The Dawn Cycle", "series[summary]" to "Three stories about a difficult sunrise.",
            "series[series_notes]" to "<p>Leave a lamp in the window for the next traveller.</p>", "series[complete]" to "1",
            "series[author_attributes][ids][]" to "123"), form.iosParameters())
        val html = seriesFixture("ao3_demo_series_edit").replace("name=\"authenticity_token\" value=\"demo-series-token\"",
            "name=\"authenticity_token\" value=\"wrong-input-token\"")
        assertEquals("demo-series-token", parser.parse(html, AO3SeriesFormUrls.edit(321)).csrfToken)
        val hidden = html.replace(Regex("<select[^>]*>.*?</select>", RegexOption.DOT_MATCHES_ALL),
            "<input type='hidden' name='series[author_attributes][ids][]' value='777'>")
        assertEquals(listOf("777"), parser.parse(hidden, AO3SeriesFormUrls.edit(321)).creators.selectedPseudIDs)
        val invited = parser.parse(html.replace("id=\"series_byline\" name=\"series[author_attributes][byline]\" value=\"\"",
            "id=\"series_byline\" name=\"series[author_attributes][byline]\" value=\"existing invitation\""), AO3SeriesFormUrls.edit(321))
        assertEquals(listOf(AO3SeriesField.byline to "existing invitation"), invited.copy(
            creators = invited.creators.copy(coauthorByline = "")).parameters().filter { it.first == AO3SeriesField.byline })
    }

    /** The rule audit A23-1 set for Edit tags, here too: the token is in the body even when only the meta tag has it. */
    @Test fun theTokenAndMethodGoInTheBodyEvenWhenOnlyTheMetaTagCarriesTheToken() {
        val html = seriesFixture("ao3_demo_series_edit")
            .replace("<input type=\"hidden\" name=\"authenticity_token\" value=\"demo-series-token\">", "")
        assertTrue("name=\"authenticity_token\"" !in html)
        val body = parser.parse(html, AO3SeriesFormUrls.edit(321)).parameters()
        assertEquals("authenticity_token" to "demo-series-token", body.first())
        assertEquals(1, body.count { it.first == "authenticity_token" })
        assertTrue(body.any { it.first == "_method" && it.second == "put" })
    }

    @Test fun unsafeActionsLoginOverloadAndMissingManageLandmarkAreRefused() {
        val html = seriesFixture("ao3_demo_series_edit")
        for (action in listOf("https://archiveofourown.org.evil.test/series/321", "https://evil.test/series/321", "/series/321/delete"))
            assertThrows(AO3WorkFormParseException.InvalidForm::class.java) {
                parser.parse(html.replace("action=\"/series/321\"", "action=\"$action\""), AO3SeriesFormUrls.edit(321)) }
        assertThrows(AO3WorkFormParseException.InvalidForm::class.java) {
            parser.parse(html.replace("name=\"_method\" value=\"put\"", "name=\"_method\" value=\"delete\""), AO3SeriesFormUrls.edit(321)) }
        assertThrows(AO3WorkFormParseException.LoginRequired::class.java) {
            parser.parse("<form id='new_user' action='/users/login'></form>", AO3SeriesFormUrls.edit(321)) }
        assertThrows(AO3WorkFormParseException.InvalidForm::class.java) { parser.parseManage("<ul></ul>", AO3SeriesFormUrls.manage(321)) }
        // A writer's own words that happen to sound like AO3's overloaded page are still a form.
        // (Only the summary is compared: the served controls carry the changed text too.)
        assertEquals("Retry later: AO3 is down",
            parser.parse(html.replace("Three stories about a difficult sunrise.", "Retry later: AO3 is down"), AO3SeriesFormUrls.edit(321)).summary)
    }

    @Test fun openingReadsEditAndManageOnceEvenAfterEditsAndChildReturn() = runTest {
        val setup = seriesSetup()
        val model = setup.model()
        model.load(); model.load(); model.load(retry = true)
        model.edit { it.copy(title = "held", notes = "typed notes") }
        model.beginReorder(); model.move(0, 2)
        assertEquals(listOf(AO3SeriesFormUrls.edit(321), AO3SeriesFormUrls.manage(321)), setup.client.gets)
        assertEquals("held", model.state.value.form!!.title)
        assertEquals(0, setup.client.posts.size)
        setup.model(reorderOnly = true).load()
        assertEquals(AO3SeriesFormUrls.manage(321), setup.client.gets.last())
        assertEquals(3, setup.client.gets.size)
    }

    @Test fun optionalManageFailureConsumesAttemptAndNeverPreventsEditingOrSave() = runTest {
        val setup = seriesSetup()
        setup.client.getFailure = AO3Error.Forbidden
        setup.client.failManageOnly = true
        val model = setup.model()
        model.load(); model.load(retry = true); model.edit { it.copy(title = "edited") }
        assertEquals("edited", model.state.value.form!!.title)
        assertEquals(emptyList<AO3SeriesWorkRow>(), model.state.value.form!!.works)
        assertEquals(2, setup.client.gets.size)
        model.save()
        assertEquals(1, setup.client.posts.size)
        assertEquals(2, setup.client.gets.size)
    }

    @Test fun invalidIDsAndRepositorySessionChangeReadNoForbiddenPageAndPublishNoForm() = runTest {
        val setup = seriesSetup()
        assertTrue(setup.repository.loadForm(0) is AO3Result.Failure)
        assertTrue(setup.repository.loadManage(-1) is AO3Result.Failure)
        assertTrue(setup.client.gets.isEmpty())
        setup.client.beforeGet = { setup.auth.logout() }
        assertThrows(CancellationException::class.java) { runBlocking<Unit> { setup.repository.loadForm(321) } }
        assertEquals(listOf(AO3SeriesFormUrls.edit(321)), setup.client.gets)
    }

    @Test fun requiredRefusalAndSignedOutNeverReadManage() = runTest {
        val refused = seriesSetup()
        refused.client.getFailure = AO3Error.Forbidden
        refused.model().load()
        assertEquals(listOf(AO3SeriesFormUrls.edit(321)), refused.client.gets)
        val out = seriesSetup(false)
        val model = out.model(); model.load(); model.load(retry = true)
        assertEquals("Log in to AO3 first.", model.state.value.failure)
        assertTrue(out.client.gets.isEmpty())
    }

    @Test fun saveEveryVerdictUsesIosWordsOnePostAndPreservesDraft() = runTest {
        for ((response, expected) in listOf(
            seriesResponse(200, "<main id='main'><div class='flash notice'>Series was successfully updated.</div></main>") to "Series was successfully updated.",
            seriesResponse(302, "") to "Saved.",
            seriesResponse(200, "<p>successfully in the author's text</p>") to AO3CollectionFields.UNCONFIRMED,
            seriesResponse(204, "") to AO3CollectionFields.UNCONFIRMED,
            seriesResponse(200, "<main id='main'><div class='flash notice'>Saved</div><div id='error'><ul><li>Byline is invalid</li></ul></div></main>") to "Byline is invalid",
            seriesResponse(422, "<div id='error'><ul><li>Title is too long</li></ul></div>") to "Title is too long",
            seriesResponse(500, "") to "AO3 didn't accept the change.")) {
            val setup = seriesSetup(); val model = setup.model(); model.load()
            model.edit { it.copy(title = "typed", notes = "held", creators = it.creators.copy(coauthorByline = "friend (pseud)")) }
            val draft = model.state.value.form
            setup.client.postResponse = response
            model.save()
            assertEquals(draft, model.state.value.form)
            assertEquals(expected, model.state.value.notice ?: model.state.value.error)
            assertEquals(1, setup.client.posts.size)
            assertEquals(2, setup.client.gets.size)
            val post = setup.client.posts.single()
            assertEquals(AO3SeriesFormUrls.show(321), post.url)
            assertEquals(post.url, post.headers["Referer"])
            assertEquals("demo-series-token", post.headers["X-CSRF-Token"])
            assertEquals(draft!!.parameters(), post.fields)
        }
    }

    @Test fun duplicateTapWhileHeldPostsOnceAndPublishesOnlyAfterConfirmation() = runTest {
        val setup = seriesSetup(); val model = setup.model(); model.load()
        val hold = CompletableDeferred<Unit>(); setup.client.beforePost = { hold.await() }
        val saving = launch { model.save() }; runCurrent(); model.save()
        assertTrue(model.state.value.saving); assertNull(model.state.value.notice)
        assertEquals(1, setup.client.posts.size)
        hold.complete(Unit); saving.join()
        assertEquals("Series was successfully updated.", model.state.value.notice)
    }

    @Test fun reorderUsesFreshManageTokenWholeSerialOrderOnePostAndReadBack() = runTest {
        val setup = seriesSetup(); val model = setup.model(); model.load(); model.beginReorder(); model.move(0, 2)
        model.save(order = true)
        assertTrue(model.state.value.orderSaved)
        assertEquals(listOf(3212L, 3213L, 3211L), model.state.value.form!!.works.map { it.serialWorkID })
        val post = setup.client.posts.single()
        assertEquals(AO3SeriesFormUrls.positions(321), post.url)
        assertEquals(listOf("authenticity_token" to "demo-series-manage-token", "serial[]" to "3212", "serial[]" to "3213", "serial[]" to "3211"), post.fields)
        assertEquals("demo-series-manage-token", post.headers["X-CSRF-Token"])
        assertEquals(AO3SeriesFormUrls.manage(321), post.headers["Referer"])
        assertEquals(listOf(AO3SeriesFormUrls.edit(321)) + List(3) { AO3SeriesFormUrls.manage(321) }, setup.client.gets)
        model.beginReorder()
        assertEquals(listOf(3212L, 3213L, 3211L), model.state.value.rows!!.map { it.serialWorkID })
    }

    @Test fun failedOrderVerificationAndRefusalKeepProposedAndParentOrders() = runTest {
        for (failure in listOf("mismatch", "read failure", "refusal", "429", "503", "offline")) {
            val setup = seriesSetup(); val model = setup.model(); model.load(); model.beginReorder(); model.move(0, 2)
            val draft = model.state.value.form; val order = model.state.value.rows
            setup.client.applyOrder = false
            when (failure) {
                "read failure" -> setup.client.failReadBack = true
                "refusal" -> setup.client.postResponse = seriesResponse(422, "<div id='error'><ul><li>Order is invalid</li></ul></div>")
                "429" -> setup.client.postResponse = AO3Result.Failure(AO3Error.RateLimited(null))
                "503" -> setup.client.postResponse = AO3Result.Failure(AO3Error.Server(503))
                "offline" -> setup.client.postResponse = AO3Result.Failure(AO3Error.Network("offline", offline = true))
            }
            model.save(order = true)
            assertFalse(model.state.value.orderSaved)
            assertEquals(draft, model.state.value.form); assertEquals(order, model.state.value.rows)
            assertEquals(1, setup.client.posts.size)
            assertEquals(if (failure in listOf("mismatch", "read failure")) 4 else 3, setup.client.gets.size)
            if (failure in listOf("mismatch", "read failure")) assertEquals(AO3CollectionFields.UNCONFIRMED, model.state.value.error)
            if (failure == "refusal") assertEquals("Order is invalid", model.state.value.error)
        }
    }

    @Test fun staleMembershipAndSessionBeforeDispatchNeverPost() = runTest {
        val setup = seriesSetup(); val model = setup.model(); model.load(); model.beginReorder(); model.move(0, 1)
        setup.client.manage = setup.client.manage.replace("serial_3213", "serial_3214").replace("position-for-3213", "position-for-3214")
        val draft = model.state.value.rows; model.save(order = true)
        assertEquals("The series changed on AO3 since this screen opened. Reopen it and try again.", model.state.value.error)
        assertEquals(draft, model.state.value.rows); assertTrue(setup.client.posts.isEmpty())
        setup.auth.logout(); model.save(order = true)
        assertEquals("Your AO3 session changed, so the order was not saved.", model.state.value.error)
        assertTrue(setup.client.posts.isEmpty())
    }

    @Test fun cancelledBestEffortManageAttemptIsRememberedOnExplicitRetry() = runTest {
        val setup = seriesSetup(); val model = setup.model()
        var cancel = true
        setup.client.beforeGet = {
            if (cancel && setup.client.gets.last().endsWith("/manage")) { cancel = false; throw CancellationException() }
        }
        model.load(); assertNotNull(model.state.value.form)
        model.load(retry = true)
        assertNotNull(model.state.value.form)
        assertEquals(listOf(AO3SeriesFormUrls.edit(321), AO3SeriesFormUrls.manage(321)), setup.client.gets)
        assertTrue(model.state.value.form!!.works.isEmpty())
    }

    @Test fun transportFailuresAndSessionChangesRetainEveryTypedField() = runTest {
        for (error in listOf(AO3Error.Forbidden, AO3Error.RateLimited(null), AO3Error.Server(503),
            AO3Error.Network("offline", offline = true), AO3Error.Validation("Pseud is invalid"))) {
            val setup = seriesSetup(); val model = setup.model(); model.load()
            model.edit { it.copy(title = "typed", summary = "held summary", notes = "held notes", isComplete = false,
                creators = it.creators.copy(coauthorByline = "invited byline")) }
            val draft = model.state.value.form
            setup.client.postResponse = AO3Result.Failure(error); model.save()
            assertEquals(draft, model.state.value.form)
            assertEquals(workFormFailure(error), model.state.value.error)
            assertNull(model.state.value.notice); assertEquals(1, setup.client.posts.size)
        }
        val setup = seriesSetup(); val model = setup.model(); model.load()
        model.edit { it.copy(title = "held across session failure") }
        val draft = model.state.value.form
        setup.client.beforePost = { setup.auth.logout() }
        model.save()
        assertEquals(draft, model.state.value.form); assertNull(model.state.value.notice)
        // The request had gone out when the session ended (one POST is recorded), so the
        // truthful answer is that AO3 did not confirm it, not that nothing was saved
        // (audit A24-1).
        assertEquals(io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields.UNCONFIRMED, model.state.value.error)
        assertEquals(1, setup.client.posts.size)
        model.save(); assertEquals(1, setup.client.posts.size)
    }

    @Test fun heldVerificationAndDuplicateReorderTapDoNotPublishOrPostTwice() = runTest {
        val setup = seriesSetup(); val model = setup.model(); model.load(); model.beginReorder(); model.move(0, 2)
        val draft = model.state.value.form
        val verification = CompletableDeferred<Unit>()
        setup.client.beforeGet = { if (setup.client.posts.isNotEmpty()) verification.await() }
        val saving = launch { model.save(order = true) }; runCurrent()
        assertEquals(1, setup.client.posts.size); assertTrue(model.state.value.saving)
        assertEquals(draft, model.state.value.form); assertFalse(model.state.value.orderSaved)
        model.save(order = true); assertEquals(1, setup.client.posts.size)
        verification.complete(Unit); saving.join()
        assertTrue(model.state.value.orderSaved)
    }

    @Test fun metaOnlyReorderTokenAndStalePreparationPreventPost() = runTest {
        val setup = seriesSetup()
        setup.client.manage = setup.client.manage.replace("<meta name=\"csrf-token\" content=\"demo-series-manage-token\">",
            "<input name='authenticity_token' value='input-is-not-meta'>")
        val result = setup.writes.reorderSeries(321, listOf(3211, 3212, 3213), setup.auth.generation.value)
        assertEquals(AO3Result.Failure(AO3Error.Validation("Couldn't prepare the request. Try again, or open the form on AO3.")), result)
        assertTrue(setup.client.posts.isEmpty())
        val second = seriesSetup(); val generation = second.auth.generation.value
        second.client.beforeGet = { second.auth.logout() }
        assertThrows(CancellationException::class.java) {
            runBlocking<Unit> { second.writes.reorderSeries(321, listOf(3211, 3212, 3213), generation) }
        }
        assertTrue(second.client.posts.isEmpty())
    }

    @Test fun titleSaveGateUsesFoundationWhitespacesWithoutChangingWhatIsSent() {
        assertTrue(seriesTitleIsBlank(" \t\u200b\u00a0"))
        assertFalse(seriesTitleIsBlank("\n"))
        assertEquals("  title  ", form().copy(title = "  title  ").parameters().first { it.first == AO3SeriesField.title }.second)
    }

    @Test fun removalIsVerifiedAndLastWorkCannotPost() = runTest {
        val setup = seriesSetup(); val model = setup.model(); model.load()
        model.remove(model.state.value.form!!.works.first())
        assertEquals(listOf(3212L, 3213L), model.state.value.form!!.works.map { it.serialWorkID })
        assertEquals(listOf("authenticity_token" to "demo-series-manage-token", "_method" to "delete"), setup.client.posts.single().fields)
        model.remove(model.state.value.form!!.works.first()); model.remove(model.state.value.form!!.works.first())
        assertEquals(2, setup.client.posts.size)
        assertEquals(1, model.state.value.form!!.works.size)
    }

    @Test fun removalFailuresKeepEveryFieldAndFreshLastWorkGuardPreventsPost() = runTest {
        for (failure in listOf("refusal", "unconfirmed", "last work", "session")) {
            val setup = seriesSetup(); val model = setup.model(); model.load()
            model.edit { it.copy(title = "held", notes = "held notes", creators = it.creators.copy(coauthorByline = "friend")) }
            val draft = model.state.value.form!!
            when (failure) {
                "refusal" -> setup.client.postResponse = seriesResponse(422, "<div id='error'><ul><li>Removal is invalid</li></ul></div>")
                "unconfirmed" -> setup.client.applyOrder = false
                "last work" -> {
                    val doc = org.jsoup.Jsoup.parse(setup.client.manage)
                    doc.select("#sortable_series_list li").drop(1).forEach { it.remove() }
                    setup.client.manage = doc.outerHtml()
                }
                "session" -> setup.auth.logout()
            }
            model.remove(draft.works.first())
            assertEquals(draft, model.state.value.form)
            assertEquals(if (failure in listOf("last work", "session")) 0 else 1, setup.client.posts.size)
            val reason = when (failure) {
                "refusal" -> "Removal is invalid"
                "unconfirmed" -> AO3CollectionFields.UNCONFIRMED
                "last work" -> "It is the series' last work on AO3, and AO3 deletes a series with its last work."
                else -> null
            }
            assertEquals(reason?.let { "First Light was not removed. $it" }
                ?: "Your AO3 session changed, so nothing was removed.", model.state.value.error)
        }
    }
}

internal fun seriesFixture(name: String): String = listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures", "android/app/src/debug/assets/fixtures")
    .map { File(it, "$name.html") }.first { it.isFile }.readText()
internal fun seriesResponse(code: Int, body: String): AO3Result<AO3HttpResponse> =
    AO3Result.Success(AO3HttpResponse(AO3SeriesFormUrls.show(321), code, emptyMap(), body))
internal data class SeriesPost(val url: String, val fields: List<Pair<String, String>>, val headers: Map<String, String>)
internal class SeriesTestClient(private val auth: AO3AuthRepository) : AO3AuthenticatedClient {
    val gets = mutableListOf<String>()
    val posts = mutableListOf<SeriesPost>()
    var manage = seriesFixture("ao3_demo_series_manage")
    var getFailure: AO3Error? = null
    var failManageOnly = false
    var postResponse = seriesResponse(200, "<main id='main'><div class='flash notice'>Series was successfully updated.</div></main>")
    var beforePost: suspend () -> Unit = {}
    var beforeGet: suspend () -> Unit = {}
    var applyOrder = true
    var failReadBack = false
    override fun username() = auth.username()
    override fun sessionGeneration() = auth.generation.value
    override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> {
        gets += url; beforeGet()
        if (failReadBack && posts.isNotEmpty()) return AO3Result.Failure(AO3Error.Forbidden)
        getFailure?.let { if (!failManageOnly || url.endsWith("/manage")) return AO3Result.Failure(it) }
        return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), if (url.endsWith("/manage")) manage else seriesFixture("ao3_demo_series_edit")))
    }
    override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        posts += SeriesPost(url, formFields, headers); beforePost()
        if (postResponse is AO3Result.Success && applyOrder) {
            val doc = org.jsoup.Jsoup.parse(manage); val list = doc.selectFirst("#sortable_series_list")!!
            if (url.endsWith("/update_positions")) {
                val rows = list.select("li").associateBy { it.id().removePrefix("serial_") }
                list.empty(); formFields.filter { it.first == "serial[]" }.forEach { list.appendChild(rows.getValue(it.second)) }
            } else if (url.contains("/serial_works/")) doc.getElementById("serial_${url.substringAfterLast('/')}")?.remove()
            list.select("li").forEachIndexed { index, row -> row.selectFirst("[id^=position-for-]")?.text((index + 1).toString()) }
            manage = doc.outerHtml()
        }
        return postResponse
    }
}
internal data class SeriesSetup(val auth: AO3AuthRepository, val client: SeriesTestClient, val repository: AO3SeriesFormRepository,
    val writes: AO3WriteRepository) {
    fun model(reorderOnly: Boolean = false) = WritingSeriesState(321, repository, writes, reorderOnly)
}
internal suspend fun seriesSetup(signedIn: Boolean = true): SeriesSetup {
    val auth = AO3AuthRepository(MemorySessionStore(if (signedIn) testSession() else null), MemoryCookieStore())
    auth.restoreSession()
    val client = SeriesTestClient(auth)
    return SeriesSetup(auth, client, AO3SeriesFormRepository(client, auth, parseDispatcher = Dispatchers.Unconfined), AO3WriteRepository(client))
}
