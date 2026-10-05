package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.app.Routes
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3FormPostClient
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3AccountParseException
import io.github.cidy02.kudos.network.ao3.writing.AO3DraftsPage
import io.github.cidy02.kudos.network.ao3.writing.AO3DraftsParser
import io.github.cidy02.kudos.network.ao3.writing.AO3DraftsUrls
import io.github.cidy02.kudos.network.ao3.writing.DraftExpiry
import io.github.cidy02.kudos.network.ao3.writes.DefaultAO3AuthenticatedClient
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset

class WritingDraftsTest {
    private val parser = AO3DraftsParser()
    private val clock = Clock.fixed(Instant.parse("2026-10-05T12:00:00Z"), ZoneOffset.UTC)

    @Test fun fixtureParsesBlurbsAndNoticeOnlyIncludingTheMissingNotice() {
        val first = parser.parse(draftsFixture(1), 1)
        val second = parser.parse(draftsFixture(2), 2)
        assertEquals(listOf(995001L, 995002L, 995003L), first.page.works.map { it.id })
        assertEquals(listOf(995004L, 995005L), second.page.works.map { it.id })
        assertEquals(2, first.page.totalPages); assertEquals(2, second.page.currentPage)
        assertEquals(listOf(29, 7), first.deletionDates.values.map { DraftExpiry.daysLeft(it, clock) })
        assertEquals(listOf(1, 0), second.deletionDates.values.map { DraftExpiry.daysLeft(it, clock) })
        assertNull(first.deletionDates[995003L])
        val work = first.page.works.first()
        assertEquals("Lanterns Above the Mill", work.title)
        assertEquals(listOf("Original Work"), work.fandoms)
        assertEquals("General Audiences", work.rating)
        assertEquals(listOf("Gen"), work.categories)
        assertEquals(listOf("No Archive Warnings Apply"), work.warnings)
        assertEquals(false, work.isComplete)
        assertEquals(2400, work.wordCount)
        assertTrue(work.summary.isNotEmpty())
        assertEquals("01 Jan 2001", work.updatedDate) // Deliberately unrelated to expiry.
        assertEquals(LocalDate.of(2026, 10, 5), DraftExpiry.createdDate(first.deletionDates.getValue(work.id)))
    }

    @Test fun unreadableNoticeDoesNotGuessFromTheRevisedDate() {
        val dates = parser.parseDraftDeletionDates(draftsFixture(1).replace("title=\"November\"", "title=\"Unreadable\""))
        assertFalse(dates.containsKey(995001L)); assertFalse(dates.containsKey(995003L))
        assertTrue(dates.containsKey(995002L))
    }

    @Test fun allMalformedBlurbsAreFailureWhileAMalformedNeighborDoesNotLoseValidDrafts() {
        val broken = "<li class='work blurb'>Unrecognized work markup</li>"
        assertThrows(AO3AccountParseException.MissingRequiredStructure::class.java) { parser.parse("<ol>$broken</ol>", 1) }
        assertEquals(3, parser.parse(draftsFixture(1).replace("</ol>", "$broken</ol>"), 1).page.works.size)
        assertTrue(parser.parse("<ol class='work index'></ol>", 1).page.works.isEmpty())
    }

    @Test fun expiryWordsAndTonesAtEveryBoundaryNeverBecomeNegative() {
        val today = LocalDate.now(clock)
        for ((offset, tone) in listOf(29 to DraftExpiry.Tone.Mint, 8 to DraftExpiry.Tone.Mint,
            7 to DraftExpiry.Tone.Orange, 4 to DraftExpiry.Tone.Orange, 3 to DraftExpiry.Tone.Red,
            1 to DraftExpiry.Tone.Red, 0 to DraftExpiry.Tone.Red, -1 to DraftExpiry.Tone.Red)) {
            val days = DraftExpiry.daysLeft(today.plusDays(offset.toLong()), clock)
            assertEquals(offset.coerceAtLeast(0), days)
            assertEquals(tone, DraftExpiry.tone(days))
        }
        assertEquals("29 days left", DraftExpiry.chipText(29))
        assertEquals("7 days left", DraftExpiry.chipText(7))
        assertEquals("1 day left", DraftExpiry.chipText(1))
        assertEquals("Last day", DraftExpiry.chipText(0))
    }

    @Test fun midnightChangesTheCountdownAndTallyWithTheClockInTheLocalZone() {
        val zone = ZoneId.of("America/New_York")
        val before = Clock.fixed(Instant.parse("2026-03-08T04:59:59Z"), zone)
        val after = Clock.fixed(Instant.parse("2026-03-08T05:00:00Z"), zone)
        val expiry = LocalDate.of(2026, 3, 15)
        assertEquals(8, DraftExpiry.daysLeft(expiry, before))
        assertEquals(7, DraftExpiry.daysLeft(expiry, after))
        val first = parser.parse(draftsFixture(1), 1)
        val draft = first.copy(page = first.page.copy(works = first.page.works.take(1), totalPages = 1),
            deletionDates = mapOf(995001L to expiry))
        assertEquals("1 draft", DraftExpiry.tally(draft, before))
        assertEquals("1 draft · 1 expiring this week", DraftExpiry.tally(draft, after))
        val lastDay = Clock.fixed(Instant.parse("2026-10-06T04:00:00Z"), zone)
        assertEquals("Last day", DraftExpiry.chipText(DraftExpiry.daysLeft(LocalDate.of(2026, 10, 6), lastDay)))
    }

    @Test fun tallyHasEverySinglePageAndPagedCaseAndExcludesUnknownDates() {
        val first = parser.parse(draftsFixture(1), 1)
        fun tally(works: Int, deletions: Map<Long, LocalDate>, pages: Int = 1): String =
            DraftExpiry.tally(AO3DraftsPage(first.page.copy(works = first.page.works.take(works), totalPages = pages), deletions), clock)
        assertEquals("0 drafts", tally(0, emptyMap()))
        assertEquals("1 draft", tally(1, emptyMap()))
        assertEquals("3 drafts", tally(3, emptyMap()))
        assertEquals("3 drafts · 1 expiring this week", tally(3, first.deletionDates))
        assertEquals("1 draft · 1 expiring this week", tally(1, mapOf(995001L to LocalDate.now(clock))))
        assertEquals("page 1 of 2", tally(3, emptyMap(), 2))
        assertEquals("page 1 of 2 · 1 expiring this week on this page", DraftExpiry.tally(first, clock))
        assertEquals("page 2 of 2 · 2 expiring this week on this page", DraftExpiry.tally(parser.parse(draftsFixture(2), 2), clock))
    }

    @Test fun urlsMatchIosAndBothEditorFallbacksStayTogether() {
        assertEquals("/users/AO3_Reader/works/drafts", AO3DraftsUrls.page(" AO3_Reader ", 1)!!.toHttpUrl().encodedPath)
        assertNull(AO3DraftsUrls.page("AO3_Reader", 1)!!.toHttpUrl().query)
        assertEquals("2", AO3DraftsUrls.page("AO3_Reader", 2)!!.toHttpUrl().queryParameter("page"))
        assertEquals("/users/a%2Fb/works/drafts", AO3DraftsUrls.page("a/b", 1)!!.toHttpUrl().encodedPath)
        assertNull(AO3DraftsUrls.page(" ", 1))
        assertEquals("https://archiveofourown.org/works/995001/edit", WritingWorkDestination.url(995001L))
        assertEquals("https://archiveofourown.org/works/new", WritingWorkDestination.url())
        assertEquals("Drafts", Routes.titleFor(Routes.WritingDrafts))
        assertTrue(Routes.hasSubjectHeader(Routes.WritingDrafts)); assertTrue(Routes.hidesTabBar(Routes.WritingDrafts))
        assertFalse(Routes.isShellRoot(Routes.WritingDrafts))
    }

    @Test fun eachOpeningPageTurnAndRefreshReadsOneIndexWithCookiesAndNoEnrichment() = runTest {
        val (auth, client, repository) = draftsSetup()
        WritingDraftsState(repository, 1).load()
        val second = WritingDraftsState(repository, 2)
        second.load(); second.load() // Explicit refresh on this page.
        WritingDraftsState(repository, 1).load() // New opening.
        assertEquals(listOf(AO3DraftsUrls.page("AO3_Reader", 1), AO3DraftsUrls.page("AO3_Reader", 2),
            AO3DraftsUrls.page("AO3_Reader", 2), AO3DraftsUrls.page("AO3_Reader", 1)), client.gets)
        assertTrue(client.headers.all { it["Cookie"]?.contains("_otwarchive_session=secret") == true })
        assertEquals(AO3AuthState.SignedIn("AO3_Reader"), auth.state.value)
    }

    @Test fun signedOutAndSignedOutRefreshReadNothingAndKeepIosWords() = runTest {
        val (_, client, repository) = draftsSetup(signedIn = false)
        val state = WritingDraftsState(repository, 1)
        state.load(); state.load()
        assertTrue(client.gets.isEmpty())
        assertEquals("Log in to AO3 first.", state.state.value.error)
        assertNull(state.state.value.drafts)
    }

    @Test fun duplicateLoadIsIgnoredOldRowsClearAndRetryIsExplicit() = runTest {
        val (_, client, repository) = draftsSetup()
        val state = WritingDraftsState(repository, 1)
        state.load()
        val release = CompletableDeferred<Unit>()
        client.beforeResponse = { release.await() }
        client.failure = AO3Error.Forbidden
        val refresh = async { state.load() }
        runCurrent()
        assertTrue(state.state.value.loading); assertNull(state.state.value.drafts)
        state.load(); assertEquals(2, client.gets.size)
        release.complete(Unit); refresh.await()
        assertEquals("AO3 refused the request (HTTP 403). Wait a while before trying again.", state.state.value.error)
        client.failure = null
        state.load()
        assertEquals(3, client.gets.size); assertNotNull(state.state.value.drafts)
    }

    @Test fun aLogoutDuringTheReadDiscardsThePrivateResponse() = runTest {
        val (auth, client, repository) = draftsSetup()
        val release = CompletableDeferred<Unit>()
        client.beforeResponse = { release.await() }
        val state = WritingDraftsState(repository, 1)
        val pending = async { try { state.load(); false } catch (_: CancellationException) { true } }
        runCurrent(); auth.logout(); release.complete(Unit)
        assertTrue(pending.await()); assertNull(state.state.value.drafts)
        state.load(); assertEquals(1, client.gets.size)
    }

    @Test fun cancellationDoesNotPublishThePageOrAnError() = runTest {
        val (_, client, repository) = draftsSetup()
        val release = CompletableDeferred<Unit>()
        client.beforeResponse = { release.await() }
        val state = WritingDraftsState(repository, 1)
        val pending = async { state.load() }
        runCurrent(); pending.cancel(); pending.join()
        assertNull(state.state.value.drafts); assertNull(state.state.value.error)
    }

    @Test fun returnedLoginFormExpiresTheSessionWithoutAnonymousRetry() = runTest {
        val (auth, client, repository) = draftsSetup()
        client.body = "<form id='new_user' action='/users/login'></form>"
        assertEquals(AO3Error.AuthenticationRequired, (repository.load() as AO3Result.Failure).error)
        assertTrue(auth.state.value is AO3AuthState.Expired)
        repository.load()
        assertEquals(1, client.gets.size)
    }
}

internal fun draftsFixture(page: Int): String = listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
    .map { File("$it/fixtures/ao3_demo_drafts_$page.html") }.first(File::isFile).readText()

internal suspend fun draftsSetup(signedIn: Boolean = true): Triple<AO3AuthRepository, DraftsMemoryClient, WritingDraftsRepository> {
    val auth = AO3AuthRepository(MemorySessionStore(if (signedIn) testSession() else null), MemoryCookieStore())
    auth.restoreSession()
    val client = DraftsMemoryClient()
    val rejectWrites = object : AO3FormPostClient {
        override suspend fun postForm(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> =
            error("The drafts list must never write")
    }
    return Triple(auth, client, WritingDraftsRepository(DefaultAO3AuthenticatedClient(client, rejectWrites, auth),
        auth, parseDispatcher = Dispatchers.Unconfined))
}

/** Memory only; there is no socket client or write interface in this test double. */
internal class DraftsMemoryClient : AO3Client {
    val gets = mutableListOf<String>()
    val headers = mutableListOf<Map<String, String>>()
    var beforeResponse: suspend () -> Unit = {}
    var failure: AO3Error? = null
    var body: String? = null
    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        gets += url; this.headers += headers
        beforeResponse()
        failure?.let { return AO3Result.Failure(it) }
        val page = if (url.toHttpUrl().queryParameter("page") == "2") 2 else 1
        return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), body ?: draftsFixture(page)))
    }
}
