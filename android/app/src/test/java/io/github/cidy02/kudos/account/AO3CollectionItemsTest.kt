package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.*
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test

class AO3CollectionItemsTest {
    private val parser = AO3CollectionItemsParser()
    private fun page(html: String = fixture()) = parser.parse(html, "winter_exchange", AO3CollectionItemTab.Unreviewed, 1)

    @Test fun parsesOriginalFixtureControlsIdentityTokenMethodAndPaging() {
        val page = page()
        assertEquals(13, page.items.size)
        val item = page.items.first()
        assertEquals(41, item.id)
        assertEquals("The Lantern Ledger", item.workTitle)
        assertEquals("Winter Exchange 2026", item.collectionTitle)
        assertEquals("Member", item.role)
        assertEquals("winterquill (Member)", item.creatorByline)
        assertEquals("17 Jan 2026", item.dateText)
        assertEquals(AO3CollectionItemApproval.Approved, item.creatorApproval)
        assertEquals(AO3CollectionItemApproval.Unreviewed, item.moderatorApproval)
        assertFalse(item.creatorEditable)
        assertTrue(item.moderatorEditable && item.unrevealedEditable && item.anonymousEditable && item.removeEditable)
        assertTrue(item.unrevealed)
        assertFalse(item.anonymous)
        assertEquals("demo-items-token", page.csrfToken)
        assertEquals("patch", page.methodOverride)
        assertEquals("https://archiveofourown.org/collections/winter_exchange/items/update_multiple", page.actionUrl)
        val paged = parser.parse(fixture().replace("</form>", "</form><ol class='pagination'><li>1</li><li>7</li></ol>"),
            "winter_exchange", AO3CollectionItemTab.Approved, 3)
        assertEquals(3, paged.currentPage)
        assertEquals(7, paged.totalPages)
        assertEquals(AO3CollectionItemTab.Approved, paged.tab)
    }

    @Test fun parametersMatchIosAndCarryTheServedTokenAndOverride() {
        val served = page(fixture().replace("value=\"patch\"", "value=\"put\""))
        val draft = AO3CollectionItemDraft(41, moderatorApproval = AO3CollectionItemApproval.Rejected,
            unrevealed = false, anonymous = true)
        assertEquals(listOf("authenticity_token" to "demo-items-token", "_method" to "put",
            "collection_items[41][collection_approval_status]" to "rejected",
            "collection_items[41][unrevealed]" to "0", "collection_items[41][anonymous]" to "1"), draft.parameters(served))
        assertEquals(listOf("authenticity_token" to "demo-items-token", "_method" to "put",
            "collection_items[41][remove]" to "1"), AO3CollectionItemDraft(41, remove = true).parameters(served))
        assertEquals("patch", draft.parameters(served.copy(methodOverride = null)).toMap()["_method"])
    }

    @Test fun stagingRevertsBaselineExcludesDisabledAndOffPageAndRemovalReplacesEdits() {
        val item = page().items.first()
        var staging = AO3CollectionItemStaging().set(item) { it.copy(moderatorApproval = AO3CollectionItemApproval.Approved) }
        assertEquals(1, staging.pending(listOf(item)).size)
        assertTrue(staging.pending(emptyList()).isEmpty())
        staging = staging.set(item) { it.copy(moderatorApproval = item.moderatorApproval) }
        assertTrue(staging.pending(listOf(item)).isEmpty())
        staging = staging.set(item) { it.copy(creatorApproval = AO3CollectionItemApproval.Rejected) }
        assertTrue(staging.pending(listOf(item)).isEmpty())
        staging = staging.set(item) { it.copy(anonymous = true) }.remove(item, true)
        assertEquals(AO3CollectionItemDraft(item.id, remove = true), staging.shown(item))
        staging = staging.remove(item, false)
        assertTrue(staging.pending(listOf(item)).isEmpty())
        assertEquals(listOf(41, 43), AO3CollectionItemStaging(mapOf(
            43 to AO3CollectionItemDraft(43, remove = true), 41 to AO3CollectionItemDraft(41, remove = true)
        )).pending(page().items).map { it.itemId })
    }

    @Test fun malformedLoginAndUntrustedFormsAreErrorsRecognizedEmptyIsEmpty() {
        for (html in listOf("<p>Unknown</p>", "<form id='new_user' action='/users/login'></form>",
            fixture().replace("/collections/winter_exchange/items/update_multiple", "https://example.com/items"))) {
            assertThrows(IllegalArgumentException::class.java) { page(html) }
        }
        assertTrue(page("<h2 class='heading'>Collection Items</h2><p class='note'>No items.</p>").items.isEmpty())
    }

    @Test fun oneFreshFormThenOrderedNonoverlappingPostsAndAuthoritativeSuccessRefresh() = runTest {
        val (auth, client, state) = setup()
        state.load()
        val items = state.state.value.page!!.items
        // Stage in reverse order: iOS pendingDrafts sorts by item id.
        state.remove(items.first { it.id == 43 })
        state.stage(items.first { it.id == 41 }) { it.copy(moderatorApproval = AO3CollectionItemApproval.Approved) }
        client.holdPost = true
        val confirmed = async { state.confirmSubmit() }
        client.postEntered.await()
        state.confirmSubmit() // Double tap while the first item is out cannot send again.
        assertEquals(1, client.posts.size)
        assertEquals(2, client.gets.size) // Initial read plus exactly one fresh form read.
        client.postRelease.complete(Unit)
        confirmed.await()
        assertEquals(listOf(41, 43), client.posts.map { id(it) })
        assertEquals(1, client.maximumPosts)
        assertEquals(3, client.gets.size) // Verification only after the batch.
        assertEquals(13 - 1, state.state.value.page!!.items.size) // Reflected removal, from the read response.
        assertEquals(AO3CollectionItemApproval.Approved,
            state.state.value.page!!.items.first { it.id == 41 }.moderatorApproval)
        assertTrue(state.state.value.pending.isEmpty())
        assertNull(state.state.value.submitError)
        assertEquals(auth.generation.value, client.generations.single())
    }

    @Test fun submitUsesOneFreshServedActionTokenAndMethodInsteadOfTheDisplayedForm() = runTest {
        val (_, client, state) = setup()
        state.load()
        state.remove(state.state.value.page!!.items.first())
        client.html = fixture().replace("demo-items-token", "fresh-token")
            .replace("value=\"patch\"", "value=\"put\"")
            .replace("items/update_multiple", "items/update_multiple?fresh=1")
        state.confirmSubmit()
        assertEquals(1, client.posts.size)
        assertEquals("fresh-token", client.posts.single().toMap()["authenticity_token"])
        assertEquals("put", client.posts.single().toMap()["_method"])
        assertEquals("https://archiveofourown.org/collections/winter_exchange/items/update_multiple?fresh=1", client.postUrls.single())
        assertEquals("fresh-token", client.postHeaders.single()["X-CSRF-Token"])
        assertEquals("https://archiveofourown.org/collections/winter_exchange/items", client.postHeaders.single()["Referer"])
        assertEquals(3, client.gets.size)
    }

    @Test fun refusalStopsRemainingItemsAndRefreshShowsEarlierSuccessAndRefusedServerValue() = runTest {
        val (_, client, state) = setup()
        client.refuse = 42
        state.load()
        state.state.value.page!!.items.filter { it.id in 41..43 }.forEach { item ->
            state.stage(item) { it.copy(moderatorApproval = AO3CollectionItemApproval.Approved) }
        }
        state.confirmSubmit()
        assertEquals(listOf(41, 42), client.posts.map { id(it) })
        assertEquals(1, client.maximumPosts)
        assertEquals("AO3 couldn't update that collection item.", state.state.value.submitError)
        val rows = state.state.value.page!!.items
        assertEquals(AO3CollectionItemApproval.Approved, rows.first { it.id == 41 }.moderatorApproval)
        assertEquals(AO3CollectionItemApproval.Unreviewed, rows.first { it.id == 42 }.moderatorApproval)
        assertEquals(AO3CollectionItemApproval.Unreviewed, rows.first { it.id == 43 }.moderatorApproval)
        assertEquals(listOf(42, 43), state.state.value.pending.map { it.itemId })
    }

    @Test fun discardNeverPostsAndRefreshAndPageTabLoadsDoNotReadAheadOrDropOtherDrafts() = runTest {
        val (_, client, state) = setup()
        state.load()
        val item = state.state.value.page!!.items.first()
        state.remove(item)
        state.load(AO3CollectionItemTab.Approved, 2)
        assertEquals(2, client.gets.size)
        assertTrue(client.gets.last().contains("status=approved&page=2"))
        assertTrue(state.state.value.staging.drafts.containsKey(item.id))
        state.discard()
        state.confirmSubmit()
        assertTrue(client.posts.isEmpty())
        assertTrue(state.state.value.staging.drafts.isEmpty())
    }

    @Test fun loadingEmptyFailureSignedOutAndNotMaintainerStates() = runTest {
        val (_, client, state) = setup()
        client.holdGet = true
        val load = async { state.load() }
        client.getEntered.await()
        assertEquals(AO3CollectionItemsUiState.Phase.Loading, state.state.value.phase)
        client.getRelease.complete(Unit)
        load.await()
        assertEquals(AO3CollectionItemsUiState.Phase.Loaded, state.state.value.phase)
        client.getError = AO3Error.Forbidden
        state.load(page = 2)
        assertEquals(AO3CollectionItemsUiState.Phase.NotMaintainer, state.state.value.phase)
        assertEquals(1, state.state.value.page!!.currentPage)
        client.getError = AO3Error.Network("offline")
        state.load()
        assertEquals(AO3CollectionItemsUiState.Phase.Failed, state.state.value.phase)
        client.getError = null
        client.html = "<h2 class='heading'>Collection Items</h2><p class='note'>No items.</p>"
        state.load()
        assertTrue(state.state.value.page!!.items.isEmpty())
        val signedOut = AO3AuthRepository(MemorySessionStore(null), MemoryCookieStore())
        signedOut.restoreSession()
        val out = ItemsClient(signedOut)
        val outState = AO3CollectionItemsState("winter_exchange", AO3CollectionDetailRepository(out, signedOut), AO3WriteRepository(out))
        outState.load()
        assertEquals(AO3CollectionItemsUiState.Phase.SignedOut, outState.state.value.phase)
        assertEquals(AO3CollectionItemsState.SIGNED_OUT, outState.state.value.loadError)
        assertTrue(out.gets.isEmpty())
    }

    @Test fun sessionChangeWhileInitialPageIsOutLeavesItUninstalled() = runTest {
        val (auth, client, state) = setup()
        client.holdGet = true
        val read = async { state.load() }
        client.getEntered.await()
        auth.logout()
        client.getRelease.complete(Unit)
        read.join()
        assertNull(state.state.value.page)
        assertTrue(state.state.value.staging.drafts.isEmpty())
        assertTrue(client.posts.isEmpty())
    }

    @Test fun sessionChangeDuringReadDoesNotInstallRowsOrPreparePost() = runTest {
        val (auth, client, state) = setup()
        state.load()
        state.remove(state.state.value.page!!.items.first())
        client.holdGet = true
        val submit = async { state.confirmSubmit() }
        client.getEntered.await()
        val before = state.state.value
        auth.logout()
        client.getRelease.complete(Unit)
        submit.await()
        assertEquals(before, state.state.value)
        assertTrue(client.posts.isEmpty())
    }

    @Test fun sessionChangeAfterFirstPostStopsLoopAndDoesNotTouchOldList() = runTest {
        val (auth, client, state) = setup()
        state.load()
        state.state.value.page!!.items.take(3).forEach { state.remove(it) }
        client.afterPost = { auth.logout() }
        val previousPage = state.state.value.page
        state.confirmSubmit()
        assertEquals(1, client.posts.size)
        assertEquals(2, client.gets.size) // No verification in replacement session.
        assertEquals(previousPage, state.state.value.page)
        assertEquals(3, state.state.value.staging.drafts.size)
        assertNull(state.state.value.submitError)
    }

    @Test fun plain200IsUnconfirmedAndTransportFailureIsNeverRetried() = runTest {
        for (reply in listOf(response("<p>No confirmation</p>"), AO3Result.Failure(AO3Error.Network("Lost reply")))) {
            val (_, client, state) = setup()
            client.postReply = reply
            state.load()
            state.state.value.page!!.items.take(2).forEach { state.remove(it) }
            state.confirmSubmit()
            assertEquals(1, client.posts.size)
            assertNotNull(state.state.value.submitError)
            assertEquals(2, state.state.value.pending.size)
        }
    }

    private suspend fun setup(): Triple<AO3AuthRepository, ItemsClient, AO3CollectionItemsState> {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val client = ItemsClient(auth)
        return Triple(auth, client, AO3CollectionItemsState("winter_exchange",
            AO3CollectionDetailRepository(client, auth), AO3WriteRepository(client)))
    }
}

private fun fixture(): String = listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures", "android/app/src/debug/assets/fixtures")
    .map { File(it, "ao3_demo_collection_items.html") }.first { it.isFile }.readText()

private fun response(html: String, status: Int = 200) = AO3Result.Success(AO3HttpResponse(
    "https://archiveofourown.org/collections/winter_exchange/items", status, emptyMap(), html
))

private fun id(fields: List<Pair<String, String>>) = fields.first { it.first.startsWith("collection_items[") }
    .first.substringAfter('[').substringBefore(']').toInt()

/** All requests terminate in memory; production HTTP clients are never constructed. */
private class ItemsClient(private val auth: AO3AuthRepository) : AO3Client, AO3AuthenticatedClient {
    var html = fixture()
    val gets = mutableListOf<String>()
    val posts = mutableListOf<List<Pair<String, String>>>()
    val generations = mutableSetOf<Int?>()
    val postUrls = mutableListOf<String>()
    val postHeaders = mutableListOf<Map<String, String>>()
    var activePosts = 0
    var maximumPosts = 0
    var refuse: Int? = null
    var getError: AO3Error? = null
    var postReply: AO3Result<AO3HttpResponse>? = null
    var afterPost: (suspend () -> Unit)? = null
    var holdGet = false
    var holdPost = false
    val getEntered = CompletableDeferred<Unit>()
    val getRelease = CompletableDeferred<Unit>()
    val postEntered = CompletableDeferred<Unit>()
    val postRelease = CompletableDeferred<Unit>()
    override fun username() = auth.username()
    override fun sessionGeneration() = auth.generation.value
    override suspend fun getAuthenticated(url: String) = get(url, emptyMap())
    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        gets += url
        if (holdGet) { getEntered.complete(Unit); getRelease.await() }
        getError?.let { return AO3Result.Failure(it) }
        return response(html)
    }
    override suspend fun postAuthenticatedInSession(url: String, formFields: List<Pair<String, String>>,
        headers: Map<String, String>, generation: Int?): AO3Result<AO3HttpResponse> {
        if (generation != sessionGeneration()) throw kotlinx.coroutines.CancellationException()
        generations.add(generation)
        return postAuthenticated(url, formFields, headers)
    }
    override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>,
        headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        posts += formFields
        postUrls += url
        postHeaders += headers
        activePosts++
        maximumPosts = maxOf(maximumPosts, activePosts)
        if (holdPost) { postEntered.complete(Unit); postRelease.await() }
        val reply = postReply ?: if (id(formFields) == refuse) {
            response("<div class='flash error'>AO3 couldn't update that collection item.</div>", 422)
        } else {
            val doc = Jsoup.parse(html)
            formFields.filter { it.first.startsWith("collection_items[") }.forEach { (name, value) ->
                val control = doc.select("select, input[type=checkbox]").first { it.attr("name") == name }
                if (name.endsWith("[remove]")) control.closest("li.collection.item")!!.remove()
                else if (control.tagName() == "select") control.select("option").forEach { option ->
                    option.removeAttr("selected")
                    if (option.attr("value") == value) option.attr("selected", "selected")
                } else {
                    control.removeAttr("checked")
                    if (value == "1") control.attr("checked", "checked")
                }
            }
            html = doc.outerHtml()
            response("<div class='flash notice'>Updated.</div>")
        }
        afterPost?.invoke()
        activePosts--
        return reply
    }
}
