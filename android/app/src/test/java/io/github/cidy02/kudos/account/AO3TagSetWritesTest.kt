package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.account.*
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.network.ao3.writes.DefaultAO3AuthenticatedClient
import java.io.IOException
import java.util.concurrent.CopyOnWriteArrayList
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.Protocol
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class AO3TagSetWritesTest {
    private val parser = AO3TagSetParser()
    private val unconfirmed = "AO3 replied but didn't confirm the change went through. Check on AO3 before trying again."
    private val missingToken = "Couldn't prepare the request. Try again, or open the work on AO3."
    private fun response(status: Int, body: String): AO3Result<AO3HttpResponse> = AO3Result.Success(
        AO3HttpResponse(AO3TagSetUrls.page(42), status, emptyMap(), body))
    private fun edit() = parser.parse(tagSetFixture("ao3_demo_tag_set_42_edit"), 42)
    private fun nomination(field: AO3TagSetField = AO3TagSetField.Freeform) =
        AO3TagNomination(5, "Letters [Winter] & Snow", field, AO3TagNominationState.Unreviewed)

    @Test fun draftsBeginWithServedEditValuesAndOnlyExplicitRefreshReplacesThemWithoutWriting() = runTest {
        val (auth, client, repo) = tagSetSetup(id = 43)
        val model = AO3TagSetState(43, repo, tagSetWrites(client, auth))
        model.load()
        assertEquals("Cloudbound Courier", model.state.value.fields[AO3TagSetField.Fandom])
        assertEquals("Oren Reed", model.state.value.fields[AO3TagSetField.Character])
        model.change(AO3TagSetField.Character, "New draft")
        assertEquals(tagSetReadUrls(43), client.gets)
        model.load()
        assertEquals("Oren Reed", model.state.value.fields[AO3TagSetField.Character])
        assertEquals(tagSetReadUrls(43) + tagSetReadUrls(43), client.gets)
        assertEquals(0, client.posts)
    }

    @Test fun saveUsesCapturedActionAndOverrideFreshMetaAndAllFourUnmodifiedStringsIncludingEmpty() = runTest {
        val (auth, client, _) = tagSetSetup()
        client.replies[AO3TagSetUrls.edit(42)] = response(200, """
            <meta name='csrf-token' content='fresh-save'>
            <form action='/tag_sets/999'><input name='_method' value='patch'>
            <input name='authenticity_token' value='wrong-input-token'></form>
        """)
        val fields = linkedMapOf(AO3TagSetField.Fandom to " Harbor, [Lantern] & Snow \n",
            AO3TagSetField.Character to "", AO3TagSetField.Relationship to "Mira/Oren", AO3TagSetField.Freeform to "")
        assertTrue(tagSetWrites(client, auth).saveTagSetFields(edit(), fields, auth.generation.value) is AO3Result.Success)
        assertEquals(listOf(AO3TagSetUrls.edit(42)), client.gets)
        val post = client.postRequests.single()
        assertEquals(AO3TagSetUrls.page(42), post.url)
        assertEquals(listOf("authenticity_token" to "fresh-save", "_method" to "put",
            "owned_tag_set[tag_set_attributes][fandom_tagnames_to_add]" to " Harbor, [Lantern] & Snow \n",
            "owned_tag_set[tag_set_attributes][character_tagnames_to_add]" to "",
            "owned_tag_set[tag_set_attributes][relationship_tagnames_to_add]" to "Mira/Oren",
            "owned_tag_set[tag_set_attributes][freeform_tagnames_to_add]" to ""), post.fields)
        assertEquals("fresh-save", post.headers["X-CSRF-Token"])
        assertEquals(AO3TagSetUrls.edit(42), post.headers["Referer"])
        assertTrue(post.headers["Cookie"].orEmpty().isNotEmpty())
        assertFalse(post.headers.containsKey("X-Requested-With"))
        assertFalse(post.headers.containsKey("Accept"))
        assertEquals(1, client.posts)
    }

    @Test fun absentOverrideIsOmittedButEveryEmptyFieldIsPresent() = runTest {
        val (auth, client, _) = tagSetSetup()
        tagSetWrites(client, auth).saveTagSetFields(edit().copy(httpMethodOverride = null), emptyMap(), auth.generation.value)
        assertEquals(listOf("authenticity_token" to "demo-tag-set-42") + AO3TagSetField.entries.map { it.tagnamesParameter to "" },
            client.postRequests.single().fields)
        assertEquals(1, client.gets.size)
        assertEquals(1, client.posts)
    }

    @Test fun rejectEachWireFieldReplacesBracketsBeforeFormEncodingAndPostsToTokenPage() = runTest {
        for (field in AO3TagSetField.entries) {
            val (auth, client, _) = tagSetSetup()
            client.replies[AO3TagSetUrls.nominations(42)] = response(200,
                "<meta name='csrf-token' content='fresh-reject'><input name='authenticity_token' value='wrong-input'>")
            assertTrue(tagSetWrites(client, auth).reportRejectedTag(42, nomination(field), auth.generation.value) is AO3Result.Success)
            assertEquals(listOf(AO3TagSetUrls.nominations(42)), client.gets)
            val post = client.postRequests.single()
            assertEquals(AO3TagSetUrls.nominations(42), post.url)
            assertEquals(listOf("_method" to "put", "authenticity_token" to "fresh-reject",
                "${field.wireName}_reject_Letters #LBRACKETWinter#RBRACKET & Snow" to "1"), post.fields)
            val encoded = AO3FormEncoding.encode(post.fields)
            assertTrue(encoded.contains("%23LBRACKETWinter%23RBRACKET"))
            assertTrue(encoded.contains("%26"))
            assertEquals("fresh-reject", post.headers["X-CSRF-Token"])
            assertEquals(post.url, post.headers["Referer"])
            assertFalse(post.headers.containsKey("X-Requested-With"))
            assertFalse(post.headers.containsKey("Accept"))
            assertEquals(1, client.posts)
        }
    }

    @Test fun bothWritesUseIosVerdictPriorityAndFallbackWithoutRetryOrExtraGet() = runTest {
        for (save in listOf(true, false)) {
            val cases = listOf(
                response(200, "<div class='flash notice'>Updated.</div>") to null,
                response(302, "") to null,
                response(200, "<div class='flash error'>AO3's reason.</div><div class='flash notice'>Updated.</div>") to "AO3's reason.",
                response(302, "<div class='flash error'>AO3's reason.</div>") to "AO3's reason.",
                response(422, "<div class='flash error'>List refused.</div>") to "List refused.",
                response(200, "<h2>No confirmation</h2>") to unconfirmed,
                response(204, "") to unconfirmed,
                response(422, "") to if (save) "AO3 couldn't save that tag set." else "AO3 couldn't reject that tag.")
            for ((reply, error) in cases) {
                val (auth, client, _) = tagSetSetup()
                client.postReply = reply
                val writes = tagSetWrites(client, auth)
                val result = if (save) writes.saveTagSetFields(edit(), emptyMap(), auth.generation.value)
                    else writes.reportRejectedTag(42, nomination(), auth.generation.value)
                if (error == null) assertTrue(result is AO3Result.Success)
                else assertEquals(error, (result as AO3Result.Failure).error.moderationMessage())
                assertEquals(1, client.gets.size)
                assertEquals(1, client.posts)
            }
        }
    }

    @Test fun tokenFailureMissingMetaAndSignedOutNeverPostAndHaveExactIosWords() = runTest {
        for (save in listOf(true, false)) {
            for ((read, message) in listOf(
                response(200, "<input name='authenticity_token' value='input-only'>") to missingToken,
                AO3Result.Failure(AO3Error.Forbidden) to "AO3 refused the request (HTTP 403). Wait a while before trying again.",
                AO3Result.Failure(AO3Error.Network("offline", IOException("offline"), offline = true)) to "You're offline. Connect to the internet and try again.")) {
                val (auth, client, _) = tagSetSetup()
                client.replies[if (save) AO3TagSetUrls.edit(42) else AO3TagSetUrls.nominations(42)] = read
                val writes = tagSetWrites(client, auth)
                val result = if (save) writes.saveTagSetFields(edit(), emptyMap(), auth.generation.value)
                    else writes.reportRejectedTag(42, nomination(), auth.generation.value)
                assertEquals(message, (result as AO3Result.Failure).error.moderationMessage())
                assertEquals(1, client.gets.size)
                assertEquals(0, client.posts)
            }
            val (auth, client, _) = tagSetSetup(username = null)
            val writes = tagSetWrites(client, auth)
            val result = if (save) writes.saveTagSetFields(edit(), emptyMap(), auth.generation.value)
                else writes.reportRejectedTag(42, nomination(), auth.generation.value)
            assertEquals("Log in to AO3 first.", (result as AO3Result.Failure).error.moderationMessage())
            assertTrue(client.gets.isEmpty())
            assertEquals(0, client.posts)
        }
    }

    @Test fun missingCapturedActionIsCheckedOnlyAfterFreshTokenAndNeverBorrowedFromFreshForm() = runTest {
        val (auth, client, _) = tagSetSetup()
        val result = tagSetWrites(client, auth).saveTagSetFields(edit().copy(actionUrl = null), emptyMap(), auth.generation.value)
        assertEquals("Couldn't find AO3's tag-set form.", (result as AO3Result.Failure).error.moderationMessage())
        assertEquals(listOf(AO3TagSetUrls.edit(42)), client.gets)
        assertEquals(0, client.posts)
    }

    @Test fun saveKeepsDraftAndCountsDuringHeldWriteAndOnlyConfirmationShowsNotice() = runTest {
        val (auth, client, repo) = tagSetSetup()
        val model = AO3TagSetState(42, repo, tagSetWrites(client, auth))
        model.load()
        val before = model.state.value.data
        model.change(AO3TagSetField.Fandom, "New Harbor")
        client.holdPost = true
        val job = async { model.save() }
        client.postEntered.await()
        assertTrue(model.state.value.saving)
        assertNull(model.state.value.saveNotice)
        assertEquals(before, model.state.value.data)
        model.save(); model.load()
        assertEquals(4, client.gets.size)
        assertEquals(1, client.posts)
        model.change(AO3TagSetField.Fandom, "Newer Harbor") // iOS fields stay editable while saving.
        client.postRelease.complete(Unit); job.await()
        assertFalse(model.state.value.saving)
        assertEquals("Tags saved.", model.state.value.saveNotice)
        assertEquals("Newer Harbor", model.state.value.fields[AO3TagSetField.Fandom])
        assertEquals(before, model.state.value.data)
        assertEquals(4, client.gets.size)
        assertEquals(1, client.posts)
    }

    @Test fun saveRefusalAndUnconfirmedKeepTypedFieldsAndScreenUnchanged() = runTest {
        for ((reply, reason) in listOf(response(422, "<div class='flash error'>Character tags to add: Uncharted Lantern could not be added.</div>") to
                "Character tags to add: Uncharted Lantern could not be added.", response(200, "") to unconfirmed)) {
            val (auth, client, repo) = tagSetSetup()
            val model = AO3TagSetState(42, repo, tagSetWrites(client, auth))
            model.load(); model.change(AO3TagSetField.Character, "Uncharted Lantern")
            val data = model.state.value.data
            client.postReply = reply
            model.save()
            assertEquals(reason, model.state.value.saveError)
            assertNull(model.state.value.saveNotice)
            assertEquals("Uncharted Lantern", model.state.value.fields[AO3TagSetField.Character])
            assertEquals(data, model.state.value.data)
            assertEquals(4, client.gets.size)
            assertEquals(1, client.posts)
        }
    }

    @Test fun rejectOnlyUpdatesOneRowAndThreeDerivedCountsAfterConfirmationAndGuardsOtherTaps() = runTest {
        val (auth, client, repo) = tagSetSetup()
        val model = AO3TagSetState(42, repo, tagSetWrites(client, auth))
        model.load()
        val before = model.state.value.data!!
        val pending = before.reviewQueue.filter { it.state == AO3TagNominationState.Unreviewed }
        client.holdPost = true
        val job = async { model.reject(pending.last()) }
        client.postEntered.await()
        assertEquals(pending.last().id, model.state.value.nominationInFlight)
        assertEquals(before, model.state.value.data)
        pending.forEach { model.reject(it) }; model.load()
        assertEquals(1, client.posts)
        assertEquals(4, client.gets.size)
        client.postRelease.complete(Unit); job.await()
        val after = model.state.value.data!!
        assertEquals(listOf(2, 1, 2), AO3TagNominationState.entries.map { status -> after.reviewQueue.count { it.state == status } })
        assertEquals(before.reviewQueue.filter { it.id != pending.last().id }, after.reviewQueue.filter { it.id != pending.last().id })
        assertNull(model.state.value.nominationInFlight)
        assertNull(model.state.value.queueError)
        assertEquals(4, client.gets.size)
    }

    @Test fun rejectRefusalUnconfirmedAndTransportFailureRetainQueueAndPrefixIosReason() = runTest {
        for ((reply, reason) in listOf(response(422, "<div class='flash error'>Locked for review.</div>") to "Locked for review.",
            response(200, "") to unconfirmed,
            AO3Result.Failure(AO3Error.RateLimited(null)) to "AO3 is rate-limiting requests. Wait a moment and try again.",
            AO3Result.Failure(AO3Error.Network("drop", IOException("drop"))) to "Couldn't reach AO3. Check your connection and try again.")) {
            val (auth, client, repo) = tagSetSetup()
            val model = AO3TagSetState(42, repo, tagSetWrites(client, auth))
            model.load()
            val before = model.state.value.data!!
            val row = before.reviewQueue.last()
            client.postReply = reply
            model.reject(row)
            assertEquals(before, model.state.value.data)
            assertEquals("Couldn't reject “${row.tagName}”: $reason", model.state.value.queueError)
            assertNull(model.state.value.nominationInFlight)
            assertEquals(1, client.posts)
            assertEquals(4, client.gets.size)
        }
    }

    @Test fun refusedOpeningEditAndSignedOutStillHaveDraftButSavingReportsFailureWithoutPost() = runTest {
        for ((id, username, reason) in listOf(
            Triple(44, "Other_Viewer", "AO3 refused the request (HTTP 403). Wait a while before trying again."),
            Triple(42, null, "Log in to AO3 first."))) {
            val reads = if (username == null) 1 else 4
            val (auth, client, repo) = tagSetSetup(id, username)
            val model = AO3TagSetState(id, repo, tagSetWrites(client, auth))
            model.load()
            assertTrue(model.state.value.fields.values.all(String::isEmpty))
            model.change(AO3TagSetField.Fandom, "Retained input")
            model.save()
            assertEquals(reason, model.state.value.saveError)
            assertEquals("Retained input", model.state.value.fields[AO3TagSetField.Fandom])
            assertEquals(reads, client.gets.size)
            assertEquals(0, client.posts)
            if (username == null) {
                val before = model.state.value.data!!
                model.reject(before.reviewQueue.first())
                assertEquals(before, model.state.value.data)
                assertEquals("Couldn't reject “Paper Harbor”: Log in to AO3 first.", model.state.value.queueError)
                assertEquals(1, client.gets.size)
            }
        }
    }

    @Test fun failedPreparationForBothActionsPreservesScreenAndExactFailureFeedback() = runTest {
        for (save in listOf(true, false)) {
            val (auth, client, repo) = tagSetSetup()
            val model = AO3TagSetState(42, repo, tagSetWrites(client, auth))
            model.load()
            val before = model.state.value.data!!
            model.change(AO3TagSetField.Freeform, "Retained draft")
            client.replies[if (save) AO3TagSetUrls.edit(42) else AO3TagSetUrls.nominations(42)] =
                response(200, "<input name='authenticity_token' value='input-only'>")
            if (save) model.save() else model.reject(before.reviewQueue.last())
            assertEquals(before, model.state.value.data)
            assertEquals("Retained draft", model.state.value.fields[AO3TagSetField.Freeform])
            if (save) assertEquals(missingToken, model.state.value.saveError)
            else assertEquals("Couldn't reject “Letters [Winter]”: $missingToken", model.state.value.queueError)
            assertEquals(0, client.posts)
            assertEquals(4, client.gets.size)
        }
    }

    @Test fun sessionChangeDuringEitherTokenReadNeverPostsOrPublishesFeedback() = runTest {
        for (save in listOf(true, false)) {
            val (auth, client, repo) = tagSetSetup()
            val model = AO3TagSetState(42, repo, tagSetWrites(client, auth))
            model.load()
            val before = model.state.value.data!!
            client.afterGet = { auth.logout() }
            if (save) model.save() else model.reject(before.reviewQueue.last())
            assertEquals(0, client.posts)
            assertEquals(before, model.state.value.data)
            assertNull(model.state.value.saveNotice)
            assertNull(model.state.value.queueError)
        }
    }

    @Test fun actualSharedTransportStampsHeadersEncodesBracketsAndNeverRetriesEitherWriteOn429Or503() = runTest {
        for (save in listOf(true, false)) for (status in listOf(200, 429, 503)) {
            val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
            auth.restoreSession()
            val requests = CopyOnWriteArrayList<Request>()
            val http = OkHttpClient.Builder().addInterceptor { chain ->
                val request = chain.request()
                requests += request
                val body = if (request.method == "GET") "<meta name='csrf-token' content='fresh-wire'>"
                    else "<div class='flash notice'>Confirmed.</div>"
                Response.Builder().request(request).protocol(Protocol.HTTP_1_1)
                    .code(if (request.method == "GET") 200 else status).message("Local answer")
                    .body(body.toResponseBody()).build() // Terminal: no sockets, even on an erroneous retry.
            }.build()
            val config = AO3NetworkConfig(minDelayBetweenRequestsMillis = 0)
            val client = OkHttpAO3Client(http, config)
            val writes = AO3WriteRepository(DefaultAO3AuthenticatedClient(client, client, auth))
            val result = if (save) writes.saveTagSetFields(edit(), emptyMap(), auth.generation.value)
                else writes.reportRejectedTag(42, nomination(), auth.generation.value)
            assertEquals(status == 200, result is AO3Result.Success)
            assertEquals(listOf("GET", "POST"), requests.map { it.method })
            val get = requests.first()
            val post = requests.last()
            assertEquals(if (save) AO3TagSetUrls.edit(42) else AO3TagSetUrls.nominations(42), get.url.toString())
            assertEquals(if (save) AO3TagSetUrls.page(42) else AO3TagSetUrls.nominations(42), post.url.toString())
            assertEquals(AO3UserAgent.VALUE, post.header("User-Agent"))
            assertTrue(post.header("Cookie").orEmpty().isNotEmpty())
            assertEquals("fresh-wire", post.header("X-CSRF-Token"))
            assertEquals(get.url.toString(), post.header("Referer"))
            assertNull(post.header("X-Requested-With"))
            assertNull(post.header("Accept"))
            assertEquals("application/x-www-form-urlencoded; charset=UTF-8", post.body!!.contentType().toString())
            val buffer = Buffer(); post.body!!.writeTo(buffer)
            val expected = if (save) "authenticity_token=fresh-wire&_method=put&" +
                "owned_tag_set%5Btag_set_attributes%5D%5Bfandom_tagnames_to_add%5D=&" +
                "owned_tag_set%5Btag_set_attributes%5D%5Bcharacter_tagnames_to_add%5D=&" +
                "owned_tag_set%5Btag_set_attributes%5D%5Brelationship_tagnames_to_add%5D=&" +
                "owned_tag_set%5Btag_set_attributes%5D%5Bfreeform_tagnames_to_add%5D="
            else "_method=put&authenticity_token=fresh-wire&freeform_reject_Letters%20%23LBRACKETWinter%23RBRACKET%20%26%20Snow=1"
            assertEquals(expected, buffer.readUtf8())
        }
    }

    @Test fun sharedPacingSessionFenceCancelsBothQueuedPosts() = runTest {
        for (save in listOf(true, false)) {
            val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
            auth.restoreSession()
            val methods = CopyOnWriteArrayList<String>()
            val http = OkHttpClient.Builder().addInterceptor { chain ->
                methods += chain.request().method
                Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("Local answer")
                    .body("<meta name='csrf-token' content='fresh'>".toResponseBody()).build()
            }.build()
            val config = AO3NetworkConfig(minDelayBetweenRequestsMillis = 600)
            var paced = false
            val coordinator = AO3RequestCoordinator(config, AO3Clock { 0 }, AO3Delay { paced = true; auth.logout() })
            val client = OkHttpAO3Client(http, config, coordinator)
            val writes = AO3WriteRepository(DefaultAO3AuthenticatedClient(client, client, auth))
            try {
                if (save) writes.saveTagSetFields(edit(), emptyMap(), auth.generation.value)
                else writes.reportRejectedTag(42, nomination(), auth.generation.value)
                fail("Stale queued write must be cancelled")
            } catch (_: kotlinx.coroutines.CancellationException) { }
            assertTrue(paced)
            assertEquals(listOf("GET"), methods)
        }
    }

    @Test fun disposalAndLogoutDuringSentWritesFinishOnePostButNeverChangeDepartedScreen() = runTest {
        for (save in listOf(true, false)) for (logout in listOf(true, false)) {
            val (auth, client, repo) = tagSetSetup()
            val model = AO3TagSetState(42, repo, tagSetWrites(client, auth))
            model.load()
            val before = model.state.value.data!!
            client.holdPost = true
            val job = async { if (save) model.save() else model.reject(before.reviewQueue.last()) }
            client.postEntered.await()
            if (logout) auth.logout() else model.close()
            client.postRelease.complete(Unit); job.join()
            assertEquals(1, client.posts)
            assertEquals(4, client.gets.size)
            assertEquals(before, model.state.value.data)
            assertNull(model.state.value.saveNotice)
            assertNull(model.state.value.queueError)
        }
    }
}
