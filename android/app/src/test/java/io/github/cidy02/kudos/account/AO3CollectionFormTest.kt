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
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Test

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class AO3CollectionFormTest {
    private val parser = AO3CollectionFormParser()

    @Test fun fixturesParseDefaultsEditLocksOwnerIdsAndErrors() {
        val new = parser.parse(collectionFixture("new"), null)
        assertEquals("https://archiveofourown.org/collections", new.actionUrl)
        assertEquals("demo-collection-new-token", new.csrfToken)
        assertNull(new.methodOverride)
        assertEquals("", new[AO3CollectionFields.TITLE])
        assertEquals(listOf("81", "82"), new.ownerIds)
        assertEquals(3, new.challengeOptions.size)
        assertFalse(new.allowsDelete)
        val edit = parser.parse(collectionFixture("edit"), "winter_exchange")
        assertEquals("Winter Exchange 2026", edit[AO3CollectionFields.TITLE])
        assertEquals("winter_exchange", edit[AO3CollectionFields.NAME])
        assertEquals("patch", edit.methodOverride)
        assertTrue(edit.allowsDelete && edit.emailNotifyIsPresent)
        assertEquals("1", edit[AO3CollectionFields.preference("moderated")])
        assertEquals("Bring a story and a lantern.", edit[AO3CollectionFields.profile("intro")])
        assertTrue(edit.challengeOptions.isEmpty())
        val invalid = parser.parse(collectionFixture("invalid"), null)
        assertEquals("Name has already been taken", invalid.fieldErrors[AO3CollectionFields.NAME])
        assertEquals(listOf("Name has already been taken"), invalid.generalErrors)
        assertEquals("demo-collection-destroy-token", parser.destroyToken(collectionFixture("destroy")))
    }

    @Test fun bodyMatchesIosIncludesUnchangedDisabledAndRepeatedOwnersAndExcludesUnencodedFields() {
        val form = parser.parse(collectionFixture("edit"), "winter_exchange")
            .changed(AO3CollectionFields.TITLE, "Winter & Lanterns")
            .changed(AO3CollectionFields.NAME, "cannot_rename")
            .changed(AO3CollectionFields.preference("closed"), "1")
        val fields = form.parameters()
        val expected = listOf("_method" to "patch", "authenticity_token" to "demo-collection-edit-token",
            "collection[name]" to "winter_exchange", "collection[title]" to "Winter & Lanterns",
            "collection[email]" to "winterquill@example.invalid", "collection[header_image_url]" to "",
            "collection[description]" to "A fictional exchange of warm letters.", "collection[parent_name]" to "",
            "collection[icon_alt_text]" to "A paper lantern", "collection[icon_comment_text]" to "Original demo artwork",
            "collection[tag_string]" to "Winter letters", "collection[multifandom]" to "1", "collection[delete_icon]" to "0",
            "collection[collection_preference_attributes][moderated]" to "1",
            "collection[collection_preference_attributes][closed]" to "1",
            "collection[collection_preference_attributes][unrevealed]" to "0",
            "collection[collection_preference_attributes][anonymous]" to "1",
            "collection[collection_preference_attributes][show_random]" to "1",
            "collection[collection_profile_attributes][intro]" to "Bring a story and a lantern.",
            "collection[collection_profile_attributes][faq]" to "May I bring a poem? Yes.",
            "collection[collection_profile_attributes][rules]" to "Leave a kind reply.",
            "collection[collection_profile_attributes][gift_notification]" to "A parcel awaits.",
            "collection[collection_profile_attributes][assignment_notification]" to "Your writing prompt is ready.",
            "collection[collection_preference_attributes][id]" to "701",
            "collection[collection_profile_attributes][id]" to "702",
            "collection[collection_preference_attributes][email_notify]" to "1",
            "owner_pseuds[]" to "81", "owner_pseuds[]" to "82")
        assertEquals(expected.toSet(), fields.toSet())
        assertEquals(expected.size, fields.size)
        val new = parser.parse(collectionFixture("new"), null).parameters().toMap()
        assertEquals("", new["challenge_type"])
        assertFalse(new.containsKey("_method"))
        assertFalse(new.containsKey("collection[header_image_alt]"))
        assertFalse(new.containsKey("demo_unsubmitted"))
        val missing = parser.parse(collectionFixture("new").replace("collection[collection_preference_attributes][email_notify]", "unrelated"), null)
        assertFalse(missing.parameters().toMap().containsKey(AO3CollectionFields.preference("email_notify")))
    }

    @Test fun untrustedLoginMissingTokenAndMissingFormAreRejected() {
        for (html in listOf("<p>Unknown page</p>", "<form id='new_user' action='/users/login'></form>",
            collectionFixture("new").replace("action=\"/collections\"", "action=\"https://example.com/collections\""),
            collectionFixture("new").replace("csrf-token", "absent").replace("authenticity_token", "absent"))) {
            assertThrows(Exception::class.java) { parser.parse(html, null) }
        }
    }

    @Test fun fiveQuickCharactersProduceOneAnonymousReadAndOnlySettledValueIsMarked() = runTest {
        val (_, client, model) = setup()
        model.load()
        for (name in listOf("l", "la", "lan", "lant", "lante")) {
            model.change(AO3CollectionFields.NAME, name)
            advanceTimeBy(100)
        }
        advanceTimeBy(499); runCurrent()
        assertTrue(client.anonymousGets.isEmpty())
        advanceTimeBy(1); runCurrent()
        assertEquals(listOf("https://archiveofourown.org/collections/lante"), client.anonymousGets)
        assertTrue(client.anonymousHeaders.single().isEmpty())
        assertEquals(AO3CollectionNameAvailability.Available, model.state.value.availability)
    }

    @Test fun emptyInvalidReservedAndEditNamesMakeNoAvailabilityRequest() = runTest {
        val (_, client, model) = setup()
        model.load()
        for (name in listOf("", "_bad", "new", "edit", "list_challenges")) {
            model.change(AO3CollectionFields.NAME, name)
            advanceTimeBy(700); runCurrent()
        }
        assertTrue(client.anonymousGets.isEmpty())
        assertEquals(AO3CollectionNameAvailability.Taken, model.state.value.availability)
        val (_, editClient, edit) = setup("winter_exchange")
        edit.load(); edit.change(AO3CollectionFields.NAME, "new_name")
        advanceTimeBy(700); runCurrent()
        assertTrue(editClient.anonymousGets.isEmpty())
        assertEquals("winter_exchange", edit.state.value.form!![AO3CollectionFields.NAME])
    }

    @Test fun leavingCancelsPendingCheckAndCancelNeverPosts() = runTest {
        val (_, client, model) = setup()
        model.load(); fill(model)
        model.close()
        advanceTimeBy(1000); runCurrent()
        model.confirmSave()
        assertTrue(client.posts.isEmpty() && client.anonymousGets.isEmpty())
    }

    @Test fun olderNoncancellableNameReplyCannotMarkTheNewName() = runTest {
        val (_, client, model) = setup()
        model.load()
        client.holdProbe = true
        model.change(AO3CollectionFields.NAME, "first_name")
        advanceTimeBy(600); runCurrent()
        client.probeEntered.await()
        model.change(AO3CollectionFields.NAME, "second_name")
        client.holdProbe = false
        client.probeRelease.complete(Unit)
        runCurrent()
        assertNull(model.state.value.availability)
        advanceTimeBy(600); runCurrent()
        assertEquals(AO3CollectionNameAvailability.Available, model.state.value.availability)
        assertEquals(2, client.anonymousGets.size)
    }

    @Test fun failedProbeIsUnknownAndDoesNotBlockSaveOrRetry() = runTest {
        val (_, client, model) = setup()
        model.load(); fill(model)
        client.probeReply = AO3Result.Failure(AO3Error.Network("offline"))
        advanceTimeBy(600); runCurrent()
        assertEquals(AO3CollectionNameAvailability.Unknown, model.state.value.availability)
        assertTrue(model.state.value.canSave)
        advanceTimeBy(5000); runCurrent()
        assertEquals(1, client.anonymousGets.size)
        model.confirmSave()
        assertEquals(1, client.posts.size)
    }

    @Test fun availabilityMapsStatusAndTakenAndInvalidBlockSave() = runTest {
        val (_, client, model) = setup()
        model.load(); fill(model)
        client.probeReply = collectionResponse("occupied", 200)
        advanceTimeBy(600); runCurrent()
        assertEquals(AO3CollectionNameAvailability.Taken, model.state.value.availability)
        assertFalse(model.state.value.canSave)
        model.change(AO3CollectionFields.NAME, "_bad")
        assertFalse(model.state.value.canSave)
        client.probeReply = collectionResponse("not found", 404)
        assertEquals(AO3CollectionNameAvailability.Available,
            AO3CollectionDetailRepository(client, client.auth).collectionNameAvailable("free_name"))
        client.probeReply = collectionResponse("unknown", 204)
        assertEquals(AO3CollectionNameAvailability.Unknown,
            AO3CollectionDetailRepository(client, client.auth).collectionNameAvailable("free_name"))
    }

    @Test fun freshTokenOriginalActionAndValuesOnePostForDoubleConfirmation() = runTest {
        val (_, client, model) = setup()
        model.load(); fill(model)
        client.html = collectionFixture("new").replace("demo-collection-new-token", "fresh-token")
            .replace("action=\"/collections\"", "action=\"/collections?changed=1\"")
        client.holdPost = true
        val saving = async { model.confirmSave() }
        client.postEntered.await()
        model.confirmSave()
        assertEquals(2, client.authenticatedGets.size)
        assertEquals(1, client.posts.size)
        assertEquals("fresh-token", client.posts.single().toMap()["authenticity_token"])
        assertEquals("https://archiveofourown.org/collections", client.postUrls.single())
        assertEquals("Lanterns & Letters", client.posts.single().toMap()["collection[title]"])
        client.postRelease.complete(Unit); saving.await()
        assertNotNull(model.state.value.notice)
    }

    @Test fun invalidServerMessageAppearsBesideFieldAndTypedEntriesAreKept() = runTest {
        val (_, client, model) = setup()
        model.load(); fill(model)
        model.change(AO3CollectionFields.profile("intro"), "  My exact\nentry  ")
        advanceTimeBy(600); runCurrent()
        assertEquals(AO3CollectionNameAvailability.Available, model.state.value.availability)
        client.postReply = collectionResponse(collectionFixture("invalid"), 422)
        val entries = model.state.value.form!!.values
        model.confirmSave()
        assertEquals(entries, model.state.value.form!!.values)
        assertEquals("Name has already been taken", model.state.value.form!!.fieldErrors[AO3CollectionFields.NAME])
        // AO3's word on the name is said once, and outranks the earlier "available".
        assertEquals(1, model.state.value.form!!.generalErrors.count { it == "Name has already been taken" })
        assertNull(model.state.value.availability)
        assertNull(model.state.value.notice)
        assertEquals(1, client.posts.size)
    }

    @Test fun unconfirmedTransportAndRefusalKeepEntriesAndNeverRetry() = runTest {
        for (reply in listOf(collectionResponse("<p>No confirmation</p>"),
            collectionResponse("<div class='flash error'>Refused</div><div class='flash notice'>Saved</div>"),
            AO3Result.Failure(AO3Error.Network("Lost reply")))) {
            val (_, client, model) = setup()
            model.load(); fill(model); val entries = model.state.value.form!!.values
            client.postReply = reply; model.confirmSave()
            assertEquals(1, client.posts.size)
            assertEquals(entries, model.state.value.form!!.values)
            assertTrue(model.state.value.form!!.generalErrors.isNotEmpty())
            assertNull(model.state.value.notice)
        }
    }

    @Test fun sessionChangeDuringFreshReadSendsNothingAndDuringPostDoesNotTouchScreen() = runTest {
        for (duringPost in listOf(false, true)) {
            val (auth, client, model) = setup()
            model.load(); fill(model)
            client.holdGet = !duringPost; client.holdPost = duringPost
            val save = async { model.confirmSave() }
            if (duringPost) client.postEntered.await() else client.getEntered.await()
            val before = model.state.value
            auth.logout()
            if (duringPost) client.postRelease.complete(Unit) else client.getRelease.complete(Unit)
            save.await()
            assertEquals(before, model.state.value)
            assertEquals(if (duringPost) 1 else 0, client.posts.size)
        }
    }

    @Test fun sessionChangeDuringInitialLoadDoesNotInstallForm() = runTest {
        val (auth, client, model) = setup()
        client.holdGet = true
        val loading = async { model.load() }
        client.getEntered.await(); val before = model.state.value
        auth.logout(); client.getRelease.complete(Unit); loading.await()
        assertEquals(before, model.state.value)
        assertNull(model.state.value.form)
    }

    @Test fun deleteRequiresOfferedControlExactTypedNameAndFreshDestroyToken() = runTest {
        val (_, client, model) = setup("winter_exchange")
        model.load()
        model.confirmDelete("wrong"); model.confirmDelete("")
        assertTrue(client.posts.isEmpty())
        model.confirmDelete("  Winter Exchange 2026  ")
        assertEquals(2, client.authenticatedGets.size)
        assertEquals("https://archiveofourown.org/collections/winter_exchange/confirm_delete", client.authenticatedGets.last())
        assertEquals(listOf("_method" to "delete", "authenticity_token" to "demo-collection-destroy-token"), client.posts.single())
        assertTrue(model.state.value.deleted)
        model.confirmDelete("Winter Exchange 2026")
        assertEquals(1, client.posts.size)
        val (_, freshClient, newModel) = setup()
        newModel.load(); newModel.confirmDelete("collection")
        assertTrue(freshClient.posts.isEmpty())
    }

    @Test fun deleteRefusalAndMissingDestroyControlAndSessionChangesNeverRetryOrDismiss() = runTest {
        val (_, client, model) = setup("winter_exchange")
        model.load(); client.destroyHtml = "<meta name='csrf-token' content='meta-is-not-delete-token'>"
        model.confirmDelete("Winter Exchange 2026")
        assertTrue(client.posts.isEmpty()); assertFalse(model.state.value.deleted)
        client.destroyHtml = collectionFixture("destroy")
        client.postReply = collectionResponse("<div class='flash error'>Cannot delete</div>", 422)
        model.confirmDelete("Winter Exchange 2026")
        assertEquals(1, client.posts.size); assertFalse(model.state.value.deleted)
        for (duringPost in listOf(false, true)) {
            val (auth, heldClient, held) = setup("winter_exchange")
            held.load(); heldClient.holdGet = !duringPost; heldClient.holdPost = duringPost
            val deleting = async { held.confirmDelete("Winter Exchange 2026") }
            if (duringPost) heldClient.postEntered.await() else heldClient.getEntered.await()
            val before = held.state.value; auth.logout()
            if (duringPost) heldClient.postRelease.complete(Unit) else heldClient.getRelease.complete(Unit)
            deleting.await()
            assertEquals(before, held.state.value)
            assertFalse(held.state.value.deleted)
            assertEquals(if (duringPost) 1 else 0, heldClient.posts.size)
        }
    }

    private fun fill(model: AO3CollectionFormState) {
        model.change(AO3CollectionFields.TITLE, "Lanterns & Letters")
        model.change(AO3CollectionFields.NAME, "lantern_archive")
    }

    private suspend fun TestScope.setup(slug: String? = null): Triple<AO3AuthRepository, CollectionFormClient, AO3CollectionFormState> {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val client = CollectionFormClient(auth, if (slug == null) "new" else "edit")
        return Triple(auth, client, AO3CollectionFormState(slug, AO3CollectionDetailRepository(client, auth),
            AO3WriteRepository(client), backgroundScope))
    }
}

private fun collectionFixture(name: String): String = listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures", "android/app/src/debug/assets/fixtures")
    .map { File(it, "ao3_demo_collection_$name.html") }.first { it.isFile }.readText()

private fun collectionResponse(html: String, status: Int = 200) = AO3Result.Success(AO3HttpResponse(
    "https://archiveofourown.org/collections", status, emptyMap(), html))

/** No production HTTP client is constructed; every read and write terminates in memory. */
private class CollectionFormClient(val auth: AO3AuthRepository, fixture: String) : AO3Client, AO3AuthenticatedClient {
    var html = collectionFixture(fixture)
    var destroyHtml = collectionFixture("destroy")
    val authenticatedGets = mutableListOf<String>()
    val anonymousGets = mutableListOf<String>()
    val anonymousHeaders = mutableListOf<Map<String, String>>()
    val posts = mutableListOf<List<Pair<String, String>>>()
    val postUrls = mutableListOf<String>()
    var probeReply: AO3Result<AO3HttpResponse> = AO3Result.Failure(AO3Error.NotFound)
    var postReply: AO3Result<AO3HttpResponse> = collectionResponse("<div class='flash notice'>Collection saved.</div>")
    var holdGet = false
    var holdPost = false
    var holdProbe = false
    val getEntered = CompletableDeferred<Unit>(); val getRelease = CompletableDeferred<Unit>()
    val postEntered = CompletableDeferred<Unit>(); val postRelease = CompletableDeferred<Unit>()
    val probeEntered = CompletableDeferred<Unit>(); val probeRelease = CompletableDeferred<Unit>()
    override fun username() = auth.username()
    override fun sessionGeneration() = auth.generation.value
    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        if (headers.isNotEmpty()) return getAuthenticated(url)
        anonymousGets += url; anonymousHeaders += headers
        if (holdProbe) withContext(NonCancellable) { probeEntered.complete(Unit); probeRelease.await() }
        return probeReply
    }
    override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> {
        authenticatedGets += url
        if (holdGet) { getEntered.complete(Unit); getRelease.await() }
        return collectionResponse(if (url.endsWith("/confirm_delete")) destroyHtml else html)
    }
    override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>,
        headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        posts += formFields; postUrls += url
        if (holdPost) { postEntered.complete(Unit); postRelease.await() }
        return postReply
    }
}
