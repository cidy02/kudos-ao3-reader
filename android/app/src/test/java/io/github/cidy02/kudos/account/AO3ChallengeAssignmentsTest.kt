package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.account.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

@OptIn(ExperimentalCoroutinesApi::class)
class AO3ChallengeAssignmentsTest {
    @Test fun sharedParserReadsEveryFixtureAllStatesIdsPaginationAndDoesNotInventSentDates() {
        val parser = AO3ChallengeSignUpsParser()
        for (list in SignUpAssignmentList.entries) for (page in 1..2) {
            val parsed = parser.parseAssignmentPage(challengeFixture(assignmentFixture(list, page)), list, page)
            assertEquals(page, parsed.currentPage); assertEquals(2, parsed.totalPages)
            assertTrue(parsed.rows.all { it.id > 0 })
        }
        val complete = parser.parseAssignments(challengeFixture(assignmentFixture(SignUpAssignmentList.Complete)), SignUpAssignmentList.Complete).single()
        assertEquals(81, complete.id); assertNull(complete.requestID); assertEquals("AO3_Reader", complete.recipient)
        assertEquals("DELIVERED", complete.badge(null))
        val open = parser.parseAssignments(challengeFixture(assignmentFixture(SignUpAssignmentList.Open)), SignUpAssignmentList.Open)
        assertEquals("Replacement", open.first().pinchHitter)
        assertNull(open[1].badge(null))
        assertEquals("LATE", open[1].badge(Instant.EPOCH, Instant.parse("2026-10-09T00:00:00Z")))
        assertEquals("DEFAULTED", open.last().badge(Instant.EPOCH))
        val defaults = parser.parseAssignments(challengeFixture(assignmentFixture(SignUpAssignmentList.Defaults)))
        assertEquals(listOf(82, 85, 88), defaults.map { it.id })
        assertEquals("FormerGiver", defaults.first().giver)
        val empty = "<h2 class='heading'>Assignments</h2><p class='note'>No assignments</p>"
        assertTrue(parser.parseAssignmentPage(empty, SignUpAssignmentList.Defaults).rows.isEmpty())
        for (html in listOf("<form>Login</form>", "<dl class='index'><dt>giver</dt><dd>Missing id</dd></dl>"))
            assertThrows(Exception::class.java) { parser.parseAssignments(html) }
        assertEquals("An anonymous sign-up", complete.copy(recipient = "").recipientDisplay)
        assertEquals("Unclaimed", complete.copy(giver = "").giverDisplay)
    }

    @Test fun dueDateUsesServedTimezoneUnknownRailsZoneNeverInventsLateAndMissingDueHasNoBadge() {
        val raw = "2026-03-01 00:00:00"
        assertEquals(Instant.parse("2026-03-01T05:00:00Z"), ChallengeAssignmentsUiState(dueRaw = raw, dueZone = "America/New_York").dueInstant)
        assertNull(ChallengeAssignmentsUiState(dueRaw = raw, dueZone = "Eastern Time (US & Canada)").dueInstant)
        assertNull(ChallengeAssignmentsUiState().dueInstant)
        assertNull(ChallengeAssignmentsUiState().dueText)
        val parsed = AO3ChallengeSettingsParser().parseSettings(challengeFixture("ao3_demo_winter_settings"), AO3ChallengeKind.GiftExchange)
        assertEquals("UTC", parsed.timeZoneName)
    }

    @Test fun ownerModeratorNeitherSignedOutAndUnknownClosureCountEveryOpeningReadNoWrites() = runTest {
        for (case in listOf(Triple(true, true, true), Triple(false, true, true), Triple(false, false, true), Triple(true, true, false))) {
            val (auth, client, repo) = assignmentsSetup(case.third)
            val model = AO3ChallengeAssignmentsState("winter_exchange", case.first, case.second, true, repo, promptMemeWrites(client, auth))
            model.load(); model.load()
            assertEquals(if (!case.third || !case.second) emptyList() else assignmentReads + if (case.first) listOf(signUpsSettings) else emptyList(), client.gets)
            assertEquals(0, client.posts); assertFalse(model.state.value.loading)
            if (!case.third) assertEquals("Sign in to AO3 to view assignments.", model.state.value.failure)
            if (case.third && case.second) {
                assertEquals(5, model.state.value.matched.size)
                assertEquals(3, model.state.value.unmatched.size)
                assertEquals(if (case.first) "Mar 1, 2026" else null, model.state.value.dueText?.let { challengeDateText(model.state.value.dueRaw, java.util.Locale.US) })
            }
        }
        for (owner in listOf(false, true)) {
            val (auth, client, repo) = assignmentsSetup()
            val model = AO3ChallengeAssignmentsState("winter_exchange", owner, true, null, repo, promptMemeWrites(client, auth))
            model.load()
            // A moderator is not served the settings form, so cannot be told whether sign-ups are closed:
            // the lists are asked for, as on iOS. (The first version turned every moderator away.)
            assertEquals(if (owner) listOf(signUpsSettings) + assignmentReads else assignmentReads, client.gets)
            assertEquals(true, model.state.value.loaded)
        }
    }

    /** AO3 serves the four lists to the same people: its first refusal is the answer for all of them. */
    @Test fun aRefusedListStopsTheOthersAndAFailedOneDoesNot() = runTest {
        for (refused in listOf(true, false)) {
            val (auth, client, repo) = assignmentsSetup()
            client.replies[assignmentUrl(SignUpAssignmentList.Complete)] =
                AO3Result.Failure(if (refused) AO3Error.Forbidden else AO3Error.Server(503))
            val model = AO3ChallengeAssignmentsState("winter_exchange", false, true, null, repo, promptMemeWrites(client, auth))
            model.load()
            assertEquals(if (refused) listOf(assignmentReads[0]) else listOf(assignmentReads[0], assignmentReads[2], assignmentReads[3]), client.gets)
            assertEquals(if (refused) SignUpAssignmentList.entries.toSet() else emptySet<SignUpAssignmentList>(), model.state.value.blocked)
            assertEquals(if (refused) 4 else 1, model.state.value.errors.size)
            model.load(refresh = true)
            if (refused) assertEquals(1, client.gets.size)
        }
    }

    @Test fun knownOpenAndFailedAdmissionNeverProbeAssignmentsDueAttemptDoesNotRepeat() = runTest {
        for (failure in listOf(false, true)) {
            val (auth, client, repo) = assignmentsSetup()
            client.replies[signUpsSettings] = if (failure) AO3Result.Failure(AO3Error.Forbidden)
                else challengeResponse(signUpsSettings, challengeFixture("ao3_challenge_settings"))
            val model = AO3ChallengeAssignmentsState("winter_exchange", true, true, null, repo, promptMemeWrites(client, auth))
            model.load(); model.load(refresh = true)
            assertEquals(listOf(signUpsSettings), client.gets)
            assertTrue(model.state.value.terminal); assertFalse(model.state.value.loading); assertEquals(0, client.posts)
        }
        val (auth, client, repo) = assignmentsSetup()
        val model = AO3ChallengeAssignmentsState("winter_exchange", true, true, false, repo, promptMemeWrites(client, auth))
        model.load(); assertTrue(client.gets.isEmpty())
    }

    @Test fun oneFailingListLeavesOthersAndOptionalFailureIsRememberedAndLoadMoreIsOnlyOnRequest() = runTest {
        for (failed in assignmentReads + signUpsSettings) {
            val (auth, client, repo) = assignmentsSetup()
            client.replies[failed] = AO3Result.Failure(AO3Error.NotFound)
            // Suppress the iOS 404 -> meme fallback, too.
            client.replies[ChallengeSettingsDestinations.challengeSettingsEditView("winter_exchange", AO3ChallengeKind.PromptMeme)] = AO3Result.Failure(AO3Error.Forbidden)
            val model = AO3ChallengeAssignmentsState("winter_exchange", true, true, true, repo, promptMemeWrites(client, auth))
            model.load(); model.load()
            assertTrue(model.state.value.loaded); assertFalse(model.state.value.loading)
            assertTrue(model.state.value.pages.isNotEmpty())
            assertEquals(1, client.gets.count { it == failed })
            val before = client.gets.size
            model.load(more = SignUpAssignmentList.PinchHits)
            if (failed != assignmentReads.last()) {
                assertEquals(listOf(assignmentUrl(SignUpAssignmentList.PinchHits, 2)), client.gets.drop(before))
                assertEquals(2, model.state.value.claimed.size)
            }
            model.load(refresh = true)
            assertEquals(if (failed == signUpsSettings) 1 else 2, client.gets.count { it == signUpsSettings })
            assertEquals(0, client.posts)
        }
    }

    @Test fun failingDueRefreshStopsFurtherOptionalAttemptsAndDoesNotClaimLateFromAnOldDate() = runTest {
        val (auth, client, repo) = assignmentsSetup()
        val model = AO3ChallengeAssignmentsState("winter_exchange", true, true, true, repo, promptMemeWrites(client, auth))
        model.load(); assertNotNull(model.state.value.dueInstant)
        client.replies[signUpsSettings] = AO3Result.Failure(AO3Error.Forbidden)
        model.load(refresh = true); model.load(refresh = true)
        assertEquals(2, client.gets.count { it == signUpsSettings })
        assertNull(model.state.value.dueInstant); assertNull(model.state.value.dueText)
        assertTrue(model.state.value.matched.isNotEmpty()); assertEquals(0, client.posts)
        assertFalse(model.state.value.loading)
    }

    @Test fun refreshPreservesConfirmationTargetAndCandidateSelectionNoWrites() = runTest {
        val (auth, client, repo) = assignmentsSetup()
        val model = AO3ChallengeAssignmentsState("winter_exchange", true, true, true, repo, promptMemeWrites(client, auth))
        model.load()
        model.select(AssignmentWrite.Claim, model.state.value.unmatched.first())
        val pending = model.state.value.pending
        assertEquals("Claim this pinch hit?", pending!!.kind.confirmTitle)
        assertTrue(model.state.value.confirmation(pending).startsWith("You'll be the pinch hitter for Harbor (AO3_Reader)'s gift, due "))
        model.load(refresh = true)
        assertEquals(pending, model.state.value.pending)
        model.cancel(); model.pick(AssignmentWrite.Default)
        assertEquals(listOf(83, 84, 86), model.state.value.candidates(AssignmentWrite.Default).map { it.id })
        assertEquals(0, client.posts)
    }

    @Test fun generationChangeAndDepartureRetireReadAndClearActiveLoading() = runTest {
        val (auth, client, repo) = assignmentsSetup()
        val model = AO3ChallengeAssignmentsState("winter_exchange", true, true, true, repo, promptMemeWrites(client, auth))
        client.hold = true
        val task = async { model.load() }; runCurrent()
        auth.logout(); client.release.complete(Unit); runCatching { task.await() }
        assertTrue(model.state.value.pages.isEmpty()); assertFalse(model.state.value.loading)
        assertEquals(1, client.gets.size); model.load(refresh = true); assertEquals(1, client.gets.size)
        model.close(); assertEquals(0, client.posts)
    }
}
internal fun assignmentUrl(list: SignUpAssignmentList, page: Int = 1) = AO3ChallengeSignUpsUrls.assignments("winter_exchange", list, page)
internal val assignmentReads = SignUpAssignmentList.entries.map { assignmentUrl(it) }
internal fun assignmentFixture(list: SignUpAssignmentList, page: Int = 1) = "ao3_demo_winter_assignments_" + when (list) {
    SignUpAssignmentList.Complete -> "complete"
    SignUpAssignmentList.Open -> "open"
    SignUpAssignmentList.Defaults -> "defaults"
    SignUpAssignmentList.PinchHits -> "pinch_hits"
} + if (page == 2) "_2" else ""
internal suspend fun assignmentsSetup(signedIn: Boolean = true) = signUpsSetup(signedIn).also { (_, client, _) ->
    for (list in SignUpAssignmentList.entries) for (page in 1..2) {
        val url = assignmentUrl(list, page)
        client.replies[url] = challengeResponse(url, challengeFixture(assignmentFixture(list, page)))
    }
}
