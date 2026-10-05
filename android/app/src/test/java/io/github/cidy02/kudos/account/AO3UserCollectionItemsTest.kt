package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.app.Routes
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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test

class AO3UserCollectionItemsTest {
    private val parser = AO3CollectionItemsParser()
    private fun page(html: String = userItemsFixture()) = parser.parseUser(html, "AO3_Reader", AO3CollectionItemTab.Invited, 1)

    @Test fun accountAddressesDefaultsAndResetMatchIosWithoutChangingCollectionQueries() {
        val root = "https://archiveofourown.org/users/AO3_Reader/collection_items"
        assertEquals(root, AO3CollectionItemsUrls.userPage("AO3_Reader", AO3CollectionItemTab.Invited, 1))
        assertEquals("$root?status=unreviewed_by_collection&page=2",
            AO3CollectionItemsUrls.userPage("AO3_Reader", AO3CollectionItemTab.Unreviewed, 2))
        assertEquals("$root?status=rejected_by_collection", AO3CollectionItemsUrls.userPage("AO3_Reader", AO3CollectionItemTab.Rejected, 1))
        assertEquals("$root?status=approved", AO3CollectionItemsUrls.userPage("AO3_Reader", AO3CollectionItemTab.Approved, 1))
        assertEquals("$root/update_multiple", AO3CollectionItemsUrls.userUpdate("AO3_Reader"))
        assertEquals(AO3CollectionItemTab.Invited, AO3CollectionItemTab.defaultTab(null))
        assertEquals(AO3CollectionItemTab.Unreviewed, AO3CollectionItemTab.defaultTab("winter_exchange"))
        assertEquals("https://archiveofourown.org/collections/winter_exchange/items",
            AO3CollectionItemsUrls.page("winter_exchange", AO3CollectionItemTab.Unreviewed, 1))
        assertTrue(AO3CollectionItemsUrls.page("winter_exchange", AO3CollectionItemTab.Invited, 1).endsWith("status=unreviewed_by_user"))
        assertEquals("https://archiveofourown.org/users/name%20with%20space/collection_items",
            AO3CollectionItemsUrls.userPage(" name with space ", AO3CollectionItemTab.Invited, 1))
        assertNull(AO3CollectionItemsUrls.userPage(" ", AO3CollectionItemTab.Invited, 1))
        assertNull(AO3CollectionItemsUrls.userUpdate("another/account"))
        assertTrue(Routes.hasSubjectHeader(Routes.AO3UserCollectionItems))
        assertTrue(Routes.hidesTabBar(Routes.AO3UserCollectionItems))
    }

    @Test fun parserKeepsEachCollectionAndServedCreatorPermissionsAndFreshFormEvidence() {
        val page = page()
        assertEquals(7, page.items.size)
        assertEquals(setOf("Winter Exchange 2026", "Summer Prompt Meme"), page.items.map { it.collectionTitle }.toSet())
        assertEquals("demo-user-items-token", page.csrfToken)
        assertEquals("https://archiveofourown.org/users/AO3_Reader/collection_items/update_multiple", page.actionUrl)
        assertEquals("patch", page.methodOverride)
        val item = page.items.first()
        assertEquals(61, item.id)
        assertEquals("The Lantern Keeper", item.workTitle)
        assertEquals("AO3_Reader (Member)", item.creatorByline)
        assertEquals(AO3CollectionItemApproval.Unreviewed, item.creatorApproval)
        assertTrue(item.creatorEditable && item.removeEditable)
        assertFalse(item.moderatorEditable || item.unrevealedEditable || item.anonymousEditable)
        assertTrue(item.anonymous)
        val blankCollectionTitle = Jsoup.parse(userItemsFixture()).apply {
            selectFirst("span.collection a")!!.text("")
        }
        assertEquals("winter_exchange", page(blankCollectionTitle.outerHtml()).items.first().collectionTitle)
        val locked = page.items.last()
        assertFalse(locked.creatorEditable || locked.removeEditable)
        val withoutAction = parser.parseUser(userItemsFixture().replace("action=\"/users/AO3_Reader/collection_items/update_multiple\"", ""),
            "another_reader", AO3CollectionItemTab.Approved, 2)
        assertEquals("https://archiveofourown.org/users/another_reader/collection_items/update_multiple", withoutAction.actionUrl)
        assertThrows(IllegalArgumentException::class.java) {
            page(userItemsFixture().replace("/users/AO3_Reader/collection_items/update_multiple", "https://example.com/collection_items"))
        }
    }

    @Test fun creatorStagingExcludesDisabledFieldsAndRemovalReplacesApproval() {
        val item = page().items.first()
        val changed = AO3CollectionItemStaging().set(item) { it.copy(creatorApproval = AO3CollectionItemApproval.Approved,
            moderatorApproval = AO3CollectionItemApproval.Rejected, anonymous = false, unrevealed = true) }
        val draft = changed.pending(listOf(item)).single()
        assertEquals(AO3CollectionItemDraft(61, creatorApproval = AO3CollectionItemApproval.Approved), draft)
        assertEquals(listOf("authenticity_token" to "demo-user-items-token", "_method" to "patch",
            "collection_items[61][user_approval_status]" to "approved"), draft.parameters(page()))
        val removed = changed.remove(item, true).pending(listOf(item)).single()
        assertEquals(listOf("authenticity_token" to "demo-user-items-token", "_method" to "patch",
            "collection_items[61][remove]" to "1"), removed.parameters(page()))
        assertTrue(changed.pending(emptyList()).isEmpty())
        val locked = page().items.last()
        assertTrue(AO3CollectionItemStaging().set(locked) { it.copy(creatorApproval = AO3CollectionItemApproval.Approved) }
            .remove(locked, true).pending(listOf(locked)).isEmpty())
    }

    @Test fun reverseStagingSendsOrderedSinglePostsWithOneFreshReadAndStopsAtRefusal() = runTest {
        val (_, client, model) = setup()
        model.load()
        assertEquals(AO3CollectionItemTab.Invited, model.state.value.tab)
        assertEquals(listOf("https://archiveofourown.org/users/AO3_Reader/collection_items"), client.gets)
        model.state.value.page!!.items.take(3).reversed().forEach { item ->
            model.stage(item) { it.copy(creatorApproval = AO3CollectionItemApproval.Approved) }
        }
        client.refuse = 62
        client.holdPost = true
        val submit = async { model.confirmSubmit() }
        client.postEntered.await()
        model.confirmSubmit()
        assertEquals(1, client.posts.size)
        assertEquals(2, client.gets.size) // initial list + one fresh default form, never per item
        client.postRelease.complete(Unit); submit.await()
        assertEquals(listOf(61, 62), client.posts.map(::userItemId))
        assertEquals(1, client.maximumPosts)
        assertTrue(client.posts.all { fields -> fields.size == 3 && fields.last().first.endsWith("[user_approval_status]") })
        assertTrue(client.postUrls.all { it == "https://archiveofourown.org/users/AO3_Reader/collection_items/update_multiple" })
        assertTrue(client.postHeaders.all { it["Referer"] == "https://archiveofourown.org/users/AO3_Reader/collection_items" &&
            it["X-CSRF-Token"] == "demo-user-items-token" })
        assertEquals("AO3 couldn't update that collection item.", model.state.value.submitError)
        assertEquals(listOf(62, 63), model.state.value.pending.map { it.itemId })
        assertEquals(3, client.gets.size) // shared Android verification after partial failure, as 3as
    }

    @Test fun successfulCreatorApprovalAndRemovalClearOnlySentDraftsAndRereadCurrentPage() = runTest {
        val (_, client, model) = setup()
        model.load()
        val items = model.state.value.page!!.items
        model.stage(items[0]) { it.copy(creatorApproval = AO3CollectionItemApproval.Approved) }
        model.remove(items[2])
        model.load(AO3CollectionItemTab.Approved, 2) // fake keeps fixture rows, verifying off-page draft retention
        assertEquals(2, model.state.value.pending.size)
        model.confirmSubmit()
        assertEquals(listOf(61, 63), client.posts.map(::userItemId))
        assertEquals("https://archiveofourown.org/users/AO3_Reader/collection_items", client.gets[2])
        assertEquals("https://archiveofourown.org/users/AO3_Reader/collection_items?status=approved&page=2", client.gets.last())
        assertNull(model.state.value.submitError)
        assertTrue(model.state.value.pending.isEmpty())
        assertFalse(model.state.value.page!!.items.any { it.id == 63 })
        assertEquals(AO3CollectionItemApproval.Approved, model.state.value.page!!.items.first { it.id == 61 }.creatorApproval)
    }

    @Test fun freshServedTokenActionAndMethodWinOverTheDisplayedForm() = runTest {
        val (auth, client, model) = setup()
        model.load(); model.remove(model.state.value.page!!.items.first())
        client.html = userItemsFixture().replace("demo-user-items-token", "fresh-token")
            .replace("value=\"patch\"", "value=\"put\"")
            .replace("collection_items/update_multiple", "collection_items/update_multiple?fresh=1")
        model.confirmSubmit()
        assertEquals(1, client.posts.size)
        assertEquals("fresh-token", client.posts.single().toMap()["authenticity_token"])
        assertEquals("put", client.posts.single().toMap()["_method"])
        assertEquals("https://archiveofourown.org/users/AO3_Reader/collection_items/update_multiple?fresh=1", client.postUrls.single())
        assertEquals(setOf(auth.generation.value), client.generations)
    }

    @Test fun accountWriteUsesIosFallbackOnUnrecognizedPageButRequiresFreshMetaToken() = runTest {
        val (auth, client, _) = setup()
        val writes = AO3WriteRepository(client)
        val draft = listOf(AO3CollectionItemDraft(61, creatorApproval = AO3CollectionItemApproval.Approved))
        client.html = "<meta name='csrf-token' content='fallback-token'><p>Unrecognized list</p>"
        assertTrue(writes.updateUserCollectionItems("AO3_Reader", draft, auth.generation.value) is AO3Result.Success)
        assertEquals("https://archiveofourown.org/users/AO3_Reader/collection_items/update_multiple", client.postUrls.single())
        assertEquals(listOf("authenticity_token" to "fallback-token", "_method" to "patch",
            "collection_items[61][user_approval_status]" to "approved"), client.posts.single())
        client.html = "<input name='authenticity_token' value='input-only'>"
        assertTrue(writes.updateUserCollectionItems("AO3_Reader", draft, auth.generation.value) is AO3Result.Failure)
        assertEquals(1, client.posts.size)
    }

    @Test fun discardAndEmptySubmissionNeverReadOrPostAndTabsAreExplicit() = runTest {
        val (auth, client, model) = setup()
        val writes = AO3WriteRepository(client)
        writes.updateUserCollectionItems("AO3_Reader", emptyList(), auth.generation.value)
        assertTrue(client.gets.isEmpty())
        model.load(); model.remove(model.state.value.page!!.items.first())
        model.discard(); model.confirmSubmit()
        assertTrue(client.posts.isEmpty()); assertEquals(1, client.gets.size)
        model.load(AO3CollectionItemTab.Unreviewed, 1)
        assertTrue(client.gets.last().endsWith("?status=unreviewed_by_collection"))
        model.load(AO3CollectionItemTab.Invited, 1)
        assertEquals("https://archiveofourown.org/users/AO3_Reader/collection_items", client.gets.last())
    }

    @Test fun onlyVisibleDraftsSubmitAndOtherPagesDraftsSurviveUntilDiscard() = runTest {
        val (_, client, model) = setup()
        model.load(); model.remove(model.state.value.page!!.items.first()) // 61 on page one
        val document = Jsoup.parse(client.html)
        document.selectFirst("h4#collection_item_61")!!.closest("li.collection.item")!!.remove()
        client.html = document.outerHtml()
        model.load(AO3CollectionItemTab.Approved, 2)
        assertTrue(model.state.value.pending.isEmpty())
        model.remove(model.state.value.page!!.items.first { it.id == 64 })
        model.confirmSubmit()
        assertEquals(listOf(64), client.posts.map(::userItemId))
        assertEquals(setOf(61), model.state.value.staging.drafts.keys)
        model.discard()
        assertTrue(model.state.value.staging.drafts.isEmpty())
    }

    @Test fun signedOutAccountScopeNeverReadsAndAStaleInitialReadDoesNotInstallRows() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(null), MemoryCookieStore())
        auth.restoreSession()
        val client = UserItemsClient(auth)
        val out = AO3CollectionItemsState(null, AO3CollectionDetailRepository(client, auth), AO3WriteRepository(client))
        out.load()
        assertEquals(AO3CollectionItemsUiState.Phase.SignedOut, out.state.value.phase)
        assertTrue(client.gets.isEmpty())
        val (signedIn, heldClient, model) = setup()
        heldClient.holdGet = true
        val read = async { model.load() }
        heldClient.getEntered.await()
        signedIn.logout(); heldClient.getRelease.complete(Unit); read.join()
        assertNull(model.state.value.page)
        assertTrue(heldClient.posts.isEmpty())
    }

    @Test fun refusedUnconfirmedAndTransportWritesAreSingleShotAndKeepDrafts() = runTest {
        for (reply in listOf(userItemsResponse("<p>No confirmation</p>"),
            userItemsResponse("<div class='flash error'>Refused</div><div class='flash notice'>Saved</div>", 422),
            AO3Result.Failure(AO3Error.Network("Lost reply")))) {
            val (_, client, model) = setup()
            model.load(); model.state.value.page!!.items.take(3).forEach { model.remove(it) }
            client.postReply = reply; model.confirmSubmit()
            assertEquals(1, client.posts.size)
            assertEquals(3, model.state.value.pending.size)
            assertNotNull(model.state.value.submitError)
        }
    }

    @Test fun staleGenerationOnEntryOrFreshReadPreventsDispatchAndStalePostStopsRemainingItems() = runTest {
        val (signedOut, unused, _) = setup()
        val oldGeneration = signedOut.generation.value
        signedOut.logout()
        assertTrue(runCatching { AO3WriteRepository(unused).updateUserCollectionItems("AO3_Reader",
            listOf(AO3CollectionItemDraft(61, remove = true)), oldGeneration) }.exceptionOrNull() is CancellationException)
        assertTrue(unused.gets.isEmpty() && unused.posts.isEmpty())
        for (duringPost in listOf(false, true)) {
            val (auth, client, model) = setup()
            model.load(); model.state.value.page!!.items.take(3).forEach { model.remove(it) }
            client.holdGet = !duringPost; client.holdPost = duringPost
            val submit = async { model.confirmSubmit() }
            if (duringPost) client.postEntered.await() else client.getEntered.await()
            val before = model.state.value
            auth.logout()
            if (duringPost) client.postRelease.complete(Unit) else client.getRelease.complete(Unit)
            submit.await()
            assertEquals(before, model.state.value)
            assertEquals(if (duringPost) 1 else 0, client.posts.size)
            assertEquals(2, client.gets.size) // No new account's verification read or second POST.
        }
    }

    @Test fun everyCollectionRowOffersEditAndManageRegardlessOfRoleFlagsOrChallenge() {
        for (owner in listOf(false, true)) for (member in listOf(false, true)) {
            for (kind in listOf(null, AO3ChallengeKind.GiftExchange, AO3ChallengeKind.PromptMeme)) {
                val collection = AO3Collection(name = "winter_exchange", title = "Winter & Letters", viewerIsOwner = owner,
                    viewerIsMember = member, challengeKind = kind, isClosed = true, isAnonymous = true, isUnrevealed = true)
                assertEquals(listOf(
                    AO3CollectionRowAction("Edit Collection", "ao3-collection-form?slug=winter_exchange"),
                    AO3CollectionRowAction("Manage Items", "ao3-collection-items/winter_exchange?title=Winter%20%26%20Letters")
                ), ao3CollectionRowActions(collection))
            }
        }
    }

    private suspend fun setup(): Triple<AO3AuthRepository, UserItemsClient, AO3CollectionItemsState> {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val client = UserItemsClient(auth)
        return Triple(auth, client, AO3CollectionItemsState(null, AO3CollectionDetailRepository(client, auth), AO3WriteRepository(client)))
    }
}

private fun userItemsFixture(): String = listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures", "android/app/src/debug/assets/fixtures")
    .map { File(it, "ao3_demo_user_collection_items.html") }.first { it.isFile }.readText()

private fun userItemsResponse(html: String, status: Int = 200) = AO3Result.Success(AO3HttpResponse(
    "https://archiveofourown.org/users/AO3_Reader/collection_items", status, emptyMap(), html))

private fun userItemId(fields: List<Pair<String, String>>) = fields.first { it.first.startsWith("collection_items[") }
    .first.substringAfter('[').substringBefore(']').toInt()

/** No HTTP client or validator: every request is an in-memory response. */
private class UserItemsClient(private val auth: AO3AuthRepository) : AO3Client, AO3AuthenticatedClient {
    var html = userItemsFixture()
    val gets = mutableListOf<String>()
    val posts = mutableListOf<List<Pair<String, String>>>()
    val postUrls = mutableListOf<String>()
    val postHeaders = mutableListOf<Map<String, String>>()
    val generations = mutableSetOf<Int>()
    var maximumPosts = 0
    var activePosts = 0
    var refuse: Int? = null
    var postReply: AO3Result<AO3HttpResponse>? = null
    var holdGet = false; var holdPost = false
    val getEntered = CompletableDeferred<Unit>(); val getRelease = CompletableDeferred<Unit>()
    val postEntered = CompletableDeferred<Unit>(); val postRelease = CompletableDeferred<Unit>()
    override fun username() = auth.username()
    override fun sessionGeneration() = auth.generation.value
    override suspend fun getAuthenticated(url: String) = get(url, emptyMap())
    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        gets += url
        if (holdGet) { getEntered.complete(Unit); getRelease.await() }
        return userItemsResponse(html)
    }
    override suspend fun postAuthenticatedInSession(url: String, formFields: List<Pair<String, String>>,
        headers: Map<String, String>, generation: Int?): AO3Result<AO3HttpResponse> {
        if (generation != sessionGeneration()) throw CancellationException()
        generations.add(generation!!)
        return postAuthenticated(url, formFields, headers)
    }
    override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>,
        headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        posts += formFields; postUrls += url; postHeaders += headers
        ++activePosts; maximumPosts = maxOf(maximumPosts, activePosts)
        if (holdPost) { postEntered.complete(Unit); postRelease.await() }
        val reply = postReply ?: if (userItemId(formFields) == refuse) {
            userItemsResponse("<div class='flash error'>AO3 couldn't update that collection item.</div>", 422)
        } else {
            val document = Jsoup.parse(html)
            formFields.filter { it.first.startsWith("collection_items[") }.forEach { (name, value) ->
                val control = document.select("select, input[type=checkbox]").firstOrNull { it.attr("name") == name }
                if (name.endsWith("[remove]")) control?.closest("li.collection.item")?.remove()
                else if (control?.tagName() == "select") control.select("option").forEach { option ->
                    option.removeAttr("selected"); if (option.attr("value") == value) option.attr("selected", "selected")
                }
            }
            html = document.outerHtml()
            userItemsResponse("<div class='flash notice'>Collection item updated.</div>")
        }
        --activePosts
        return reply
    }
}
