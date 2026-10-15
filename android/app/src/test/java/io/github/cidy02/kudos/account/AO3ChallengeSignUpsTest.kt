package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.account.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AO3ChallengeSignUpsTest {
    private val parser = AO3ChallengeSignUpsParser()

    @Test fun assignmentJoinFetchesEveryPageIncludingOpenAssignments() = runTest {
        val (_, client, repo) = signUpsSetup()
        val expected = mutableListOf<String>()
        for (list in listOf(SignUpAssignmentList.Complete, SignUpAssignmentList.Open, SignUpAssignmentList.Defaults)) {
            val totalPages = if (list == SignUpAssignmentList.Open) 3 else 2
            for (page in 1..totalPages) {
                val url = AO3ChallengeSignUpsUrls.assignments("winter_exchange", list, page)
                expected += url
                // Only the last Open page contains this visible sign-up's recipient.
                val recipient = if (list == SignUpAssignmentList.Open && page == 3) 4 else 200 + page
                val html = """<h2 class="heading">Assignments</h2>
                    <dl class="index"><dt>Giver<span> for <a href="/collections/winter_exchange/signups/$recipient">Recipient</a></span></dt>
                    <dd><input name="default_$page" type="checkbox"></dd></dl>
                    <ol class="pagination"><li>$totalPages</li></ol>"""
                client.replies[url] = challengeResponse(url, html)
            }
        }
        val model = AO3ChallengeSignUpsState("winter_exchange", true, true, repo)
        model.load()
        assertEquals(listOf(signUpsSettings) + expected + listOf(signUpsFirst, signUpsLast), client.gets)
        assertEquals(7, model.state.value.assignments?.size)
        val openThird = expected[4].toHttpUrl()
        assertEquals("true", openThird.queryParameter("unfulfilled"))
        assertEquals("3", openThird.queryParameter("page"))
        assertEquals(SignUpMatch.Matched, signUpMatch(model.state.value.rows.first(), model.state.value.assignments))
        assertEquals(0, client.posts)
    }

    @Test fun aFailedLaterAssignmentPageStopsTheJoinAndNeverPublishesPartialUnmatched() = runTest {
        for (failedIndex in listOf(1, 3, 5)) for (malformed in listOf(false, true)) {
            val (_, client, repo) = signUpsSetup()
            val failed = signUpsAssignmentReads[failedIndex]
            client.replies[failed] = if (malformed) challengeResponse(failed, "<h2 class=heading>Assignments</h2>")
                else AO3Result.Failure(AO3Error.Forbidden)
            val model = AO3ChallengeSignUpsState("winter_exchange", true, true, repo)
            model.load()
            assertEquals(listOf(signUpsSettings) + signUpsAssignmentReads.take(failedIndex + 1) +
                listOf(signUpsFirst, signUpsLast), client.gets)
            assertEquals(4, model.state.value.rows.size)
            assertNull(model.state.value.assignments)
            assertNotNull(model.state.value.matchError)
            assertTrue(model.state.value.matchNote!!.contains(model.state.value.matchError!!))
            assertTrue(model.state.value.rows.all { signUpMatch(it, model.state.value.assignments) == SignUpMatch.Unknown })
            assertTrue(model.state.value.filtered(SignUpFilter.Unmatched).isEmpty())
            assertEquals(0, client.posts)
        }
    }

    @Test fun closingOrReplacingTheSessionDuringALaterAssignmentPageStopsAllFurtherReads() = runTest {
        for (close in listOf(true, false)) {
            val (auth, client, repo) = signUpsSetup()
            val entered = CompletableDeferred<Unit>()
            val release = CompletableDeferred<Unit>()
            val later = signUpsAssignmentReads[1]
            client.afterGet = { url -> if (url == later) { entered.complete(Unit); release.await() } }
            val model = AO3ChallengeSignUpsState("winter_exchange", true, true, repo)
            val task = async { model.load() }
            entered.await()
            assertNull(model.state.value.assignments)
            if (close) model.close() else auth.logout()
            release.complete(Unit)
            assertTrue(runCatching { task.await() }.isFailure)
            assertEquals(listOf(signUpsSettings) + signUpsAssignmentReads.take(2), client.gets)
            assertNull(model.state.value.assignments)
            assertTrue(model.state.value.rows.isEmpty())
            model.load(refresh = true)
            assertEquals(3, client.gets.size)
            assertEquals(0, client.posts)
        }
    }

    @Test fun bothPagesAndEveryAssignmentFixtureHaveIosTagsBylinesAnyOptionalTextAndMatchStates() {
        val first = parser.parse(challengeFixture("ao3_demo_winter_signups_1"))
        val second = parser.parse(challengeFixture("ao3_demo_winter_signups_2"), 2)
        assertEquals(listOf(4, 5, 6, 7), first.rows.map { it.id })
        assertEquals(listOf(8, 9), second.rows.map { it.id })
        assertEquals(2, first.totalPages)
        val prompt = first.rows[0].requests.single()
        assertEquals(listOf("Cloudbound Courier", "The Lantern Pier"), prompt.tags[SignUpTagType.Fandom])
        assertEquals(listOf("Mira/Sol"), prompt.tags[SignUpTagType.Relationship])
        assertEquals(setOf(SignUpTagType.Character), prompt.any)
        assertEquals(listOf("A Lamp in the Window"), prompt.optionalTags)
        assertTrue(prompt.text.contains("floating lantern"))
        assertEquals("Cloudbound Courier, The Lantern Pier", first.rows[0].requestTagSummary)
        assertEquals("1 request · 1 offer", signUpPromptCount(first.rows[0]))
        val assignments = signUpAssignmentFixtures.flatMap { parser.parseAssignments(challengeFixture(it)) }
        assertEquals(listOf(SignUpMatch.Matched, SignUpMatch.Unmatched, SignUpMatch.Matched, SignUpMatch.Unmatched),
            first.rows.map { signUpMatch(it, assignments) })
        assertEquals(listOf(SignUpMatch.Matched, SignUpMatch.Unmatched), second.rows.map { signUpMatch(it, assignments) })
        assertEquals(4, ownListedSignUpID(first.rows, " ao3_reader "))
        assertEquals(5, ownListedSignUpID(first.rows.drop(1), "AO3_Reader"))
        assertNull(ownListedSignUpID(first.rows, ""))
        assertEquals(SignUpMatch.Unknown, signUpMatch(first.rows.first(), null))
        assertEquals(SignUpMatch.Unknown, signUpMatch(first.rows.first(), emptyList()))
        val original = parser.parse(challengeFixture("ao3_challenge_signups"))
        assertEquals("Good Omens (TV), Naruto", original.rows.first().requestTagSummary)
        assertEquals("Any Fandom", original.rows[1].requestTagSummary)
        assertEquals(4, parser.parseAssignments(challengeFixture("ao3_challenge_assignments")).size)
    }

    @Test fun emptyRecognizedPagesAndMalformedParticipantsOrAssignmentsFollowSwift() {
        assertTrue(parser.parse("<h2 class='heading'>Sign-ups</h2><dl class='index'></dl>").rows.isEmpty())
        assertTrue(parser.parseAssignments("<h2 class='heading'>Assignments</h2><p class='note'>No assignments</p>").isEmpty())
        for (html in listOf("<form>Login</form>", "<dl class='index'><dt class='participant'>Missing link</dt><dd></dd></dl>",
            "<dl class='index'><dt class='participant'><a href='/signups/4'>AO3_Reader</a></dt></dl>")) {
            assertThrows(Exception::class.java) { parser.parse(html) }
        }
        assertThrows(Exception::class.java) { parser.parseAssignments("<h2 class='heading'>Assignments</h2>") }
        val row = parser.parse(challengeFixture("ao3_demo_winter_signups_1")).rows.first()
        assertEquals(SignUpMatch.Unmatched, signUpMatch(row, listOf(
            AO3SignUpAssignment(4, "wrong pseud", "giver", false), AO3SignUpAssignment(4, "AO3_Reader", "giver", true))))
        assertEquals(SignUpMatch.Matched, signUpMatch(row, listOf(AO3SignUpAssignment(null, "ao3_READER", "giver", false))))
    }

    @Test fun openingOwnerModeratorNeitherAndSignedOutCountsEveryReadAndDoesNotWrite() = runTest {
        for ((owner, maintainer, signedIn) in listOf(Triple(true, true, true), Triple(false, true, true),
            Triple(false, false, true), Triple(true, true, false))) {
            val (_, client, repo) = signUpsSetup(signedIn)
            val model = AO3ChallengeSignUpsState("winter_exchange", owner, maintainer, repo)
            model.load(); model.load()
            val expected = if (!signedIn || !maintainer) emptyList() else if (owner) signUpsOpeningReads else listOf(signUpsFirst, signUpsLast)
            assertEquals(expected, client.gets)
            assertEquals(0, client.posts)
            assertFalse(model.state.value.loading)
            if (signedIn && maintainer) {
                assertEquals(6, model.state.value.total)
                assertEquals(4, model.state.value.rows.size)
                assertEquals(if (owner) "closed" else "", model.state.value.closeDateText)
                assertEquals(if (owner) SignUpMatch.Matched else SignUpMatch.Unknown,
                    signUpMatch(model.state.value.rows.first(), model.state.value.assignments))
            } else assertTrue(model.state.value.terminal)
        }
    }

    @Test fun openOwnerNeverReadsRefusedAssignmentsAndModeratorNeverReadsOwnerForm() = runTest {
        val (_, client, repo) = signUpsSetup()
        client.replies[signUpsSettings] = challengeResponse(signUpsSettings, challengeFixture("ao3_challenge_settings"))
        val model = AO3ChallengeSignUpsState("winter_exchange", true, true, repo)
        model.load()
        assertEquals(listOf(signUpsSettings, signUpsFirst, signUpsLast), client.gets)
        assertTrue(model.state.value.closeDateText.startsWith("open until "))
        assertNull(model.state.value.assignments)
    }

    @Test fun optionalFailuresAreRememberedRowsSurviveAndMoreReadsJustOnePage() = runTest {
        for (failed in listOf(signUpsSettings, signUpsAssignmentReads[0], signUpsAssignmentReads[2], signUpsLast)) {
            val (_, client, repo) = signUpsSetup()
            client.replies[failed] = AO3Result.Failure(AO3Error.Forbidden)
            val model = AO3ChallengeSignUpsState("winter_exchange", true, true, repo)
            model.load(); model.load()
            assertEquals(1, client.gets.count { it == failed })
            assertEquals(4, model.state.value.rows.size)
            assertNull(model.state.value.failure)
            assertFalse(model.state.value.loading)
            if (failed == signUpsLast) assertNull(model.state.value.total) else assertNull(model.state.value.assignments)
            client.replies[signUpsLast] = challengeResponse(signUpsLast, challengeFixture("ao3_demo_winter_signups_2"))
            val previous = client.gets.toList()
            model.load(more = true)
            assertEquals(previous + signUpsLast, client.gets)
            assertEquals(6, model.state.value.rows.size)
            assertFalse(model.state.value.hasMore)
            assertEquals(0, client.posts)
        }
    }

    @Test fun failedRefreshOrMoreLeavesPagesAndTotalIntactAndFiltersUseAllCollectedPages() = runTest {
        val (_, client, repo) = signUpsSetup()
        val model = AO3ChallengeSignUpsState("winter_exchange", true, true, repo)
        model.load()
        val original = model.state.value
        assertEquals(listOf(4, 6), original.filtered(SignUpFilter.Matched).map { it.id })
        assertEquals(listOf(5, 7), original.filtered(SignUpFilter.Unmatched).map { it.id })
        client.replies[signUpsLast] = AO3Result.Failure(AO3Error.NotFound)
        model.load(more = true)
        assertEquals(original.rows, model.state.value.rows)
        assertEquals(1, model.state.value.loadedPages)
        assertEquals(6, model.state.value.total)
        assertNotNull(model.state.value.failure)
        client.replies[signUpsFirst] = AO3Result.Failure(AO3Error.NotFound)
        model.load(refresh = true)
        assertEquals(original.rows, model.state.value.rows)
        assertEquals(original.total, model.state.value.total)
        assertEquals(0, client.posts)
        assertFalse(model.state.value.loading)
    }

    @Test fun emptyAssignmentsUnknownFilteredEmptyAndDuplicateOrRetiredLoadsDoNotRead() = runTest {
        val (_, client, repo) = signUpsSetup()
        signUpsAssignmentReads.forEach { client.replies[it] = challengeResponse(it,
            "<h2 class='heading'>Assignments</h2><p class='note'>No assignments</p>") }
        val model = AO3ChallengeSignUpsState("winter_exchange", true, true, repo)
        model.load()
        assertEquals("No assignments have been sent yet, so no sign-up is matched or unmatched.", model.state.value.matchNote)
        assertTrue(model.state.value.filtered(SignUpFilter.Matched).isEmpty())
        val (auth, held, heldRepo) = signUpsSetup()
        held.hold = true
        val pending = AO3ChallengeSignUpsState("winter_exchange", true, true, heldRepo)
        val task = async { pending.load() }
        runCurrent()
        assertTrue(pending.state.value.loading)
        pending.load(); pending.load(refresh = true)
        assertEquals(listOf(signUpsSettings), held.gets)
        auth.logout(); held.release.complete(Unit)
        runCatching { task.await() }
        assertNull(pending.state.value.total)
        assertTrue(pending.state.value.rows.isEmpty())
        assertFalse(pending.state.value.loading)
        pending.load(refresh = true)
        assertEquals(listOf(signUpsSettings), held.gets)
        model.close(); val before = client.gets.toList(); model.load(refresh = true)
        assertEquals(before, client.gets)
    }
}

internal val signUpAssignmentFixtures = listOf("ao3_demo_winter_assignments_complete", "ao3_demo_winter_assignments_open", "ao3_demo_winter_assignments_defaults")
internal val signUpsSettings = ChallengeSettingsDestinations.challengeSettingsEditView("winter_exchange", AO3ChallengeKind.GiftExchange)
internal val signUpsFirst = AO3ChallengeSignUpsUrls.page("winter_exchange")
internal val signUpsLast = AO3ChallengeSignUpsUrls.page("winter_exchange", 2)
internal val signUpsAssignmentReads = listOf(SignUpAssignmentList.Complete, SignUpAssignmentList.Open, SignUpAssignmentList.Defaults)
    .flatMap { list -> (1..2).map { AO3ChallengeSignUpsUrls.assignments("winter_exchange", list, it) } }
internal val signUpsOpeningReads = listOf(signUpsSettings) + signUpsAssignmentReads + listOf(signUpsFirst, signUpsLast)
internal suspend fun signUpsSetup(signedIn: Boolean = true) = promptMemeSetup(signedIn).also { (_, client, _) ->
    client.replies[signUpsSettings] = challengeResponse(signUpsSettings, challengeFixture("ao3_demo_winter_settings"))
    client.replies[signUpsFirst] = challengeResponse(signUpsFirst, challengeFixture("ao3_demo_winter_signups_1"))
    client.replies[signUpsLast] = challengeResponse(signUpsLast, challengeFixture("ao3_demo_winter_signups_2"))
    val fixtures = signUpAssignmentFixtures.flatMap { listOf(it, "${it}_2") }
    signUpsAssignmentReads.zip(fixtures).forEach { (url, fixture) -> client.replies[url] = challengeResponse(url, challengeFixture(fixture)) }
}
