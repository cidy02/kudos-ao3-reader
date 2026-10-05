package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.network.ao3.*
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

class AO3CollectionModerationTest {
    @Test fun failureCopyMatchesIosAndValidationKeepsAo3sWords() {
        assertEquals("AO3 refused the request (HTTP 403). Wait a while before trying again.", AO3Error.Forbidden.moderationMessage())
        assertEquals("That work or page couldn't be found (it may be restricted).", AO3Error.NotFound.moderationMessage())
        assertEquals("AO3 is rate-limiting requests. Wait a moment and try again.", AO3Error.RateLimited(null).moderationMessage())
        assertEquals("AO3's page format wasn't what the app expected.", AO3Error.Parse("drift").moderationMessage())
        assertEquals("You're offline. Connect to the internet and try again.", AO3Error.Network("detail", offline = true).moderationMessage())
        assertEquals("Couldn't reach AO3. Check your connection and try again.", AO3Error.Network("detail").moderationMessage())
        assertEquals("AO3 took too long to answer. Try again.", AO3Error.Network("detail", java.net.SocketTimeoutException()).moderationMessage())
        assertEquals("Couldn't make a secure connection to AO3.", AO3Error.Network("detail", javax.net.ssl.SSLException("detail")).moderationMessage())
        assertEquals("AO3's own refusal.", AO3Error.Validation("AO3's own refusal.").moderationMessage())
    }

    @Test fun parsesOriginalParticipantsRolesItemsAndShowFlags() {
        val participants = AO3CollectionParticipantsParser().parse(moderationFixture("ao3_demo_moderation_participants"))
        assertEquals(listOf("mapfold", "ashletter"), participants.filter { it.isMembershipRequest }.map { it.pseud })
        assertEquals(4, participants.count { it.isMaintainer })
        assertEquals(listOf("AO3_Reader", "frostledger"), participants.filter { it.role == "Owner" }.map { it.pseud })
        assertEquals(listOf("emberpost", "duskatlas"), participants.filter { it.role == "Moderator" }.map { it.pseud })
        assertEquals(participants.size, participants.map { it.pseud }.distinct().size)
        assertEquals("Invited", participants.last().role)
        val formId = AO3CollectionParticipantsParser().parse("<ul class='participant index'><li><span class='byline'><a href='/users/test'>test</a></span>" +
            "<form action='/collections/winter_exchange/participants/222'><select name='collection_participant[participant_role]'>" +
            "<option value='None' selected>None</option></select></form></li></ul>")
        assertEquals(222, formId.single().id)
        assertTrue(AO3CollectionParticipantsParser().parse("<ul class='participant index'></ul>").isEmpty())
        assertThrows(IllegalArgumentException::class.java) { AO3CollectionParticipantsParser().parse("<form id='new_user'></form>") }
        val show = AO3CollectionParser().parseCollectionShow(moderationFixture("ao3_demo_moderation_show"), "winter_exchange")
        assertTrue(show.collection.isUnrevealed && show.collection.isAnonymous)
        val items = AO3CollectionItemsParser().parse(moderationFixture("ao3_demo_collection_items"), "winter_exchange", AO3CollectionItemTab.Unreviewed, 1)
        assertEquals("Work", items.items.first().itemType)
        assertNotNull(items.items.first().workId)
        val bookmark = AO3CollectionItemsParser().parse(moderationFixture("ao3_demo_collection_items").replace("</h4>", "</h4><blockquote class='bookmark'></blockquote>"),
            "winter_exchange", AO3CollectionItemTab.Unreviewed, 1)
        assertEquals("Bookmark", bookmark.items.first().itemType)
    }

    @Test fun openingAndRefreshReadExactlyThreePagesInIosOrderPagingReadsOnlyQueue() = runTest {
        val (_, client, model) = moderationSetup()
        model.load()
        val root = AO3CollectionFormUrls.show("winter_exchange")
        assertEquals(listOf("$root/items", "$root/participants", root), client.gets)
        assertEquals(2, model.state.value.data!!.requests.size)
        assertEquals(4, model.state.value.data!!.maintainerCount)
        model.loadPage(2)
        assertEquals("$root/items?page=2", client.gets.last())
        assertEquals(4, client.gets.size)
        assertEquals(2, model.state.value.data!!.queue.currentPage)
        model.load()
        assertEquals(listOf("$root/items", "$root/participants", root), client.gets.takeLast(3))
        assertEquals(1, model.state.value.data!!.queue.currentPage)
    }

    @Test fun approveIsImmediateRejectConfirmsCancelSendsNothingAndFieldsAreExact() = runTest {
        val (auth, client, model) = moderationSetup()
        model.load()
        model.choose(ModerationDecision(ModerationAction.Reject, 42, "The Snowbound Post Office"))
        assertEquals("Reject this work?", model.state.value.pending!!.title)
        assertEquals("This rejects “The Snowbound Post Office” from the collection. The work stays on AO3, and its creator receives no reason or email.",
            model.state.value.pending!!.message)
        model.cancel(); model.confirm()
        assertTrue(client.posts.isEmpty()); assertEquals(3, client.gets.size)
        model.choose(ModerationDecision(ModerationAction.Approve, 41))
        assertEquals(1, client.posts.size)
        assertEquals(listOf("authenticity_token" to "demo-items-token", "_method" to "patch",
            "collection_items[41][collection_approval_status]" to "approved"), client.posts.single().fields)
        assertEquals("${AO3CollectionFormUrls.show("winter_exchange")}/items/update_multiple", client.posts.single().url)
        assertEquals("demo-items-token", client.posts.single().headers["X-CSRF-Token"])
        assertEquals(auth.generation.value, client.posts.single().generation)
        assertFalse(model.state.value.data!!.queue.items.any { it.id == 41 })
        model.choose(ModerationDecision(ModerationAction.Reject, 43, "A Map of Warm Windows"))
        assertEquals(1, client.posts.size)
        model.confirm(); model.confirm()
        assertEquals(2, client.posts.size)
        assertEquals("rejected", client.posts.last().fields.toMap()["collection_items[43][collection_approval_status]"])
        assertEquals(5, client.gets.size) // Only one fresh form read per decision; no success refresh.
    }

    @Test fun acceptAndConfirmedDeclineUseParticipantAddressMetaTokenAndExactOverride() = runTest {
        val (_, client, model) = moderationSetup()
        model.load()
        model.choose(ModerationDecision(ModerationAction.Accept, 105, "mapfold"))
        assertEquals(listOf("_method" to "patch", "authenticity_token" to "demo-participants-token",
            "collection_participant[participant_role]" to "Member"), client.posts.single().fields)
        assertEquals("${AO3CollectionModerationUrls.participants("winter_exchange")}/105", client.posts.single().url)
        assertEquals(AO3CollectionModerationUrls.participants("winter_exchange"), client.posts.single().headers["Referer"])
        model.choose(ModerationDecision(ModerationAction.Decline, 106, "ashletter"))
        assertEquals("Decline ashletter?", model.state.value.pending!!.title)
        assertEquals("This removes ashletter's membership request. They will need to apply again.", model.state.value.pending!!.message)
        model.cancel(); assertEquals(1, client.posts.size)
        model.choose(ModerationDecision(ModerationAction.Decline, 106, "ashletter")); model.confirm()
        assertEquals(listOf("_method" to "delete", "authenticity_token" to "demo-participants-token"), client.posts.last().fields)
        assertTrue(model.state.value.data!!.requests.isEmpty())
        assertEquals(5, client.gets.size)
    }

    @Test fun revealAndUnanonPreserveWholeFormUseTwoReadsFreshMetaAndOnePostThenReload() = runTest {
        for (action in listOf(ModerationAction.Reveal, ModerationAction.Unanon)) {
            val (_, client, model) = moderationSetup()
            model.load()
            model.choose(ModerationDecision(action)); model.cancel()
            assertTrue(client.posts.isEmpty()); assertEquals(3, client.gets.size)
            model.choose(ModerationDecision(action))
            assertEquals(if (action == ModerationAction.Reveal) "Reveal this collection?" else "Remove anonymity?", model.state.value.pending!!.title)
            model.confirm()
            assertEquals(1, client.posts.size)
            val formReads = client.gets.drop(3).take(2)
            assertEquals(listOf(AO3CollectionFormUrls.form("winter_exchange"), AO3CollectionFormUrls.form("winter_exchange")), formReads)
            val original = AO3CollectionFormParser().parse(client.editHtml, "winter_exchange")
            val changed = original.changed(AO3CollectionFields.preference(if (action == ModerationAction.Reveal) "unrevealed" else "anonymous"), "0")
            assertEquals(changed.copy(csrfToken = "fresh-edit-token").parameters(), client.posts.single().fields)
            assertEquals(original.actionUrl, client.posts.single().url)
            assertEquals("fresh-edit-token", client.posts.single().headers["X-CSRF-Token"])
            assertEquals(8, client.gets.size)
            assertFalse(if (action == ModerationAction.Reveal) model.state.value.data!!.unrevealed else model.state.value.data!!.anonymous)
        }
    }

    @Test fun everyActionRejectsDuplicateTapWhilePostIsOut() = runTest {
        for (action in ModerationAction.entries) {
            val (_, client, model) = moderationSetup()
            model.load()
            client.holdPost = true
            val decision = ModerationDecision(action, if (action in listOf(ModerationAction.Accept, ModerationAction.Decline)) 105 else 41, "test")
            val first = async { model.choose(decision); if (action.confirms) model.confirm() }
            client.postEntered.await()
            model.choose(decision); model.confirm()
            assertEquals(1, client.posts.size)
            client.postRelease.complete(Unit); first.await()
            assertEquals(1, client.posts.size)
        }
    }

    @Test fun refusalShowsAo3WordsKeepsQueueRequestsAndFlagsAndDoesNotRefresh() = runTest {
        for (action in ModerationAction.entries) {
            val (_, client, model) = moderationSetup()
            model.load()
            val before = model.state.value.data
            client.postHtml = "<div class='flash error'>The lantern keeper refused this change.</div><div class='flash notice'>Ignore me.</div>"
            client.postStatus = 422
            val decision = ModerationDecision(action, if (action in listOf(ModerationAction.Accept, ModerationAction.Decline)) 105 else 41, "test")
            model.choose(decision); if (action.confirms) model.confirm()
            assertEquals(before, model.state.value.data)
            assertEquals(if (decision.isReveal) "The lantern keeper refused this change." else
                "Failed to ${action.verb}: The lantern keeper refused this change.",
                if (decision.isReveal) model.state.value.revealError else model.state.value.actionError)
            assertEquals(if (decision.isReveal) 5 else 4, client.gets.size)
            assertEquals(1, client.posts.size)
        }
    }

    @Test fun unconfirmedAndTransportResponsesNeverMutateOrRetryRedirectIsRecognized() = runTest {
        for (action in ModerationAction.entries) {
            val (_, client, model) = moderationSetup()
            model.load(); val before = model.state.value.data
            client.postHtml = "<p>No confirmation</p>"
            val decision = ModerationDecision(action, if (action in listOf(ModerationAction.Accept, ModerationAction.Decline)) 105 else 41)
            model.choose(decision); if (action.confirms) model.confirm()
            assertEquals(before, model.state.value.data)
            assertTrue((model.state.value.actionError ?: model.state.value.revealError).orEmpty().contains(AO3CollectionFields.UNCONFIRMED))
            assertEquals(1, client.posts.size)
        }
        val (_, client, model) = moderationSetup()
        model.load(); client.postError = AO3Error.Network("offline")
        model.choose(ModerationDecision(ModerationAction.Accept, 105))
        assertEquals(1, client.posts.size); assertEquals(2, model.state.value.data!!.requests.size)
        client.postError = null; client.postStatus = 302; client.postHtml = ""
        model.choose(ModerationDecision(ModerationAction.Accept, 105))
        assertEquals(1, model.state.value.data!!.requests.size)
    }

    @Test fun sessionChangesDuringEveryWriteResponseNeverTouchTheOldScreen() = runTest {
        for (action in ModerationAction.entries) {
            val (auth, client, model) = moderationSetup()
            model.load(); client.holdPost = true
            val operation = async {
                model.choose(ModerationDecision(action, if (action in listOf(ModerationAction.Accept, ModerationAction.Decline)) 105 else 41))
                if (action.confirms) model.confirm()
            }
            client.postEntered.await()
            val out = model.state.value
            auth.logout(); client.postRelease.complete(Unit); operation.await()
            assertEquals(out, model.state.value)
            assertEquals(1, client.posts.size)
            assertEquals(if (action in listOf(ModerationAction.Reveal, ModerationAction.Unanon)) 5 else 4, client.gets.size)
        }
    }

    @Test fun sessionChangesDuringFormReadsNeverSendIncludingSecondRevealRead() = runTest {
        for (action in ModerationAction.entries) {
            for (read in 4..(if (action in listOf(ModerationAction.Reveal, ModerationAction.Unanon)) 5 else 4)) {
                val (auth, client, model) = moderationSetup()
                model.load(); client.holdGetNumber = read
                val operation = async {
                    model.choose(ModerationDecision(action, if (action in listOf(ModerationAction.Accept, ModerationAction.Decline)) 105 else 41))
                    if (action.confirms) model.confirm()
                }
                client.getEntered.await(); val before = model.state.value
                auth.logout(); client.getRelease.complete(Unit); operation.await()
                assertTrue(client.posts.isEmpty()); assertEquals(before, model.state.value)
            }
        }
    }

    @Test fun staleOpeningDoesNotInstallDataOrReadTheNextPageAndNewSessionStartsEmpty() = runTest {
        for (read in 1..3) {
            val (auth, client, model) = moderationSetup()
            client.holdGetNumber = read
            val opening = async { model.load() }
            client.getEntered.await(); auth.logout(); client.getRelease.complete(Unit); opening.join()
            assertNull(model.state.value.data); assertEquals(read, client.gets.size)
            val replacement = AO3CollectionModerationState("winter_exchange", true, AO3CollectionDetailRepository(client, auth), AO3WriteRepository(client))
            replacement.load(); assertNull(replacement.state.value.data)
            assertEquals("Log in to AO3 before using this feature.", replacement.state.value.failure)
            assertEquals(read, client.gets.size)
        }
    }

    @Test fun nonOwnerHasNoRevealControlsAndCannotPrepareEitherWrite() = runTest {
        val (_, client, model) = moderationSetup(owner = false)
        model.load()
        assertTrue(model.state.value.data!!.anonymous && model.state.value.data!!.unrevealed)
        assertFalse(model.showsReveal || model.showsUnanon)
        model.choose(ModerationDecision(ModerationAction.Reveal)); model.confirm()
        model.choose(ModerationDecision(ModerationAction.Unanon)); model.confirm()
        assertTrue(client.posts.isEmpty()); assertEquals(3, client.gets.size)
    }

    @Test fun missingMetaNeverSendsAnyActionEvenWhenAnInputTokenExists() = runTest {
        for (action in ModerationAction.entries) {
            val (_, client, model) = moderationSetup()
            model.load(); val before = model.state.value.data
            client.omitMeta = true
            model.choose(ModerationDecision(action, if (action in listOf(ModerationAction.Accept, ModerationAction.Decline)) 105 else 41))
            if (action.confirms) model.confirm()
            assertTrue(client.posts.isEmpty()); assertEquals(before, model.state.value.data)
        }
    }

    @Test fun pageFailureKeepsOldPageAndDecidingLastItemFetchesNearestPageOnly() = runTest {
        val (_, client, model) = moderationSetup()
        model.load()
        val queue = model.state.value.data!!.queue
        client.getError = AO3Error.Network("offline")
        model.loadPage(2)
        assertEquals(queue, model.state.value.data!!.queue)
        assertTrue(model.state.value.actionError!!.startsWith("Couldn't load that page: "))
        client.getError = null; model.loadPage(2)
        assertEquals(listOf(44), model.state.value.data!!.queue.items.map { it.id })
        val reads = client.gets.size
        model.choose(ModerationDecision(ModerationAction.Approve, 44))
        assertEquals(reads + 2, client.gets.size) // Form read then nearest queue page, no participants/show.
        assertTrue(client.gets.last().endsWith("/items"))
        assertEquals(1, model.state.value.data!!.queue.currentPage)
    }

    @Test fun sessionChangeDuringPageReadCannotReplaceQueueOrShowAnError() = runTest {
        val (auth, client, model) = moderationSetup()
        model.load(); client.holdGetNumber = 4
        val page = async { model.loadPage(2) }
        client.getEntered.await(); val before = model.state.value
        auth.logout(); client.getRelease.complete(Unit); page.join()
        assertEquals(before, model.state.value)
        assertEquals(4, client.gets.size)
    }

    @Test fun initialFailureEmptyLoadingAndSignedOutStatesMakeNoExtraReads() = runTest {
        val (_, client, model) = moderationSetup()
        client.holdGetNumber = 1
        val opening = async { model.load() }
        client.getEntered.await()
        assertTrue(model.state.value.loading); assertNull(model.state.value.data)
        client.getError = AO3Error.Forbidden
        client.getRelease.complete(Unit); opening.await()
        assertNotNull(model.state.value.failure); assertNull(model.state.value.data)
        assertEquals(1, client.gets.size)
        client.getError = null; client.empty = true
        model.load()
        assertTrue(model.state.value.data!!.queue.items.isEmpty() && model.state.value.data!!.requests.isEmpty())
        assertEquals(4, client.gets.size)
    }
}

internal fun moderationFixture(name: String): String = listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures", "android/app/src/debug/assets/fixtures")
    .map { File(it, "$name.html") }.first { it.isFile }.readText()

internal suspend fun moderationSetup(owner: Boolean = true): Triple<AO3AuthRepository, ModerationClient, AO3CollectionModerationState> {
    val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
    auth.restoreSession()
    val client = ModerationClient(auth)
    return Triple(auth, client, AO3CollectionModerationState("winter_exchange", owner, AO3CollectionDetailRepository(client, auth), AO3WriteRepository(client)))
}

internal class ModerationClient(private val auth: AO3AuthRepository) : AO3Client, AO3AuthenticatedClient {
    data class Post(val url: String, val fields: List<Pair<String, String>>, val headers: Map<String, String>, val generation: Int?)
    val gets = mutableListOf<String>()
    val posts = mutableListOf<Post>()
    val editHtml = Jsoup.parse(moderationFixture("ao3_demo_collection_edit")).apply {
        select("input[type=checkbox]").first { it.attr("name") == AO3CollectionFields.preference("unrevealed") }.attr("checked", "checked")
    }.outerHtml()
    var holdPost = false
    var holdGetNumber = 0
    var postHtml = "<div class='flash notice'>Collection was successfully updated.</div>"
    var postStatus = 200
    var postError: AO3Error? = null
    var getError: AO3Error? = null
    var empty = false
    var omitMeta = false
    private var editReads = 0
    private var revealed = false
    private var unanon = false
    val postEntered = CompletableDeferred<Unit>()
    val postRelease = CompletableDeferred<Unit>()
    val getEntered = CompletableDeferred<Unit>()
    val getRelease = CompletableDeferred<Unit>()
    override fun username() = auth.username()
    override fun sessionGeneration() = auth.generation.value
    override suspend fun getAuthenticated(url: String) = get(url, emptyMap())
    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        gets += url
        if (gets.size == holdGetNumber) { getEntered.complete(Unit); getRelease.await() }
        getError?.let { return AO3Result.Failure(it) }
        val body = when {
            url.contains("/edit") -> {
                editReads++
                if (editReads % 2 == 0) editHtml.replace("demo-collection-edit-token", "fresh-edit-token") else editHtml
            }
            url.contains("/participants") -> if (empty) "<ul class='participant index'></ul>" else moderationFixture("ao3_demo_moderation_participants")
            url.contains("/items") -> Jsoup.parse(moderationFixture("ao3_demo_collection_items")).apply {
                val ids = if (empty) emptySet() else if (url.contains("page=2")) setOf(44) else setOf(41, 42, 43)
                select("li.collection.item").filterNot { it.selectFirst("h4.heading")!!.id().removePrefix("collection_item_").toInt() in ids }.forEach { it.remove() }
                selectFirst("#main")!!.append("<ol class='pagination'><li>1</li><li>2</li></ol>")
            }.outerHtml()
            else -> moderationFixture("ao3_demo_moderation_show").let {
                (if (revealed) it.replace("Unrevealed, ", "") else it).let { body -> if (unanon) body.replace("Anonymous, ", "") else body }
            }
        }
        return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(),
            if (omitMeta) body.replace(Regex("<meta[^>]*name=\"csrf-token\"[^>]*>"), "") else body))
    }
    override suspend fun postAuthenticatedInSession(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>, generation: Int?): AO3Result<AO3HttpResponse> {
        if (generation != sessionGeneration()) throw kotlinx.coroutines.CancellationException()
        return postAuthenticated(url, formFields, headers)
    }
    override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        posts += Post(url, formFields, headers, sessionGeneration())
        if (holdPost) { postEntered.complete(Unit); postRelease.await() }
        postError?.let { return AO3Result.Failure(it) }
        if (postStatus == 200 && postHtml.contains("notice")) {
            val fields = formFields.toMap()
            if (fields[AO3CollectionFields.preference("unrevealed")] == "0") revealed = true
            if (fields[AO3CollectionFields.preference("anonymous")] == "0") unanon = true
        }
        return AO3Result.Success(AO3HttpResponse(url, postStatus, emptyMap(), postHtml))
    }
}
