package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.account.*
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.network.ao3.writes.DefaultAO3AuthenticatedClient
import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class AO3TagSetTest {
    private val parser = AO3TagSetParser()

    @Test fun openFixtureAndEditHaveEveryTagKindAndOnlyEditSuppliesOpenNominationControlsAndFieldValues() {
        val base = parser.parse(tagSetFixture("ao3_demo_tag_set_42"), 42)
        val edit = parser.parse(tagSetFixture("ao3_demo_tag_set_42_edit"), 42)
        assertEquals("Winter Exchange Tags", base.title)
        assertEquals(listOf(2, 2, 1, 2), AO3TagSetField.entries.map { base.counts[it] })
        assertEquals(7, base.totalTagCount)
        assertTrue(base.isVisible)
        assertFalse(base.isNominated) // Public page has no form; do not invent private flags.
        assertTrue(base.tagnames.values.all(String::isEmpty))
        assertTrue(edit.isVisible)
        assertTrue(edit.isNominated)
        assertEquals(listOf(2, 3, 2, 4), AO3TagSetField.entries.map { edit.nominationLimits[it] })
        assertTrue(edit.tagnames.values.all(String::isEmpty))
        assertEquals(AO3TagSetUrls.page(42), edit.actionUrl)
        assertEquals("put", edit.httpMethodOverride)
        assertNull(base.actionUrl)
        // A signed-in POST never follows a form address that is not AO3's own.
        assertNull(AO3TagSetParser().parse(tagSetFixture("ao3_demo_tag_set_42_edit")
            .replace("action=\"/tag_sets/42\"", "action=\"https://example.com/tag_sets/42\""), 42).actionUrl)
        assertEquals(base.counts, edit.counts)
        assertEquals("Paper Harbor", base.reviewQueue.single().tagName)
        val queue = parser.parseNominations(tagSetFixture("ao3_demo_tag_set_42_nominations"))
        assertEquals(5, queue.size)
        assertEquals(listOf(AO3TagSetField.Fandom, AO3TagSetField.Character, AO3TagSetField.Relationship,
            AO3TagSetField.Freeform, AO3TagSetField.Freeform), queue.map { it.field })
        assertEquals(listOf(AO3TagNominationState.Unreviewed, AO3TagNominationState.Approved,
            AO3TagNominationState.Unreviewed, AO3TagNominationState.Rejected, AO3TagNominationState.Unreviewed), queue.map { it.state })
        assertEquals("Letters [Winter]", queue.last().tagName)
        assertTrue(queue.all { it.parentTagName.isEmpty() }) // iOS does not read the parent spans.
    }

    @Test fun closedAndRefusedViewerFixturesKeepTheRealDefaultsAndEmptyQueue() {
        val closed = parser.parse(tagSetFixture("ao3_demo_tag_set_43"), 43)
        assertFalse(closed.isVisible)
        assertFalse(closed.isNominated)
        assertEquals(listOf(1, 1, 0, 0), AO3TagSetField.entries.map { closed.counts[it] })
        assertEquals(listOf(1, 2, 0, 0), AO3TagSetField.entries.map { closed.nominationLimits[it] })
        assertEquals("Oren Reed", closed.tagnames[AO3TagSetField.Character])
        assertTrue(parser.parseNominations(tagSetFixture("ao3_demo_tag_set_43_nominations")).isEmpty())
        val viewer = parser.parse(tagSetFixture("ao3_demo_tag_set_44"), 44)
        assertEquals("Summer Prompt Tags", viewer.title)
        assertEquals(3, viewer.totalTagCount)
        assertTrue(viewer.isVisible)
        assertFalse(viewer.isNominated)
        assertTrue(viewer.nominationLimits.values.all { it == 0 })
        assertTrue(viewer.tagnames.values.all(String::isEmpty))
        assertEquals(1, viewer.reviewQueue.size)
        assertEquals(2, parser.parseNominations(tagSetFixture("ao3_demo_tag_set_44_nominations")).size)
        assertThrows(IllegalArgumentException::class.java) { parser.parse(tagSetFixture("ao3_demo_tag_set_44_edit_refused"), 44) }
    }

    @Test fun parserMirrorsCountFallbacksTitleDefaultsFieldTrimmingAndParamDeduplication() {
        val page = parser.parse("""
            <form action='/tag_sets/8'><input type='hidden' checked name='owned_tag_set[visible]'>
            <textarea name='owned_tag_set[tag_set_attributes][fandom_tagnames_to_add]'>   </textarea>
            <input name='owned_tag_set[tag_set_attributes][fandom_tagnames_to_add]' value=' Harbor '>
            <input name='owned_tag_set[fandom_nomination_limit]' value='up to 12'></form>
            <ul class='fandom'><li>a</li><li>b</li></ul><div class='character'><ul><li>c</li></ul></div>
            <ul class='freeform'><li>x</li></ul><ul class='additional'><li>y</li><li>z</li></ul>
            <input type='checkbox' name='fandom_approve_Harbor'><input type='radio' name='fandom_reject_Harbor'>
            <input type='checkbox' name='character_synonym_A_B'><input type='checkbox' name='bad_reject_No'>
        """, 8)
        assertEquals("Tag Set 8", page.title)
        assertFalse(page.isVisible)
        assertEquals(listOf(2, 1, 0, 3), AO3TagSetField.entries.map { page.counts[it] })
        assertEquals(12, page.nominationLimits[AO3TagSetField.Fandom])
        assertEquals("Harbor", page.tagnames[AO3TagSetField.Fandom])
        assertEquals(listOf("Harbor", "A_B"), page.reviewQueue.map { it.tagName })
        assertEquals(AO3TagNominationState.Approved, page.reviewQueue.first().state)
        assertThrows(IllegalArgumentException::class.java) { parser.parse("<html>unexpected</html>", 8) }
        assertThrows(IllegalArgumentException::class.java) { parser.parse("<h2>Log in</h2><form action='/users/login'></form>", 8) }
        assertThrows(IllegalArgumentException::class.java) { parser.parseNominations("<form id='new_user'></form>") }
        assertTrue(parser.parseNominations("<html>no nominations markup</html>").isEmpty()) // iOS best effort.
    }

    @Test fun ownerAndOtherViewerEachMakeExactlyThreeSequentialAuthenticatedReadsAndRefreshRepeatsOnlyThose() = runTest {
        for ((id, username) in listOf(42 to "AO3_Reader", 44 to "Other_Viewer")) {
            val (auth, client, repository) = tagSetSetup(id, username)
            val model = AO3TagSetState(id, repository, tagSetWrites(client, auth))
            model.load()
            assertEquals(tagSetReadUrls(id), client.gets)
            assertEquals(3, client.authenticatedReads.size)
            assertTrue(client.publicReads.isEmpty())
            assertNotNull(model.state.value.data)
            assertNull(model.state.value.failure)
            model.load()
            assertEquals(tagSetReadUrls(id) + tagSetReadUrls(id), client.gets)
            assertTrue(client.gets.none { "page=" in it || "collections/" in it })
            assertEquals(0, client.posts)
        }
    }

    @Test fun signedOutMakesExactlyOnePublicClientGetAndNoAuthenticatedReadIncludingOnRetry() = runTest {
        val (auth, client, repository) = tagSetSetup(42, username = null)
        val model = AO3TagSetState(42, repository, tagSetWrites(client, auth))
        model.load()
        assertEquals(listOf(AO3TagSetUrls.page(42)), client.publicReads)
        assertTrue(client.authenticatedReads.isEmpty())
        assertEquals(1, model.state.value.data!!.reviewQueue.size)
        assertFalse(model.state.value.data!!.isNominated)
        model.load()
        assertEquals(List(2) { AO3TagSetUrls.page(42) }, client.publicReads)
        assertTrue(client.authenticatedReads.isEmpty())
        assertEquals(0, client.posts)
    }

    @Test fun optionalReadFailuresKeepEarlierValuesAndNeverHideTheScreenOrSkipTheNextRead() = runTest {
        for (failed in listOf("edit", "nominations", "both")) {
            val (auth, client, repository) = tagSetSetup()
            if (failed != "nominations") client.replies[AO3TagSetUrls.edit(42)] = AO3Result.Failure(AO3Error.Forbidden)
            if (failed != "edit") client.replies[AO3TagSetUrls.nominations(42)] = AO3Result.Failure(AO3Error.Server(503))
            val model = AO3TagSetState(42, repository, tagSetWrites(client, auth))
            model.load()
            assertEquals(tagSetReadUrls(42), client.gets)
            val data = model.state.value.data!!
            assertEquals(7, data.totalTagCount)
            assertEquals(failed == "nominations", data.isNominated)
            assertEquals(if (failed == "edit") 5 else 1, data.reviewQueue.size)
            assertNull(model.state.value.failure)
            assertEquals(0, client.posts)
        }
        val (auth, client, repository) = tagSetSetup(44, "Other_Viewer")
        val result = repository.getTagSet(44) as AO3Result.Success<AO3TagSetSnapshot>
        assertEquals(3, result.value.totalTagCount)
        assertEquals(2, result.value.reviewQueue.size)
        assertEquals(tagSetReadUrls(44), client.gets)
        assertTrue(result.value.tagnames.values.all(String::isEmpty))
    }

    @Test fun requiredFailureStopsAfterOneReadAndTryAgainCanLoad() = runTest {
        val (auth, client, repository) = tagSetSetup()
        client.replies[AO3TagSetUrls.page(42)] = AO3Result.Failure(AO3Error.Forbidden)
        val model = AO3TagSetState(42, repository, tagSetWrites(client, auth))
        model.load()
        assertNull(model.state.value.data)
        assertEquals("AO3 refused the request (HTTP 403). Wait a while before trying again.", model.state.value.failure)
        assertEquals(listOf(AO3TagSetUrls.page(42)), client.gets)
        client.replies.clear()
        model.load()
        assertNotNull(model.state.value.data)
        assertNull(model.state.value.failure)
        assertEquals(listOf(AO3TagSetUrls.page(42)) + tagSetReadUrls(42), client.gets)
    }

    @Test fun staleGenerationAndDisposalNeverInstallPrivateRowsOrContinueOptionalReads() = runTest {
        for (url in tagSetReadUrls(42)) {
            val (auth, client, repository) = tagSetSetup()
            client.afterGet = { if (it == url) auth.logout() }
            val model = AO3TagSetState(42, repository, tagSetWrites(client, auth))
            try { model.load(); fail("Expected cancellation") } catch (_: kotlinx.coroutines.CancellationException) { }
            assertNull(model.state.value.data)
            assertEquals(tagSetReadUrls(42).take(tagSetReadUrls(42).indexOf(url) + 1), client.gets)
            assertEquals(0, client.posts)
        }
        val (auth, client, repository) = tagSetSetup()
        client.hold = true
        val model = AO3TagSetState(42, repository, tagSetWrites(client, auth))
        val load = async { model.load() }
        client.entered.await()
        assertTrue(model.state.value.loading)
        model.close()
        client.release.complete(Unit)
        load.join()
        assertNull(model.state.value.data)
        assertEquals(1, client.gets.size)
    }
}

internal fun tagSetFixture(name: String): String = listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures", "android/app/src/debug/assets/fixtures")
    .map { File(it, "$name.html") }.first { it.isFile }.readText()
internal fun tagSetReadUrls(id: Int) = listOf(AO3TagSetUrls.page(id), AO3TagSetUrls.edit(id), AO3TagSetUrls.nominations(id))
internal suspend fun tagSetSetup(id: Int = 42, username: String? = "AO3_Reader"):
    Triple<AO3AuthRepository, TagSetReadClient, AO3CollectionDetailRepository> {
    val auth = AO3AuthRepository(MemorySessionStore(username?.let { testSession(it) }), MemoryCookieStore())
    auth.restoreSession()
    val client = TagSetReadClient(id)
    return Triple(auth, client, AO3CollectionDetailRepository(client, auth, parseDispatcher = Dispatchers.Unconfined))
}
internal class TagSetReadClient(private val id: Int) : AO3Client, AO3FormPostClient {
    val gets = mutableListOf<String>()
    val publicReads = mutableListOf<String>()
    val authenticatedReads = mutableListOf<String>()
    val replies = mutableMapOf<String, AO3Result<AO3HttpResponse>>()
    var posts = 0
    val postRequests = mutableListOf<TagSetPost>()
    var postReply: AO3Result<AO3HttpResponse> = AO3Result.Success(AO3HttpResponse(
        AO3TagSetUrls.page(id), 200, emptyMap(), "<div class='flash notice'>Saved.</div>"))
    var holdPost = false
    val postEntered = CompletableDeferred<Unit>()
    val postRelease = CompletableDeferred<Unit>()
    var afterPost: suspend () -> Unit = {}
    var hold = false
    val entered = CompletableDeferred<Unit>()
    val release = CompletableDeferred<Unit>()
    var afterGet: suspend (String) -> Unit = {}
    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        gets += url
        if (headers.isEmpty()) publicReads += url else {
            check(headers["Cookie"].orEmpty().isNotEmpty())
            authenticatedReads += url
        }
        entered.complete(Unit)
        if (hold) release.await()
        afterGet(url)
        replies[url]?.let { return it }
        val fixture = when (url) {
            AO3TagSetUrls.page(id) -> "ao3_demo_tag_set_$id"
            AO3TagSetUrls.edit(id) -> if (id == 44) return AO3Result.Failure(AO3Error.Forbidden)
                else if (id == 43) "ao3_demo_tag_set_43" else "ao3_demo_tag_set_${id}_edit"
            AO3TagSetUrls.nominations(id) -> "ao3_demo_tag_set_${id}_nominations"
            else -> error("Unexpected tag-set read: $url")
        }
        return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), tagSetFixture(fixture)))
    }
    override suspend fun postForm(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        posts++
        check(headers["Cookie"].orEmpty().isNotEmpty())
        postRequests += TagSetPost(url, formFields, headers)
        postEntered.complete(Unit)
        if (holdPost) postRelease.await()
        afterPost()
        return postReply
    }
}

internal data class TagSetPost(val url: String, val fields: List<Pair<String, String>>, val headers: Map<String, String>)
internal fun tagSetWrites(client: TagSetReadClient, auth: AO3AuthRepository) =
    AO3WriteRepository(DefaultAO3AuthenticatedClient(client, client, auth))
