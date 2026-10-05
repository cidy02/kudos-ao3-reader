package io.github.cidy02.kudos.account

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.account.*
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import org.junit.Rule
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

class AO3CollectionMaintainersTest {
    @Test fun fixturesParseOwnersModeratorsInvitationAndOnlyOwnerInOrder() {
        val parser = AO3CollectionParticipantsParser()
        val people = parser.parse(maintainersFixture())
        assertEquals(listOf(101, 102, 103, 104, 105, 106, 107), people.map { it.id })
        assertEquals(listOf("AO3_Reader", "frostledger", "emberpost", "duskatlas", "mapfold", "ashletter", "snowink"), people.map { it.pseud })
        assertEquals(listOf("Owner", "Owner", "Moderator", "Moderator", "None", "None", "Invited"), people.map { it.role })
        assertEquals(4, people.count { it.isMaintainer })
        assertEquals(listOf("mapfold", "ashletter"), people.filter { it.isMembershipRequest }.map { it.pseud })
        assertEquals(people.size, people.map { it.pseud }.distinct().size)
        assertEquals(listOf(AO3CollectionParticipant(101, "AO3_Reader", AO3CollectionParticipantRole.Owner.title)),
            parser.parse(maintainersFixture("ao3_demo_maintainers_last_owner")))
    }

    @Test fun parserMatchesIosFallbackIdsSelectedRoleSuffixUnknownRoleAndEmptyBehavior() {
        val people = AO3CollectionParticipantsParser().parse("""
            <ul class='participant index'>
            <li id='777'><a href='/users/alpha'> alpha </a><form action='/collections/winter_exchange/participants/8'>
            <select name='other[participant_role]'><option value='Moderator'>Moderator</option></select></form></li>
            <li id='participant_9'><a href='/users/beta'>beta</a><select name='collection_participant[participant_role]'>
            <option value='Unknown' selected>Unknown</option></select></li>
            <li id='participant_bad'><a href='/users/ignored'>ignored</a></li>
            </ul>
        """.trimIndent())
        assertEquals(listOf(AO3CollectionParticipant(8, "alpha", AO3CollectionParticipantRole.Moderator.title),
            AO3CollectionParticipant(9, "beta", AO3CollectionParticipantRole.Member.title)), people)
        // iOS returns [] for missing markup; do not invent a recognized-empty requirement in this port.
        assertTrue(AO3CollectionParticipantsParser().parse("<p>no rows</p>").isEmpty())
    }

    @Test fun openRefreshAndTypingIssueOnlyTheIosParticipantsReads() = runTest {
        val (_, client, state) = setup()
        state.load()
        state.changeUsername("lanternkeeper")
        state.chooseRole(AO3CollectionParticipantRole.Owner)
        assertEquals(listOf(AO3CollectionParticipantsUrls.page("winter_exchange")), client.gets)
        assertTrue(client.readHeaders.single().containsKey("Cookie"))
        assertEquals(2, state.state.value.owners.size)
        assertEquals(2, state.state.value.moderators.size)
        assertTrue(state.isOwner)
        assertTrue(state.isReader("ao3_reader"))
        state.load()
        assertEquals(2, client.gets.size)
        assertTrue(client.posts.isEmpty())
    }

    @Test fun inviteUsesFreshMetaTokenNoOverrideOrRoleAndSuccessAloneReloads() = runTest {
        val (auth, client, state) = setup()
        state.load()
        state.changeUsername("  lanternkeeper \n")
        state.chooseRole(AO3CollectionParticipantRole.Owner)
        client.html = client.html.replace("demo-participants-token", "fresh-invite-token")
        state.invite()
        val post = client.posts.single()
        assertEquals(AO3CollectionParticipantsUrls.add("winter_exchange"), post.url)
        assertEquals(listOf("authenticity_token" to "fresh-invite-token", "participants_to_invite" to "lanternkeeper"), post.fields)
        assertEquals("fresh-invite-token", post.headers["X-CSRF-Token"])
        assertEquals(AO3CollectionParticipantsUrls.page("winter_exchange"), post.headers["Referer"])
        assertEquals(auth.generation.value, post.generation)
        assertEquals(3, client.gets.size)
        assertEquals("Invitation sent to lanternkeeper.", state.state.value.notice)
        assertEquals("", state.state.value.username)
        assertEquals(AO3CollectionParticipantRole.Owner, state.state.value.role)
        assertEquals(7, state.state.value.participants.size) // Installed only from the read, never a synthetic local row.
    }

    @Test fun secondTapWhileInviteIsOutSendsNothing() = runTest {
        val (_, client, state) = setup()
        state.load(); state.changeUsername("lanternkeeper")
        client.holdPost = true
        val first = async { state.invite() }
        client.postEntered.await()
        state.invite(); state.leaveTap(); state.load()
        assertEquals(1, client.posts.size)
        assertEquals(2, client.gets.size)
        client.postRelease.complete(Unit); first.await()
        assertEquals(1, client.posts.size)
    }

    @Test fun duplicateRefusalAppearsOnceKeepsFieldAndParticipantsAndDoesNotReload() = runTest {
        val (_, client, state) = setup()
        state.load(); state.changeUsername("unknown_username")
        val people = state.state.value.participants
        client.reply = maintainsResponse("<div class='flash error'>Unknown username.</div><div class='error'><p>Unknown username.</p></div>", 422)
        state.invite()
        assertEquals("Unknown username.", state.state.value.inviteError)
        assertNull(state.state.value.notice)
        assertEquals("unknown_username", state.state.value.username)
        assertEquals(people, state.state.value.participants)
        assertEquals(2, client.gets.size)
        assertEquals(1, client.posts.size)
    }

    @Test fun cancelAndLastOwnerOkSendNothingAndLastOwnerCannotConfirm() = runTest {
        val (_, client, state) = setup()
        state.load(); state.leaveTap()
        assertEquals(AO3CollectionMaintainersUiState.Dialog.Owner, state.state.value.dialog)
        state.cancelDialog(); state.confirmLeave()
        assertEquals(1, client.gets.size); assertTrue(client.posts.isEmpty())
        client.html = maintainersFixture("ao3_demo_maintainers_last_owner")
        state.load(); state.leaveTap()
        assertEquals(AO3CollectionMaintainersUiState.Dialog.LastOwner, state.state.value.dialog)
        state.confirmLeave(); state.cancelDialog(); state.confirmLeave()
        assertEquals(2, client.gets.size); assertTrue(client.posts.isEmpty())
        assertFalse(state.state.value.left)
    }

    @Test fun leaveReadsShowAndUsesOnlyDeleteOverrideAndFreshShowMetaThenDismisses() = runTest {
        val (auth, client, state) = setup()
        state.load(); state.leaveTap(); state.confirmLeave()
        assertEquals(listOf(AO3CollectionParticipantsUrls.page("winter_exchange"), AO3CollectionFormUrls.show("winter_exchange")), client.gets)
        val post = client.posts.single()
        assertEquals(AO3CollectionParticipantsUrls.participant("winter_exchange", 101), post.url)
        assertEquals(listOf("_method" to "delete", "authenticity_token" to "demo-maintainers-show-token"), post.fields)
        assertEquals("demo-maintainers-show-token", post.headers["X-CSRF-Token"])
        assertEquals(AO3CollectionFormUrls.show("winter_exchange"), post.headers["Referer"])
        assertEquals(auth.generation.value, post.generation)
        assertTrue(state.state.value.left)
        state.leaveTap(); state.confirmLeave()
        assertEquals(1, client.posts.size)
    }

    @Test fun moderatorCanLeaveAndUnidentifiedReaderGetsIosErrorWithoutWrite() = runTest {
        val (_, moderatorClient, moderator) = setup(username = "EMBERPOST")
        moderator.load(); moderator.leaveTap()
        assertFalse(moderator.isOwner)
        assertEquals(AO3CollectionMaintainersUiState.Dialog.Moderator, moderator.state.value.dialog)
        moderator.confirmLeave()
        assertTrue(moderatorClient.posts.single().url.endsWith("/participants/103"))
        val (_, client, missing) = setup(username = "absent")
        missing.load(); missing.leaveTap(); missing.confirmLeave()
        assertEquals("Could not identify your maintainer record.", missing.state.value.leaveError)
        assertTrue(client.posts.isEmpty()); assertEquals(1, client.gets.size)
    }

    @Test fun repeatedLeaveConfirmWhilePostIsOutSendsNothingAndRefusalDoesNotDismiss() = runTest {
        val (_, client, state) = setup()
        state.load(); state.leaveTap()
        client.holdPost = true
        client.reply = maintainsResponse("<div class='flash error'>Cannot leave now.</div>", 422)
        val first = async { state.confirmLeave() }
        client.postEntered.await()
        state.leaveTap(); state.confirmLeave()
        assertEquals(1, client.posts.size)
        client.postRelease.complete(Unit); first.await()
        assertFalse(state.state.value.left)
        assertEquals("Cannot leave now.", state.state.value.leaveError)
        assertEquals(2, client.gets.size)
    }

    @Test fun missingMetaCannotUseAnotherRowsInputTokenForEitherWrite() = runTest {
        val (auth, client, _) = setup()
        client.html = "<input name='authenticity_token' value='wrong-row'>"
        client.showHtml = client.html
        val writes = AO3WriteRepository(client)
        val expected = AO3Error.Validation("Couldn't prepare the request. Try again, or open the collection on AO3.")
        assertEquals(expected, (writes.inviteMaintainer("winter_exchange", "lanternkeeper", auth.generation.value) as AO3Result.Failure).error)
        assertEquals(expected, (writes.leaveCollection("winter_exchange", 101, auth.generation.value) as AO3Result.Failure).error)
        assertTrue(client.posts.isEmpty())
    }

    @Test fun verdictFollowsIosAndNeverRetriesEitherWrite() = runTest {
        for (leave in listOf(false, true)) for ((reply, expected) in listOf(
            maintainsResponse("<div class='flash error'>Refused.</div><div class='flash notice'>Accepted.</div>", 200) to "Refused.",
            maintainsResponse("<p>unconfirmed</p>", 200) to AO3CollectionFields.UNCONFIRMED,
            maintainsResponse("<p>failure</p>", 500) to (if (leave) "AO3 couldn't leave that collection." else "AO3 couldn't invite that maintainer."),
            AO3Result.Failure(AO3Error.Network("offline")) to null
        )) {
            val (auth, client, _) = setup(); client.reply = reply
            val writes = AO3WriteRepository(client)
            val result = if (leave) writes.leaveCollection("winter_exchange", 101, auth.generation.value)
                else writes.inviteMaintainer("winter_exchange", "lanternkeeper", auth.generation.value)
            assertTrue(result is AO3Result.Failure)
            if (expected != null) assertEquals(AO3Error.Validation(expected), (result as AO3Result.Failure).error)
            assertEquals(1, client.posts.size); assertEquals(1, client.gets.size)
        }
        for (reply in listOf(maintainsResponse("", 302), maintainsResponse("<div class='flash notice'>Done.</div>"))) {
            val (auth, client, _) = setup(); client.reply = reply
            assertTrue(AO3WriteRepository(client).inviteMaintainer("winter_exchange", "lanternkeeper", auth.generation.value) is AO3Result.Success)
        }
    }

    @Test fun staleEntryAndSessionChangeDuringEitherTokenReadCannotPost() = runTest {
        for (leave in listOf(false, true)) {
            val (auth, client, state) = setup()
            state.load(); state.changeUsername("lanternkeeper"); if (leave) state.leaveTap()
            client.holdGet = true
            val request = async { if (leave) state.confirmLeave() else state.invite() }
            client.getEntered.await()
            val before = state.state.value
            auth.logout(); client.getRelease.complete(Unit); request.await()
            assertEquals(before, state.state.value); assertTrue(client.posts.isEmpty())
            val gets = client.gets.size
            try { AO3WriteRepository(client).inviteMaintainer("winter_exchange", "x", auth.generation.value - 1) }
            catch (_: kotlinx.coroutines.CancellationException) { /* expected */ }
            assertEquals(gets, client.gets.size)
        }
    }

    @Test fun changedSessionOrDepartedScreenWhileEitherPostIsOutCannotInstallResult() = runTest {
        for (leave in listOf(false, true)) for (logout in listOf(false, true)) {
            val (auth, client, state) = setup()
            state.load(); state.changeUsername("lanternkeeper"); if (leave) state.leaveTap()
            client.holdPost = true
            val request = async { if (leave) state.confirmLeave() else state.invite() }
            client.postEntered.await()
            val before = state.state.value
            if (logout) auth.logout() else state.close()
            client.postRelease.complete(Unit); request.await()
            assertEquals(before, state.state.value)
            assertEquals(1, client.posts.size); assertEquals(2, client.gets.size)
        }
    }

    @Test fun loadingFailureEmptySignedOutAndStaleInitialReads() = runTest {
        val (auth, client, state) = setup()
        client.holdGet = true
        val request = async { state.load() }
        client.getEntered.await()
        assertTrue(state.state.value.loading)
        auth.logout(); client.getRelease.complete(Unit); request.join()
        assertTrue(state.state.value.participants.isEmpty())
        assertFalse(state.state.value.loaded)
        val (_, otherClient, other) = setup()
        otherClient.getFailure = AO3Error.Forbidden; other.load()
        assertNotNull(other.state.value.loadError); assertFalse(other.state.value.loading)
        otherClient.getFailure = null; otherClient.html = "<ul class='participant index'></ul>"; other.load()
        assertTrue(other.state.value.loaded); assertTrue(other.state.value.participants.isEmpty())
        val signedOut = AO3CollectionMaintainersState("winter_exchange", AO3CollectionDetailRepository(client, auth), AO3WriteRepository(client))
        val count = client.gets.size
        signedOut.load(); signedOut.changeUsername("someone"); signedOut.invite(); signedOut.leaveTap(); signedOut.confirmLeave()
        assertEquals(count, client.gets.size); assertTrue(client.posts.isEmpty())
    }

    private suspend fun setup(username: String = "AO3_Reader"): Triple<AO3AuthRepository, MaintainersClient, AO3CollectionMaintainersState> {
        val auth = AO3AuthRepository(MemorySessionStore(testSession(username)), MemoryCookieStore())
        auth.restoreSession()
        val client = MaintainersClient(auth)
        return Triple(auth, client, AO3CollectionMaintainersState("winter_exchange", AO3CollectionDetailRepository(client, auth), AO3WriteRepository(client)))
    }
}

/** Real screen controls and dialog dispatch; every request still ends in the memory fake below. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2400dp")
class AO3CollectionMaintainersScreenTest {
    @get:Rule val compose = createComposeRule()
    private var left = 0

    @Test fun ownerDialogCancelMakesNoRequestAndConfirmedLeaveClosesOnce() {
        val client = show()
        compose.onNodeWithText("Winter Exchange 2026 · 4 people").assertIsDisplayed()
        compose.onNodeWithText("You · created the collection").assertIsDisplayed()
        compose.onNodeWithText("snowink").assertDoesNotExist() // iOS does not render pending invitations.
        compose.onNodeWithText("Step down as owner").performClick()
        compose.onNodeWithText("Step down as owner?").assertIsDisplayed()
        compose.onNodeWithText("You will relinquish owner privileges for Winter Exchange 2026. Another owner must maintain the collection.").assertIsDisplayed()
        compose.onNodeWithText("Cancel").performClick()
        compose.runOnIdle { assertEquals(1, client.gets.size); assertTrue(client.posts.isEmpty()) }
        compose.onNodeWithText("Step down as owner").performClick()
        compose.onNodeWithText("Step Down").performClick()
        compose.waitUntil(5_000) { left == 1 }
        compose.runOnIdle { assertEquals(1, client.posts.size); assertEquals(2, client.gets.size) }
    }

    @Test fun sepiaLargeTextRoleChoiceDoesNotInterceptSendAndDuplicateAo3RefusalIsSaidOnce() {
        val client = show(theme = KudosThemeMode.Sepia, scale = 2f)
        client.reply = maintainsResponse("<div class='flash error'>Unknown username.</div><div class='error'><p>Unknown username.</p></div>", 422)
        compose.onNodeWithContentDescription("Invite by username").performTextInput("unknown_username")
        compose.onNodeWithText("Invite as").performScrollTo().performClick()
        compose.onNodeWithText("Owner").performClick()
        compose.onNodeWithText("Send invitation to unknown_username").performScrollTo().performClick()
        compose.waitUntil(5_000) { client.posts.size == 1 }
        compose.onNodeWithText("Unknown username.").performScrollTo()
        compose.onAllNodesWithText("Unknown username.").assertCountEquals(1)
        compose.onNodeWithContentDescription("Invite by username").assertTextEquals("unknown_username")
        compose.runOnIdle {
            assertEquals(2, client.gets.size)
            assertEquals(setOf("authenticity_token", "participants_to_invite"), client.posts.single().fields.map { it.first }.toSet())
            assertEquals(0, left)
        }
    }

    @Test fun oledSoleOwnerAlertOkSendsNothing() {
        val client = show(theme = KudosThemeMode.Oled, onlyOwner = true)
        compose.onNodeWithText("Winter Exchange 2026 · 1 person").assertIsDisplayed()
        compose.onNodeWithText("Step down as owner").performClick()
        compose.onNodeWithText("Cannot Step Down").assertIsDisplayed()
        compose.onNodeWithText("You're the last owner. Appoint another owner before you step down.").assertIsDisplayed()
        compose.onNodeWithText("OK").performClick()
        compose.runOnIdle { assertEquals(1, client.gets.size); assertTrue(client.posts.isEmpty()); assertEquals(0, left) }
    }

    private fun show(theme: KudosThemeMode = KudosThemeMode.Light, scale: Float = 1f, onlyOwner: Boolean = false): MaintainersClient {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        runBlocking { auth.restoreSession() }
        val client = MaintainersClient(auth)
        if (onlyOwner) client.html = maintainersFixture("ao3_demo_maintainers_last_owner")
        val repository = AO3CollectionDetailRepository(client, auth, parseDispatcher = Dispatchers.Unconfined)
        val writes = AO3WriteRepository(client)
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, scale)) {
                KudosTheme(themeMode = theme) {
                    AO3CollectionMaintainersScreen("winter_exchange", "Winter Exchange 2026", repository, writes, onLeft = { ++left })
                }
            }
        }
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Step down as owner").fetchSemanticsNodes().isNotEmpty() }
        return client
    }
}

private fun maintainersFixture(name: String = "ao3_demo_moderation_participants") = listOf(
    "src/debug/assets/fixtures", "app/src/debug/assets/fixtures", "android/app/src/debug/assets/fixtures"
).map { File(it, "$name.html") }.first { it.isFile }.readText()

private fun maintainsResponse(html: String, status: Int = 200): AO3Result<AO3HttpResponse> = AO3Result.Success(
    AO3HttpResponse(AO3CollectionParticipantsUrls.page("winter_exchange"), status, emptyMap(), html))

private data class MaintainerPost(val url: String, val fields: List<Pair<String, String>>, val headers: Map<String, String>, val generation: Int?)

/** Memory-only transport; no OkHttp connection or socket can be constructed by this fake. */
private class MaintainersClient(private val auth: AO3AuthRepository) : AO3Client, AO3AuthenticatedClient {
    var html = maintainersFixture()
    var showHtml = maintainersFixture("ao3_demo_moderation_show")
    val gets = mutableListOf<String>()
    val readHeaders = mutableListOf<Map<String, String>>()
    val posts = mutableListOf<MaintainerPost>()
    var getFailure: AO3Error? = null
    var reply = maintainsResponse("<div class='flash notice'>Done.</div>")
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
        gets += url; readHeaders += headers
        if (holdGet) { getEntered.complete(Unit); getRelease.await() }
        getFailure?.let { return AO3Result.Failure(it) }
        return maintainsResponse(if (url.endsWith("/participants")) html else showHtml)
    }
    override suspend fun postAuthenticatedInSession(url: String, formFields: List<Pair<String, String>>,
        headers: Map<String, String>, generation: Int?): AO3Result<AO3HttpResponse> {
        if (generation != sessionGeneration()) throw kotlinx.coroutines.CancellationException()
        posts += MaintainerPost(url, formFields, headers, generation)
        if (holdPost) { postEntered.complete(Unit); postRelease.await() }
        return reply
    }
    override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>) =
        error("Write bypassed the generation-fenced path")
}
