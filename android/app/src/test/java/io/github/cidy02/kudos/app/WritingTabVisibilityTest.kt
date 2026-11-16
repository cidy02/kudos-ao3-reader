package io.github.cidy02.kudos.app

import android.app.Application
import android.content.Context
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.account.AO3AccountListCountsCache
import io.github.cidy02.kudos.account.AccountListRepository
import io.github.cidy02.kudos.account.AccountListType
import io.github.cidy02.kudos.account.AccountScreen
import io.github.cidy02.kudos.account.AccountViewModel
import io.github.cidy02.kudos.account.WritingDraftsRepository
import io.github.cidy02.kudos.account.WritingWorkDestination
import io.github.cidy02.kudos.account.showsStartWritingRow
import io.github.cidy02.kudos.account.startWritingDestination
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3PageCache
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorHeader
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRepository
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRoute
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorSeriesSummary
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorWebAction
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.network.ao3.writing.AO3ChapterForm
import io.github.cidy02.kudos.network.ao3.writing.AO3ServedControl
import io.github.cidy02.kudos.network.ao3.writing.AO3WorkForm
import io.github.cidy02.kudos.network.ao3.writing.AO3WorkFormKind
import io.github.cidy02.kudos.network.ao3.writing.AO3WorkSubmitAction
import io.github.cidy02.kudos.network.ao3.writing.recovery.WritingTextRecovery
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class WritingTabVisibilityTest {
    @get:Rule val temporary = TemporaryFolder()
    @get:Rule val compose = createComposeRule()

    private val createdControllers = mutableListOf<WritingTabController>()

    private fun controller(
        store: WritingTabStateStore = MemoryWritingTabStateStore(),
        recovery: WritingTextRecovery? = null,
        countsCache: AO3AccountListCountsCache? = null,
        cachedHeaderForUser: (String) -> AO3AuthorHeader? = { null }
    ): WritingTabController = WritingTabController(
        writingStateStore = store,
        recoveryStore = recovery,
        countsCache = countsCache,
        cachedHeaderForUser = cachedHeaderForUser
    ).also { createdControllers += it }

    @Before
    fun setUp() {
        AO3PageCache.shared.clear()
        val app = ApplicationProvider.getApplicationContext<Context>()
        app.getSharedPreferences("test_writing_tab_state", Context.MODE_PRIVATE).edit().clear().commit()
    }

    @After
    fun tearDown() {
        createdControllers.forEach { it.close() }
        createdControllers.clear()
    }

    // --- Rule 1: readers and signed-out users see Home, Library, Browse, Search; writers see Writing ---

    @Test
    fun writingTabRuleSignedOutNeverShows() {
        val rule = WritingTabRule(
            isSignedIn = false,
            workCount = 4,
            seriesCount = 2,
            draftCount = 1,
            hasLocalDrafts = true,
            lastKnownWrites = true,
            alreadyShownThisRun = false
        )
        assertFalse(rule.showsWritingTab)
    }

    @Test
    fun writingTabRuleSignedInWithAllZeroCountsHidesEvenIfLastKnownWasTrue() {
        val unseenReader = WritingTabRule(
            isSignedIn = true,
            workCount = 0,
            seriesCount = 0,
            draftCount = 0,
            hasLocalDrafts = false,
            lastKnownWrites = false,
            alreadyShownThisRun = false
        )
        assertFalse(unseenReader.showsWritingTab)

        val formerWriterWithAllZeros = WritingTabRule(
            isSignedIn = true,
            workCount = 0,
            seriesCount = 0,
            draftCount = 0,
            hasLocalDrafts = false,
            lastKnownWrites = true,
            alreadyShownThisRun = false
        )
        assertFalse(formerWriterWithAllZeros.showsWritingTab)
    }

    @Test
    fun writingTabRuleShowsWithWorkSeriesAO3DraftOrLocalDraft() {
        assertTrue(WritingTabRule(isSignedIn = true, workCount = 1, seriesCount = 0, draftCount = 0).showsWritingTab)
        assertTrue(WritingTabRule(isSignedIn = true, workCount = 0, seriesCount = 1, draftCount = 0).showsWritingTab)
        assertTrue(WritingTabRule(isSignedIn = true, workCount = 0, seriesCount = 0, draftCount = 1).showsWritingTab)
        assertTrue(WritingTabRule(isSignedIn = true, workCount = 0, seriesCount = 0, draftCount = 0, hasLocalDrafts = true).showsWritingTab)
    }

    // --- Grok P1.1, P3.8, P3.9: partial zero counts, weak lower bounds, uncounted headers ---

    @Test
    fun partialZeroCountsAndWeakBoundsAreUnknownNeverZero() {
        // Grok P1.1: partial zero counts must keep lastKnownWrites rather than hiding or overwriting with false.
        assertTrue(
            WritingTabRule(
                isSignedIn = true,
                workCount = 0,
                seriesCount = null,
                draftCount = null,
                hasLocalDrafts = false,
                lastKnownWrites = true,
                alreadyShownThisRun = false
            ).showsWritingTab
        )
        assertTrue(
            WritingTabRule(
                isSignedIn = true,
                workCount = 0,
                seriesCount = 0,
                draftCount = null,
                hasLocalDrafts = false,
                lastKnownWrites = true,
                alreadyShownThisRun = false
            ).showsWritingTab
        )
        assertFalse(
            WritingTabRule(
                isSignedIn = true,
                workCount = 0,
                seriesCount = null,
                draftCount = null,
                hasLocalDrafts = false,
                lastKnownWrites = false,
                alreadyShownThisRun = false
            ).showsWritingTab
        )

        val store = MemoryWritingTabStateStore()
        store.setLastKnownWrites(true, "draftonlywriter")
        val router = controller(store = store)
        router.evaluateWritingTab(
            isSignedIn = true,
            username = "draftonlywriter",
            workCount = 0,
            seriesCount = 0,
            draftCount = null,
            hasLocalDrafts = false
        )
        assertTrue(router.showsWritingTab)
        assertTrue(store.lastKnownWrites("draftonlywriter"))

        // Grok P3.8: weak list-count lower bounds (0 without exact) are unknown (null), never zero.
        assertNull(AO3AccountListCountsCache.Count(itemsOnPage = 0, totalPages = 2).knownCount)
        assertEquals(20, AO3AccountListCountsCache.Count(itemsOnPage = 20, totalPages = 2).knownCount)
        assertEquals(0, AO3AccountListCountsCache.Count(exact = 0).knownCount)

        // Grok P3.9: uncounted author headers must keep lastKnownWrites == true rather than inventing zero.
        val route = AO3AuthorRoute("draftonlywriter")
        val uncountedHeader = AO3AuthorHeader(
            username = "draftonlywriter",
            displayName = "draftonlywriter",
            avatarUrl = null,
            userId = null,
            pseuds = emptyList(),
            fandoms = emptyList(),
            subscriptionForm = null,
            actions = listOf(
                AO3AuthorWebAction(
                    label = "Works",
                    url = route.worksUrl,
                    kind = AO3AuthorWebAction.Kind.Works
                )
            ),
            recentWorks = emptyList(),
            recentSeries = emptyList()
        )
        val headerRouter = controller(store = store)
        headerRouter.evaluateWritingTab(
            header = uncountedHeader,
            route = route,
            username = "draftonlywriter",
            isSignedIn = true
        )
        assertTrue(headerRouter.showsWritingTab)
        assertTrue(store.lastKnownWrites("draftonlywriter"))
    }

    // --- Orchestrator fix 593c99a48: recent work or series on header is proof of writing ---

    @Test
    fun headerWithARecentWorkOrSeriesButNoCountShowsWriting() {
        val store = MemoryWritingTabStateStore()
        val route = AO3AuthorRoute("latestonly")
        val recentWork = AO3WorkSummary(
            id = 1L,
            title = "Latest",
            authors = listOf("latestonly"),
            fandoms = listOf("Original Work"),
            rating = "General Audiences",
            warnings = listOf("No Archive Warnings Apply"),
            categories = emptyList()
        )
        val recentSeries = AO3AuthorSeriesSummary(
            id = 2L,
            title = "Latest Series",
            creators = listOf("latestonly"),
            fandoms = listOf("Original Work"),
            summary = "",
            words = 1000,
            workCount = 1,
            dateUpdated = "2026-11-14",
            isComplete = true,
            url = "https://archiveofourown.org/series/2"
        )
        fun header(
            works: List<AO3WorkSummary> = emptyList(),
            series: List<AO3AuthorSeriesSummary> = emptyList()
        ) = AO3AuthorHeader(
            username = "latestonly",
            displayName = "latestonly",
            avatarUrl = null,
            userId = null,
            pseuds = emptyList(),
            fandoms = emptyList(),
            subscriptionForm = null,
            actions = emptyList(),
            recentWorks = works,
            recentSeries = series
        )

        // Empty lists with no count: unknown, so a first-seen account stays a reader.
        val reader = controller(store = store)
        reader.evaluateWritingTab(header(), route, username = "latestonly", isSignedIn = true)
        assertFalse(reader.showsWritingTab)
        assertFalse(store.lastKnownWrites("latestonly"))

        // No count, but a recent work under Your Latest: the account writes.
        val workWriter = controller(store = store)
        workWriter.evaluateWritingTab(header(works = listOf(recentWork)), route, username = "latestonly", isSignedIn = true)
        assertTrue(workWriter.showsWritingTab)
        assertTrue(store.lastKnownWrites("latestonly"))

        // Fresh store, no count, but a recent series on the header: the account writes.
        val seriesStore = MemoryWritingTabStateStore()
        val seriesWriter = controller(store = seriesStore)
        seriesWriter.evaluateWritingTab(header(series = listOf(recentSeries)), route, username = "latestonly", isSignedIn = true)
        assertTrue(seriesWriter.showsWritingTab)
        assertTrue(seriesStore.lastKnownWrites("latestonly"))
    }

    // --- Grok P1.3: local drafts are scoped to the signed-in account (even after reload) ---

    @Test
    fun localDraftsAreScopedToTheSignedInAccountAcrossReloads() {
        val tempDir = temporary.newFolder("scoped-recovery").toPath()
        val recovery = WritingTextRecovery(tempDir)
        val newWorkUrl = recovery.fileURL("Alice_Writer", "work:new", "content")
        recovery.save("<p>Alice's new work draft</p>", "", newWorkUrl)
        val existingWorkUrl = recovery.fileURL("Alice_Writer", "work:42", "summary")
        recovery.save("<p>Alice's work 42 summary</p>", "", existingWorkUrl)

        // Simulate a cold restart with a fresh WritingTextRecovery instance pointing at the same dir.
        val reloadedRecovery = WritingTextRecovery(tempDir)
        assertTrue(reloadedRecovery.hasLocalDrafts("alice_writer"))
        assertFalse(reloadedRecovery.hasLocalDrafts("bob_reader"))
        assertFalse(reloadedRecovery.hasLocalDrafts(null))
        assertFalse(reloadedRecovery.hasLocalDrafts("signed-out"))

        val store = MemoryWritingTabStateStore()
        val router = controller(store = store, recovery = reloadedRecovery)
        router.evaluateWritingTab(
            isSignedIn = true,
            username = "bob_reader",
            workCount = 0,
            seriesCount = 0,
            draftCount = 0
        )
        assertFalse(router.showsWritingTab)
        assertFalse(store.lastKnownWrites("bob_reader"))

        router.evaluateWritingTab(
            isSignedIn = true,
            username = "alice_writer",
            workCount = 0,
            seriesCount = 0,
            draftCount = 0
        )
        assertTrue(router.showsWritingTab)
        assertTrue(store.lastKnownWrites("alice_writer"))
    }

    // --- Grok P2.4: previewWork / previewChapter never mark account as writing; save/post do ---

    @Test
    fun previewingDoesNotMarkAccountAsWritingWhileSavingDoes() = runTest {
        val store = MemoryWritingTabStateStore()
        val router = controller(store = store)
        router.onAuthStateChanged(AO3AuthState.SignedIn("alice"), generation = 1)
        router.evaluateWritingTab(
            isSignedIn = true,
            username = "alice",
            workCount = 0,
            seriesCount = 0,
            draftCount = 0,
            hasLocalDrafts = false
        )
        assertFalse(router.showsWritingTab)
        assertFalse(store.lastKnownWrites("alice"))

        val workPreviewBody = """
            <html><head><meta name="csrf-token" content="w=="></head><body><div id="main">
            <div id="previewpane"><div class="draft work">
              <div id="workskin"><div class="preface group"><h2 class="title heading">Tide</h2></div>
              <div id="chapters"><div class="userstuff"><p>It rained.</p></div></div></div>
            </div>
            <form class="edit_work" id="edit_work_77" action="/works/77" method="post">
              <input type="hidden" name="_method" value="patch">
              <input type="submit" name="save_button" value="Save As Draft">
            </form></div></div></body></html>
        """.trimIndent()
        val chapterPreviewBody = """
            <html><head><meta name="csrf-token" content="c=="></head><body><div id="main">
            <div id="previewpane"><div class="draft chapter">
              <div class="userstuff"><p>Chapter preview</p></div>
            </div>
            <form action="/works/77/chapters/88" method="post">
              <input type="submit" name="post_button" value="Post">
            </form></div></div></body></html>
        """.trimIndent()
        val saveNoticeBody = """
            <html><body><main id="main"><div class="flash notice">Draft was successfully saved.</div></main></body></html>
        """.trimIndent()

        var nextPostBody = workPreviewBody
        val fakeClient = object : AO3AuthenticatedClient {
            override fun username(): String = "alice"
            override fun sessionGeneration(): Int = 1
            override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> =
                error("Unexpected GET $url")
            override suspend fun postAuthenticated(
                url: String,
                formFields: List<Pair<String, String>>,
                headers: Map<String, String>
            ): AO3Result<AO3HttpResponse> = AO3Result.Success(
                AO3HttpResponse(url, 200, emptyMap(), nextPostBody)
            )
        }
        val writes = AO3WriteRepository(fakeClient)

        val workForm = AO3WorkForm(
            kind = AO3WorkFormKind.New,
            workID = null,
            actionUrl = "https://archiveofourown.org/works",
            csrfToken = "w==",
            methodOverride = null,
            isPosted = false,
            servedControls = listOf(
                AO3ServedControl("input", mapOf("type" to "submit", "name" to "preview_button"), "", listOf("Preview")),
                AO3ServedControl("input", mapOf("type" to "submit", "name" to "save_button"), "", listOf("Save As Draft"))
            ),
            formAttributes = emptyMap()
        )
        val previewWorkResult = writes.previewWork(workForm, expectedGeneration = 1)
        assertTrue(previewWorkResult is AO3Result.Success)
        assertFalse(router.showsWritingTab)
        assertFalse(store.lastKnownWrites("alice"))

        nextPostBody = chapterPreviewBody
        val chapterForm = AO3ChapterForm(
            workID = 424242L,
            chapterID = null,
            actionUrl = "https://archiveofourown.org/works/424242/chapters",
            methodOverride = null,
            csrfToken = "c==",
            servedControls = listOf(
                AO3ServedControl("input", mapOf("type" to "submit", "name" to "preview_button"), "", listOf("Preview")),
                AO3ServedControl("input", mapOf("type" to "submit", "name" to "save_button"), "", listOf("Save As Draft"))
            ),
            formAttributes = emptyMap(),
            content = "<p>Chapter preview</p>"
        )
        val previewChapterResult = writes.previewChapter(chapterForm, expectedGeneration = 1)
        assertTrue(previewChapterResult is AO3Result.Success)
        assertFalse(router.showsWritingTab)
        assertFalse(store.lastKnownWrites("alice"))

        // Saving a draft or chapter DOES reveal Writing and persist lastKnownWrites = true.
        nextPostBody = saveNoticeBody
        val saveResult = writes.saveWork(workForm, expectedGeneration = 1)
        assertTrue(saveResult is AO3Result.Success)
        assertTrue(router.showsWritingTab)
        assertTrue(store.lastKnownWrites("alice"))

        val chapterStore = MemoryWritingTabStateStore()
        val chapterRouter = controller(store = chapterStore)
        chapterRouter.onAuthStateChanged(AO3AuthState.SignedIn("alice"), generation = 1)
        val saveChapterResult = writes.saveChapter(chapterForm, AO3WorkSubmitAction.SaveDraft, expectedGeneration = 1)
        assertTrue(saveChapterResult is AO3Result.Success)
        assertTrue(chapterRouter.showsWritingTab)
        assertTrue(chapterStore.lastKnownWrites("alice"))
    }

    // --- Rule 2: never removed mid-run; logout removes; account switch re-decides without sign-out ---

    @Test
    fun neverRemovedWhileOpenAndLogoutHidesIt() {
        val store = MemoryWritingTabStateStore()
        val router = controller(store = store)
        assertEquals(listOf(Routes.Home, Routes.Library, Routes.Browse), router.topLevelDestinations().map { it.route })

        router.onAuthStateChanged(AO3AuthState.SignedIn("saltwindow"), generation = 1)
        router.evaluateWritingTab(isSignedIn = true, username = "saltwindow", workCount = 1)
        assertTrue(router.showsWritingTab)
        assertEquals(listOf(Routes.Home, Routes.Library, Routes.Writing, Routes.Browse), router.topLevelDestinations().map { it.route })
        assertTrue(store.lastKnownWrites("saltwindow"))

        router.selection = Routes.Writing

        // Deleting the last work/draft while open keeps Writing for this run,
        // while updating stored answer to false for the next launch.
        router.evaluateWritingTab(
            isSignedIn = true,
            username = "saltwindow",
            workCount = 0,
            seriesCount = 0,
            draftCount = 0,
            hasLocalDrafts = false
        )
        assertTrue(router.showsWritingTab)
        assertEquals(Routes.Writing, router.selection)
        assertFalse(store.lastKnownWrites("saltwindow"))

        // Signing out hides Writing and moves selection off Writing.
        router.onAuthStateChanged(AO3AuthState.SignedOut, generation = 2)
        assertFalse(router.showsWritingTab)
        assertEquals(Routes.Home, router.selection)
        assertEquals(listOf(Routes.Home, Routes.Library, Routes.Browse), router.topLevelDestinations().map { it.route })

        // Next launch offline uses the updated stored answer (false).
        val nextLaunch = controller(store = store)
        nextLaunch.onAuthStateChanged(AO3AuthState.SignedIn("saltwindow"), generation = 1)
        assertFalse(nextLaunch.showsWritingTab)
    }

    @Test
    fun accountSwitchWithoutSignedOutStepReEvaluatesAndMovesSelectionOffWriting() {
        // Grok P1.2 & P3.7: switching directly from writer Alice to reader Bob must reset alreadyShownThisRun
        // and move selection off Writing before hiding.
        val store = MemoryWritingTabStateStore()
        val router = controller(store = store)

        router.onAuthStateChanged(AO3AuthState.SignedIn("alice"), generation = 1)
        router.evaluateWritingTab(isSignedIn = true, username = "alice", workCount = 2)
        router.selection = Routes.Writing
        assertTrue(router.showsWritingTab)
        assertEquals(Routes.Writing, router.selection)

        // Direct switch to Bob (reader) with no intermediate SignedOut step.
        router.onAuthStateChanged(AO3AuthState.SignedIn("bob"), generation = 2)
        assertFalse(router.showsWritingTab)
        assertEquals(Routes.Home, router.selection)
        assertEquals(listOf(Routes.Home, Routes.Library, Routes.Browse), router.topLevelDestinations().map { it.route })

        router.evaluateWritingTab(
            isSignedIn = true,
            username = "bob",
            workCount = 0,
            seriesCount = 0,
            draftCount = 0,
            hasLocalDrafts = false
        )
        assertFalse(router.showsWritingTab)
        assertFalse(store.lastKnownWrites("bob"))
        assertTrue(store.lastKnownWrites("alice"))
    }

    // --- Rule 3: offline launch uses per-account persisted answer; unseen defaults to false ---

    @Test
    fun offlineLaunchUsesPersistedSharedPreferencesAnswerPerAccountAndDefaultsUnseenToFalse() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val prefs = context.getSharedPreferences("test_writing_tab_state", Context.MODE_PRIVATE)
        val firstStore = SharedPreferencesWritingTabStateStore(prefs)
        firstStore.setLastKnownWrites(true, "Alice_Writer")
        firstStore.setLastKnownWrites(false, "Bob_Reader")

        // Cold launch with a fresh SharedPreferencesWritingTabStateStore on the same backing file.
        val offlineAlice = controller(store = SharedPreferencesWritingTabStateStore(prefs))
        offlineAlice.onAuthStateChanged(AO3AuthState.SignedIn("alice_writer"), generation = 1)
        assertTrue(offlineAlice.showsWritingTab)

        val offlineBob = controller(store = SharedPreferencesWritingTabStateStore(prefs))
        offlineBob.onAuthStateChanged(AO3AuthState.SignedIn("bob_reader"), generation = 1)
        assertFalse(offlineBob.showsWritingTab)

        val offlineUnseen = controller(store = SharedPreferencesWritingTabStateStore(prefs))
        offlineUnseen.onAuthStateChanged(AO3AuthState.SignedIn("never_seen_before"), generation = 1)
        assertFalse(offlineUnseen.showsWritingTab)
    }

    // --- Rule 4: restored or deep-linked Writing selection goes to Home while hidden and returns ---

    @Test
    fun restoredAndDeepLinkedWritingSelectionGoesToHomeWhileHiddenAndReturnsWhenRevealed() {
        val store = MemoryWritingTabStateStore()
        val router = controller(store = store)

        // Restored Writing selection while hidden -> Home, preserving intent to return.
        router.pendingWritingRoute = WritingRoute.Drafts
        router.restoreSelection(Routes.Writing)
        assertEquals(Routes.Home, router.selection)
        assertEquals(WritingRoute.Drafts, router.pendingWritingRoute)

        // Once the account answers as a writer, selection returns to Writing with route intact.
        router.evaluateWritingTab(isSignedIn = true, username = "saltwindow", workCount = 6)
        assertTrue(router.showsWritingTab)
        assertEquals(Routes.Writing, router.selection)
        assertEquals(WritingRoute.Drafts, router.consumePendingWritingRoute())
        assertTrue(router.returnToWritingRequestFlow.value > 0)

        // Leaving Home before Writing appears drops restoredWritingSelection.
        val lateRouter = controller(store = MemoryWritingTabStateStore())
        lateRouter.restoreSelection(Routes.Writing)
        assertEquals(Routes.Home, lateRouter.selection)
        lateRouter.selection = Routes.Library
        lateRouter.evaluateWritingTab(isSignedIn = true, username = "saltwindow", workCount = 6)
        assertEquals(Routes.Library, lateRouter.selection)

        // Deep-linked legacy route while hidden -> Home, returns to Writing when revealed.
        val deepLinkRouter = controller(store = MemoryWritingTabStateStore())
        deepLinkRouter.openLegacyAccountRoute(LegacyAccountRoute.Drafts)
        assertEquals(Routes.Home, deepLinkRouter.selection)
        assertEquals(WritingRoute.Drafts, deepLinkRouter.pendingWritingRoute)
        deepLinkRouter.evaluateWritingTab(isSignedIn = true, username = "writer", draftCount = 1)
        assertEquals(Routes.Writing, deepLinkRouter.selection)
        assertEquals(WritingRoute.Drafts, deepLinkRouter.consumePendingWritingRoute())
    }

    // --- Rule 5 & NavigationBar UI: Start Writing row and Material NavigationBar destinations ---

    @Test
    fun startWritingRowShowsOnlyWhileSignedInAndWritingTabHidden() {
        assertFalse(showsStartWritingRow(isSignedIn = false, showsWritingTab = false))
        assertNull(startWritingDestination(isSignedIn = false, showsWritingTab = false))
        assertTrue(showsStartWritingRow(isSignedIn = true, showsWritingTab = false))
        assertEquals(WritingWorkDestination.route(), startWritingDestination(isSignedIn = true, showsWritingTab = false))
        assertFalse(showsStartWritingRow(isSignedIn = true, showsWritingTab = true))
        assertNull(startWritingDestination(isSignedIn = true, showsWritingTab = true))
    }

    @Test
    fun accountScreenShowsStartWritingOnlyForSignedInUsersWithHiddenWritingTab() = runTest {
        val app = ApplicationProvider.getApplicationContext<Application>()
        val tempDir = Files.createTempDirectory("start-writing-ui")
        val db = Room.inMemoryDatabaseBuilder(app, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        try {
            val workRepo = WorkRepository(db, WorkFileStore(tempDir))
            val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
            auth.restoreSession()
            val vm = AccountViewModel(authRepository = auth)
            var startWritingClicks = 0
            var showsWriting = false

            val showsWritingState = androidx.compose.runtime.mutableStateOf(false)
            compose.setContent {
                KudosTheme(KudosThemeMode.Light) {
                    AccountScreen(
                        authRepository = auth,
                        workRepository = workRepo,
                        onLogin = {},
                        onOpenList = {},
                        showsWritingTab = showsWritingState.value,
                        onStartWriting = { startWritingClicks++ },
                        viewModel = vm
                    )
                }
            }

            compose.waitUntil(5_000) {
                compose.onAllNodesWithText("Start Writing", useUnmergedTree = true)
                    .fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("Start Writing").performClick()
            assertEquals(1, startWritingClicks)

            // Once Writing tab is revealed, Start Writing disappears.
            showsWriting = true
            showsWritingState.value = showsWriting
            compose.waitForIdle()
            compose.onNodeWithText("Start Writing").assertDoesNotExist()

            // Even when Writing tab is hidden again, signed-out users never see Start Writing.
            showsWriting = false
            showsWritingState.value = showsWriting
            auth.logout()
            compose.waitForIdle()
            compose.onNodeWithText("Start Writing").assertDoesNotExist()
        } finally {
            db.close()
            tempDir.toFile().deleteRecursively()
        }
    }

    @Test
    fun navigationBarShowsHomeLibraryBrowseSearchForReadersAndAddsWritingForWriters() {
        val showsWritingState = androidx.compose.runtime.mutableStateOf(false)
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                ShellNavigationBar(
                    currentRoute = Routes.Home,
                    showsWriting = showsWritingState.value,
                    onNavigate = {}
                )
            }
        }

        compose.onNodeWithText("Home").assertExists()
        compose.onNodeWithText("Library").assertExists()
        compose.onNodeWithText("Browse").assertExists()
        compose.onNodeWithText("Search").assertExists()
        compose.onNodeWithText("Writing").assertDoesNotExist()

        showsWritingState.value = true
        compose.waitForIdle()
        compose.onNodeWithText("Writing").assertExists()
    }

    // --- Rule 6 & Grok P3.10: no new AO3 requests; debug session-only reveal does not persist ---

    @Test
    fun revealWritingTabForSessionDoesNotPersistToStore() {
        val store = MemoryWritingTabStateStore()
        val router = controller(store = store)
        router.evaluateWritingTab(
            isSignedIn = true,
            username = "saltwindow",
            workCount = 0,
            seriesCount = 0,
            draftCount = 0,
            hasLocalDrafts = false
        )
        assertFalse(router.showsWritingTab)
        assertFalse(store.lastKnownWrites("saltwindow"))

        router.revealWritingTabForSession()
        assertTrue(router.showsWritingTab)
        assertFalse(store.lastKnownWrites("saltwindow"))
    }

    @Test
    fun evaluatingWritingTabFromCountsAndCacheMakesZeroAO3Requests() = runTest {
        var networkCalls = 0
        val countingClient = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                networkCalls += 1
                error("Unexpected AO3 request $url")
            }
        }
        val cache = AO3AccountListCountsCache()
        val store = MemoryWritingTabStateStore()
        val router = controller(store = store, countsCache = cache)

        val auth = AO3AuthRepository(MemorySessionStore(testSession("writer_user")), MemoryCookieStore())
        auth.restoreSession()
        val generation = auth.generation.value
        val scope = AO3AccountListCountsCache.scope("writer_user", generation)
        AccountListRepository(client = countingClient, authRepository = auth, countsCache = cache)

        router.onAuthStateChanged(AO3AuthState.SignedIn("writer_user"), generation)
        assertFalse(router.showsWritingTab)

        // Recording counts already parsed (e.g. from drafts/dashboard) reveals Writing with 0 AO3 requests.
        cache.put(AO3AccountListCountsCache.DRAFTS, scope, AO3AccountListCountsCache.Count(exact = 1))
        assertTrue(router.showsWritingTab)
        assertTrue(store.lastKnownWrites("writer_user"))
        assertEquals(0, networkCalls)
    }

    @Test
    fun loadingDraftsRepositoryRecordsDraftsCountAndRevealsWritingTab() = runTest {
        val draftsHtml = listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
            .map { java.io.File("$it/fixtures/ao3_demo_drafts_1.html") }
            .first { it.isFile }
            .readText()
        val auth = AO3AuthRepository(MemorySessionStore(testSession("draft_writer")), MemoryCookieStore())
        auth.restoreSession()
        val cache = AO3AccountListCountsCache()
        val store = MemoryWritingTabStateStore()
        val router = controller(store = store, countsCache = cache)
        router.onAuthStateChanged(AO3AuthState.SignedIn("draft_writer"), auth.generation.value)
        assertFalse(router.showsWritingTab)

        val fakeAuthClient = object : AO3AuthenticatedClient {
            override fun username(): String = "draft_writer"
            override fun sessionGeneration(): Int = auth.generation.value
            override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> =
                AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), draftsHtml))
            override suspend fun postAuthenticated(
                url: String,
                formFields: List<Pair<String, String>>,
                headers: Map<String, String>
            ): AO3Result<AO3HttpResponse> = error("Unexpected POST $url")
        }
        val draftsRepo = WritingDraftsRepository(
            client = fakeAuthClient,
            authRepository = auth,
            parseDispatcher = Dispatchers.Unconfined,
            countsCache = cache
        )
        val result = draftsRepo.load(page = 1)
        assertTrue(result is AO3Result.Success)
        assertTrue(router.showsWritingTab)
        assertTrue(store.lastKnownWrites("draft_writer"))
    }

    @Test
    fun loadingDashboardWithUncountedActionsAndRecentWorkRevealsWritingTab() = runTest {
        val dashboardHtml = listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
            .map { java.io.File("$it/fixtures/ao3_author_dashboard_demo.html") }
            .first { it.isFile }
            .readText()
        val store = MemoryWritingTabStateStore()
        val router = controller(store = store)
        router.onAuthStateChanged(AO3AuthState.SignedIn("Avery_Archive"), generation = 1)
        assertFalse(router.showsWritingTab)

        val fakeAuthClient = object : AO3AuthenticatedClient {
            override fun username(): String = "Avery_Archive"
            override fun sessionGeneration(): Int = 1
            override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> =
                AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), dashboardHtml))
            override suspend fun postAuthenticated(
                url: String,
                formFields: List<Pair<String, String>>,
                headers: Map<String, String>
            ): AO3Result<AO3HttpResponse> = error("Unexpected POST $url")
        }
        val authorRepo = AO3AuthorRepository(
            authenticatedClient = fakeAuthClient,
            parseDispatcher = Dispatchers.Unconfined
        )
        val result = authorRepo.loadDashboard(AO3AuthorRoute("Avery_Archive"))
        assertTrue(result is AO3Result.Success)
        val header = (result as AO3Result.Success).value
        assertTrue(header.recentWorks.orEmpty().isNotEmpty())
        assertTrue(router.showsWritingTab)
        assertTrue(store.lastKnownWrites("Avery_Archive"))
    }
}
