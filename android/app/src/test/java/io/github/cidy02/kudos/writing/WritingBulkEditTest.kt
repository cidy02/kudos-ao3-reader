package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields
import io.github.cidy02.kudos.network.ao3.writing.*
import io.github.cidy02.kudos.network.ao3.writes.*
import kotlinx.coroutines.*
import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test

/** Literal Swift fields, independently specified, against a recording authenticated client. */
class WritingBulkEditTest {
    @Test fun renderingUniformAndDeleteRequestsMatchSwiftForOneAndSeveralWorks() = runBlocking<Unit> {
        for (ids in listOf(listOf(11L), listOf(11L, 22L, 33L))) {
            val client = BulkRecordingClient(ids); val writes = AO3WriteRepository(client)
            val opening = writes.loadBulkEditForm(ids, 7)
            assertTrue(opening is AO3Result.Success)
            assertEquals(listOf("GET https://archiveofourown.org/works/11/edit", "POST https://archiveofourown.org/users/AO3_Reader/works/edit_multiple"), client.requests)
            assertEquals(listOf("authenticity_token" to "fresh==") + ids.map { "work_ids[]" to it.toString() }, client.posts.single().fields)
            assertEquals(mapOf("X-CSRF-Token" to "fresh==", "Referer" to "https://archiveofourown.org/users/AO3_Reader/works/edit_multiple"), client.posts.single().headers)
            client.clear()
            val changes = AO3BulkEditChanges(ids, scalars = mapOf("work[rating_string]" to "Explicit", "work[language_id]" to "2",
                "work[restricted]" to "0", "work[moderated_commenting_enabled]" to "1", "work[comment_permissions]" to "disable_anon", "work[work_skin_id]" to "9"),
                collectionsToAdd = listOf("  New collection  ", "星"), collectionsToRemove = listOf("old_bang", "second"), pseudsToAdd = "Pseud & 星", removesSelf = true)
            assertTrue(writes.bulkEditWorks(changes, 7) is AO3Result.Success)
            assertEquals(listOf("GET https://archiveofourown.org/works/11/edit", "POST https://archiveofourown.org/users/AO3_Reader/works/update_multiple"), client.requests)
            assertEquals(listOf("authenticity_token" to "fresh==", "_method" to "patch") + ids.map { "work_ids[]" to it.toString() } + listOf(
                "work[rating_string]" to "Explicit", "work[language_id]" to "2", "work[collections_to_add]" to "New collection, 星",
                "work[collections_to_remove][]" to "old_bang", "work[collections_to_remove][]" to "second", "work[restricted]" to "0",
                "work[moderated_commenting_enabled]" to "1", "work[comment_permissions]" to "disable_anon", "work[work_skin_id]" to "9", "work[pseuds_to_add]" to "Pseud & 星", "remove_me" to "1"), client.posts.single().fields)
            assertEquals(mapOf("X-CSRF-Token" to "fresh==", "Referer" to "https://archiveofourown.org/users/AO3_Reader/works/update_multiple"), client.posts.single().headers)
            client.clear()
            assertTrue(writes.deleteWorks(ids, 7) is AO3Result.Success)
            assertEquals(listOf("GET https://archiveofourown.org/users/AO3_Reader/works/show_multiple", "POST https://archiveofourown.org/users/AO3_Reader/works/delete_multiple"), client.requests)
            assertEquals(listOf("authenticity_token" to "fresh==") + ids.map { "work_ids[]" to it.toString() } + ("commit" to "Yes, Delete Works"), client.posts.single().fields)
            assertEquals(mapOf("X-CSRF-Token" to "fresh==", "Referer" to "https://archiveofourown.org/users/AO3_Reader/works/show_multiple"), client.posts.single().headers)
        }
    }

    @Test fun tagsAreMergedPerWorkAndNeverSentToUpdateMultipleAndStopAtRefusal() = runBlocking<Unit> {
        val client = BulkRecordingClient(listOf(11, 22)); val writes = AO3WriteRepository(client)
        val changes = AO3BulkEditChanges(client.ids, added = mapOf("work[freeform_string]" to listOf("Fluff", "Maps", "remove me")),
            removed = mapOf("work[freeform_string]" to listOf("REMOVE ME")), scalars = mapOf("work[rating_string]" to "Explicit"))
        val current = AO3WorkFormParser().parse(client.tagPage(11), AO3WorkFormUrls.editTags(11))
        val merged = changes.applying(current.copy(additionalTags = listOf("Maps", "maps", "remove me", "Own tag")))
        assertEquals(listOf("Maps", "Own tag", "Fluff"), merged.additionalTags)
        assertTrue(writes.bulkEditWorks(changes, 7) is AO3Result.Success)
        assertEquals(listOf("GET https://archiveofourown.org/works/11/edit_tags", "GET https://archiveofourown.org/works/11/edit_tags",
            "POST https://archiveofourown.org/works/11/update_tags", "GET https://archiveofourown.org/works/22/edit_tags", "GET https://archiveofourown.org/works/22/edit_tags",
            "POST https://archiveofourown.org/works/22/update_tags", "GET https://archiveofourown.org/works/11/edit", "POST https://archiveofourown.org/users/AO3_Reader/works/update_multiple"), client.requests)
        for ((index, post) in client.posts.take(2).withIndex()) {
            val id = client.ids[index]
            assertEquals(listOf("authenticity_token" to "demo-tags-$id==", "_method" to "patch", "work[rating_string]" to "Explicit",
                "work[archive_warning_strings][]" to "No Archive Warnings Apply", "work[category_strings][]" to "Gen", "work[category_strings][]" to "Multi",
                "work[fandom_string]" to "Mill Lantern Chronicles, 星の地図", "work[relationship_string]" to "Mira & Sol, 河 / 海",
                "work[character_string]" to "Mira \"Mapmaker\", Sol & Echo", "work[freeform_string]" to "Own $id, Maps, Fluff",
                "work[language_id]" to "1", "update_button" to "1", "utf8" to "✓", "work[served_only][]" to "first", "work[served_only][]" to "星 & second"), post.fields)
            assertEquals(AO3WorkFormUrls.editTags(id), post.headers["Referer"])
        }
        assertFalse(client.posts.last().fields.any { it.first in changes.added.keys })
        client.clear(); client.refuseTagID = 11
        val failure = writes.bulkEditWorks(changes, 7) as AO3Result.Failure
        assertEquals(AO3Error.Validation("Refused 11"), failure.error)
        assertEquals(3, client.requests.size); assertEquals(1, client.posts.size)
    }

    @Test fun formChoicesComeOnlyFromServedHtmlAndBlankChoicesAreNotInvented() {
        val form = AO3BulkEditParser.parse(BulkRecordingClient(listOf(11L)).bulkPage(), "https://archiveofourown.org/users/AO3_Reader/works/edit_multiple", listOf(11))
        assertEquals(listOf("The Weight of Water", "Salt and Static", "Long Way from Home"), form.titles)
        assertEquals(listOf("", "General Audiences", "Explicit"), form.options.getValue("work[rating_string]").map { it.value })
        assertEquals(listOf("", "1", "0"), form.options.getValue("work[restricted]").map { it.value })
        assertEquals("Old Bang", form.options.getValue("work[collections_to_remove][]").single().title)
        assertEquals(listOf("", "enable_all", "disable_anon", "disable_all"), form.options.getValue("work[comment_permissions]").map { it.value })
    }

    @Test fun allVerdictsKeepDraftAndClearBusyWithNoReadbackOrRetry() = runBlocking<Unit> {
        for ((status, html, reason) in listOf(
            Triple(200, "<main id=main><div class='flash notice'>Saved.</div></main>", null), Triple(302, "", null),
            Triple(422, "<main id=main><div class='flash error'>AO3 says no 星</div></main>", "AO3 says no 星"),
            Triple(302, "<main id=main><div class='flash error'>No</div><div class='flash notice'>Saved</div></main>", "No"),
            Triple(200, "<form><textarea>successfully saved</textarea></form>", AO3CollectionFields.UNCONFIRMED),
            Triple(204, "", AO3CollectionFields.UNCONFIRMED), Triple(400, "", "AO3 didn't accept the change."))) {
            val client = BulkRecordingClient(listOf(11)); val model = WritingBulkEditState(client.ids, AO3WriteRepository(client), 7)
            model.load(); model.change { it.copy(pseudsToAdd = "Typed & 星") }
            val before = model.state.value.changes
            client.clear(); client.status = status; client.reply = html
            model.save()
            assertEquals(before, model.state.value.changes); assertNotNull(model.state.value.form)
            assertEquals(reason, model.state.value.saveError); assertEquals(reason == null, model.state.value.saved)
            assertFalse(model.state.value.saving); assertFalse(model.state.value.loading)
            assertEquals(2, client.requests.size); assertEquals(1, client.posts.size)
            model.load(retry = true); assertEquals(2, client.requests.size)
            if (reason == null) { model.save(); assertEquals(1, client.posts.size) }
            val delete = io.github.cidy02.kudos.author.OwnWorksDeleteState(AO3WriteRepository(client), 7)
            delete.ask(listOf(bulkSummary(11))); client.clear(); delete.confirm()
            assertEquals(reason, delete.state.value.error); assertEquals(if (reason == null) 1 else 0, delete.state.value.confirmed)
            assertFalse(delete.state.value.busy); assertEquals(2, client.requests.size)
        }
    }

    @Test fun failedPreparationSignedOutAndSessionMovesDoNotReplayOrLeaveBusy() = runBlocking<Unit> {
        for (mode in listOf("read", "out", "before", "during", "after", "expired", "throw")) {
            val client = BulkRecordingClient(listOf(11)); val writes = AO3WriteRepository(client)
            val model = WritingBulkEditState(client.ids, writes, 7).also { it.load() }
            model.change { it.copy(pseudsToAdd = "Typed") }; client.clear()
            when (mode) {
                "read" -> client.getFailure = AO3Error.Forbidden
                "out" -> client.user = null
                "before" -> client.generation = 8
                "during" -> client.beforeGet = { client.generation = 8 }
                "after" -> client.beforePostReply = { client.generation = 8 }
                "expired" -> { client.beforePostReply = { client.generation = 8 }; client.postFailure = AO3Error.AuthenticationRequired }
                "throw" -> client.beforePostReply = { throw java.io.IOException("lost") }
            }
            model.save()
            assertFalse(model.state.value.saving); assertNotNull(model.state.value.saveError); assertEquals("Typed", model.state.value.changes.pseudsToAdd)
            assertEquals(if (mode in listOf("after", "expired", "throw")) 1 else 0, client.posts.size)
            if (mode == "after") assertEquals(AO3CollectionFields.UNCONFIRMED, model.state.value.saveError)
            if (mode == "expired") assertEquals("Your AO3 session expired. Please log in again.", model.state.value.saveError)
            val delete = io.github.cidy02.kudos.author.OwnWorksDeleteState(writes, 7)
            delete.ask(listOf(bulkSummary(11))); client.clear(); delete.confirm()
            assertFalse(delete.state.value.busy); assertEquals(0, delete.state.value.confirmed)
        }
        val client = BulkRecordingClient(listOf(11)); val model = WritingBulkEditState(client.ids, AO3WriteRepository(client), 7)
        client.getFailure = AO3Error.Forbidden; model.load(); model.load()
        assertEquals(1, client.requests.size); assertFalse(model.state.value.loading)
        client.getFailure = null; model.load(retry = true); assertNotNull(model.state.value.form)
    }

    @Test fun missingMetaTokenSignedOutAndFailedRenderingAreTerminalUntilExplicitRetry() = runBlocking<Unit> {
        val client = BulkRecordingClient(listOf(11)); val writes = AO3WriteRepository(client)
        client.user = null
        assertEquals(AO3Result.Failure(AO3Error.Validation("Log in to AO3 first.")), writes.deleteWorks(client.ids, 7))
        assertEquals(AO3Result.Failure(AO3Error.Validation("Log in to AO3 first.")), writes.loadBulkEditForm(client.ids, 7))
        assertTrue(client.requests.isEmpty())
        client.user = "AO3_Reader"; client.readBody = "<form><input name='authenticity_token' value='input-only'></form>"
        val answer = writes.bulkEditWorks(AO3BulkEditChanges(client.ids, pseudsToAdd = "Writer"), 7)
        assertEquals(AO3Result.Failure(AO3Error.Validation("Couldn't prepare the request. Try again, or open the form on AO3.")), answer)
        assertEquals(1, client.requests.size); assertTrue(client.posts.isEmpty())
        client.readBody = null; client.postFailure = AO3Error.Forbidden; client.clear()
        val model = WritingBulkEditState(client.ids, writes, 7)
        model.load(); model.load()
        assertFalse(model.state.value.loading); assertNotNull(model.state.value.failure)
        assertEquals(2, client.requests.size); assertEquals(1, client.posts.size)
        client.postFailure = null; model.load(retry = true); assertNotNull(model.state.value.form)
    }

    @Test fun secondTagReadSuppliesFreshTokenAndActionWhileFirstReadSuppliesMergedLists() = runBlocking<Unit> {
        val client = BulkRecordingClient(listOf(11)); var reads = 0
        client.beforeGet = {
            reads++
            client.readBody = client.tagPage(11).let { if (reads == 1) it else it.replace("demo-tags-11==", "fresh-second==") }
        }
        val answer = AO3WriteRepository(client).bulkEditWorks(AO3BulkEditChanges(client.ids,
            added = mapOf("work[freeform_string]" to listOf("Fluff"))), 7)
        assertTrue(answer is AO3Result.Success); assertEquals(2, reads); assertEquals(1, client.posts.size)
        assertEquals("fresh-second==", client.posts.single().headers["X-CSRF-Token"])
        assertEquals("fresh-second==", client.posts.single().fields.first { it.first == "authenticity_token" }.second)
    }

    @Test fun defaultAuthenticatedClientAddsOnlyItsSessionCookieAndFencesBeforePost() = runBlocking<Unit> {
        val setup = workFormSetup()
        val writes = setup.writes
        val ids = listOf(995006L)
        setup.client.postBody = "<main id=main><div class='flash notice'>Saved.</div></main>"
        assertTrue(writes.bulkEditWorks(AO3BulkEditChanges(ids, pseudsToAdd = "Writer"), setup.auth.generation.value) is AO3Result.Success)
        assertEquals(1, setup.client.gets.size); assertEquals(1, setup.client.posts)
        assertTrue(setup.client.recordedPosts.single().headers.getValue("Cookie").isNotBlank())
        assertFalse(setup.client.recordedPosts.single().headers.containsKey("X-Requested-With"))
        assertFalse(setup.client.recordedPosts.single().headers.containsKey("Accept"))
    }

    @Test fun deletionUsesTheNamedSnapshotAndSecondTapWhileBusySendsNothing() = runBlocking<Unit> {
        val client = BulkRecordingClient(listOf(11, 22)); val delete = io.github.cidy02.kudos.author.OwnWorksDeleteState(AO3WriteRepository(client), 7)
        val named = mutableListOf(bulkSummary(11), bulkSummary(22))
        delete.ask(named); named.clear()
        val started = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
        client.beforePostReply = { started.complete(Unit); release.await() }
        val task = async { delete.confirm() }; started.await()
        delete.ask(listOf(bulkSummary(33))); delete.confirm()
        assertTrue(delete.state.value.busy); assertEquals(1, client.posts.size)
        assertEquals(listOf("11", "22"), client.posts.single().fields.filter { it.first == "work_ids[]" }.map { it.second })
        release.complete(Unit); task.await()
        assertFalse(delete.state.value.busy); assertEquals(1, delete.state.value.confirmed)
    }

    @Test fun servedIdsDetermineBulkSaveOrderWithoutAcceptingUnselectedWorks() {
        val client = BulkRecordingClient(listOf(11, 22))
        val reordered = client.bulkPage(listOf(22, 11))
        assertEquals(listOf(22L, 11L), AO3BulkEditParser.parse(reordered,
            "https://archiveofourown.org/users/AO3_Reader/works/edit_multiple", client.ids).workIDs)
        try {
            AO3BulkEditParser.parse(client.bulkPage(listOf(22, 33)),
                "https://archiveofourown.org/users/AO3_Reader/works/edit_multiple", client.ids)
            fail("Unselected work must not be adopted")
        } catch (_: IllegalArgumentException) { }
    }

    @Test fun nothingChangedCancelAndBusySecondTapSendNothing() = runBlocking<Unit> {
        val client = BulkRecordingClient(listOf(11)); val model = WritingBulkEditState(client.ids, AO3WriteRepository(client), 7)
        model.load(); client.clear(); model.save(); assertTrue(client.requests.isEmpty())
        val next = WritingBulkEditState(client.ids, AO3WriteRepository(client), 7).also { it.load() }
        next.change { it.copy(pseudsToAdd = "Typed") }; client.clear()
        val started = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
        client.beforeGet = { started.complete(Unit); release.await() }
        val pending = async { next.save() }; started.await()
        next.save(); next.load(retry = true)
        assertEquals(1, client.requests.size); assertTrue(client.posts.isEmpty())
        release.complete(Unit); pending.await(); assertFalse(next.state.value.saving)
        val delete = io.github.cidy02.kudos.author.OwnWorksDeleteState(AO3WriteRepository(client), 7)
        client.clear(); delete.ask(listOf(bulkSummary(11))); delete.cancel(); delete.confirm()
        assertTrue(client.requests.isEmpty())
    }
}

internal fun bulkSummary(id: Long) = io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary(id, "Title $id", listOf("A displayed pseud"), emptyList(), "General Audiences", emptyList(), emptyList())
internal class BulkRecordingClient(val ids: List<Long>) : AO3AuthenticatedClient {
    var user: String? = "AO3_Reader"; var generation = 7
    val requests = mutableListOf<String>(); val posts = mutableListOf<WorkFormPost>()
    var readBody: String? = null
    var getFailure: AO3Error? = null; var postFailure: AO3Error? = null
    var status = 200; var reply = "<main id=main><div class='flash notice'>Saved.</div></main>"
    var refuseTagID: Long? = null
    var beforeGet: suspend () -> Unit = {}; var beforePostReply: suspend () -> Unit = {}
    override fun username() = user
    override fun sessionGeneration() = generation
    fun clear() { requests.clear(); posts.clear() }
    fun bulkPage(desiredIDs: List<Long> = ids): String = Jsoup.parse(workFixture("ao3_edit_multiple")).apply {
        select("input[name]").filter { it.attr("name") == "work_ids[]" }.forEach { it.remove() }
        desiredIDs.forEach { selectFirst("form")!!.appendElement("input").attr("name", "work_ids[]").attr("value", it.toString()) }
    }.outerHtml()
    fun tagPage(id: Long): String = Jsoup.parse(workFixture("ao3_demo_work_edit_tags").replace("995006", id.toString())).apply {
        select("input[name]").first { it.attr("name") == "work[freeform_string]" }.attr("value", "Own $id, Maps, remove me")
    }.outerHtml()
    override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> {
        requests += "GET $url"; beforeGet(); getFailure?.let { return AO3Result.Failure(it) }
        val html = readBody ?: if (url.endsWith("edit_tags")) tagPage(url.substringAfter("/works/").substringBefore('/').toLong())
            else "<meta name='csrf-token' content='fresh=='>"
        return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), html))
    }
    override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        requests += "POST $url"; posts += WorkFormPost(url, formFields, headers); beforePostReply()
        postFailure?.let { return AO3Result.Failure(it) }
        if (url.endsWith("edit_multiple")) return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), bulkPage(formFields.filter { it.first == "work_ids[]" }.map { it.second.toLong() })))
        val refusal = refuseTagID?.let { url.endsWith("/works/$it/update_tags") } == true
        return AO3Result.Success(AO3HttpResponse(url, if (refusal) 422 else status, emptyMap(),
            if (refusal) "<main id=main><div class='flash error'>Refused $refuseTagID</div></main>" else reply))
    }
}
