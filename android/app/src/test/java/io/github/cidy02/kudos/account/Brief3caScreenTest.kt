package io.github.cidy02.kudos.account

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.lifecycle.ViewModelStore
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.app.*
import io.github.cidy02.kudos.auth.*
import io.github.cidy02.kudos.author.AuthorProfileScreen
import io.github.cidy02.kudos.browse.TagWorksScreen
import io.github.cidy02.kudos.browse.FandomWorksScreen
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseRepository
import io.github.cidy02.kudos.comments.*
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRepository
import io.github.cidy02.kudos.network.ao3.comments.*
import io.github.cidy02.kudos.network.ao3.preferences.AO3PreferencesRepository
import io.github.cidy02.kudos.network.ao3.search.AO3SearchRepository
import io.github.cidy02.kudos.network.ao3.writes.*
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.WorkRepository
import java.io.File
import java.nio.file.Files
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Fifteen audit rows, driven through real screens/repositories with terminal fake transports. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class Brief3caScreenTest {
    @get:Rule val compose = createComposeRule()
    private val client = Brief3caClient()
    private val chrome = PushedShellChrome()
    private val models = ViewModelStore()
    private val ioScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val dir = Files.createTempDirectory("brief-3ca")
    private lateinit var database: KudosDatabase
    private lateinit var works: WorkRepository
    private lateinit var settings: SettingsRepository
    private lateinit var auth: AO3AuthRepository
    private lateinit var lists: AccountListRepository
    private var opened: String? = null
    private var loginTaps = 0

    @Before fun prepare() {
        val app = ApplicationProvider.getApplicationContext<Application>()
        database = Room.inMemoryDatabaseBuilder(app, KudosDatabase::class.java).allowMainThreadQueries().build()
        works = WorkRepository(database, WorkFileStore(dir))
        settings = SettingsRepository(PreferenceDataStoreFactory.create(scope = ioScope,
            produceFile = { dir.resolve("settings.preferences_pb").toFile() }))
        setAccount(true)
    }
    @After fun close() {
        compose.runOnIdle { models.clear() }
        ioScope.cancel()
        database.close()
        dir.toFile().deleteRecursively()
    }
    private fun setAccount(signedIn: Boolean) {
        auth = AO3AuthRepository(MemorySessionStore(if (signedIn) testSession("Avery_Archive") else null), MemoryCookieStore())
        runBlocking<Unit> { auth.restoreSession() }
        lists = AccountListRepository(client, auth)
    }
    private fun writer() = DefaultAO3AuthenticatedClient(client, client, auth)
    private fun authorRepo() = AO3AuthorRepository(client, writer(), parseDispatcher = Dispatchers.Unconfined)
    private fun show(scale: Float = 2f, content: @Composable () -> Unit) {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale), LocalPushedShellChrome provides chrome) {
                    Column {
                        Row { chrome.trailingContent?.invoke(this) }
                        content()
                    }
                }
            }
        }
    }
    private fun awaitText(text: String) {
        compose.waitUntil(15_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
        compose.waitForIdle()
    }
    private fun noClipping(text: String) {
        val layouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(text, useUnmergedTree = true)
            .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        assertTrue(layouts.isNotEmpty())
        layouts.forEach { assertFalse(it.didOverflowHeight); assertFalse(it.isLineEllipsized(it.lineCount - 1)) }
    }
    private fun showAuthor(error: AO3Error? = null, pseud: String? = null, dashboard: Boolean = false) {
        client.dashboardError = error
        show {
            AuthorProfileScreen("Avery_Archive", initialPseud = pseud, authorRepository = authorRepo(),
                onOpenWork = {}, onOpenWeb = { opened = it }, isDashboard = dashboard)
        }
    }
    private fun showAccount(restoring: Boolean = false) {
        if (restoring) {
            val pending = CompletableDeferred<AO3Session?>()
            val memory = MemorySessionStore()
            val store = object : AO3SessionStore by memory {
                override suspend fun load(): AO3Session? = pending.await()
            }
            auth = AO3AuthRepository(store, MemoryCookieStore())
            lists = AccountListRepository(client, auth)
        }
        // No counts cache / subscriptions prefetch: this tests only the existing header read.
        val model = AccountViewModel(auth, authorRepo())
        models.put("account", model)
        show {
            AccountScreen(auth, lists, works, onLogin = { loginTaps++ }, onOpenList = {}, viewModel = model)
        }
    }

    @Test fun row6EmptyTagDistinguishesFiltersAndClearResetsWithOneExplicitRead() {
        client.emptyWorks = true
        var fandom by mutableStateOf(false)
        show {
            if (fandom) FandomWorksScreen("Test fandom", works, {}, repository = AO3BrowseRepository(client))
            else TagWorksScreen("Test tag", works, {}, repository = AO3SearchRepository(client, writer()))
        }
        awaitText("AO3 has no works for this tag right now.")
        compose.onNodeWithText("Clear Filters").assertDoesNotExist()
        assertEquals(1, client.gets.size)
        compose.onNodeWithContentDescription("Filters").performClick()
        compose.onNodeWithTag("AO3 filter form").performScrollToNode(hasText("Completion"))
        compose.onNodeWithText("Completion").performClick()
        compose.onNodeWithText("Complete").performClick()
        assertEquals(1, client.gets.size)
        compose.onNodeWithContentDescription("Apply filters").performClick()
        awaitText("No works with this tag match your filters.")
        compose.onNodeWithText("No matching works").assertExists()
        noClipping("No works with this tag match your filters.")
        assertEquals(2, client.gets.size)
        assertEquals("T", client.gets.last().toHttpUrl().queryParameter("work_search[complete]"))
        compose.onNodeWithText("Clear Filters").performClick()
        awaitText("AO3 has no works for this tag right now.")
        assertEquals(3, client.gets.size)
        assertNull(client.gets.last().toHttpUrl().queryParameter("work_search[complete]"))
        // Fandom already matches iOS; guard that unchanged sibling's pair and reset too.
        compose.runOnIdle { fandom = true }
        awaitText("AO3 has no works for this fandom right now.")
        assertEquals(4, client.gets.size)
        compose.onNodeWithContentDescription("Filter").performClick()
        compose.onNodeWithTag("AO3 filter form").performScrollToNode(hasText("Completion"))
        compose.onNodeWithText("Completion").performClick()
        compose.onNodeWithText("Complete").performClick()
        compose.onNodeWithContentDescription("Apply filters").performClick()
        awaitText("No works in this fandom match your filters.")
        noClipping("No works in this fandom match your filters.")
        assertEquals(5, client.gets.size)
        compose.onNodeWithText("Clear Filters").performClick()
        awaitText("AO3 has no works for this fandom right now.")
        assertEquals(6, client.gets.size)
        assertNull(client.gets.last().toHttpUrl().queryParameter("work_search[complete]"))
        assertTrue(client.posts.isEmpty())
    }

    @Test fun row10SignedOutDashboardHasIosCopyAndNoActionOrRead() {
        setAccount(false)
        show { AO3DashboardScreen(authorRepo(), {}, {}, {}, null, {}, {}) }
        awaitText("Not signed in")
        compose.onNodeWithText("Log in to AO3 to open your dashboard.").assertExists()
        noClipping("Log in to AO3 to open your dashboard.")
        compose.onNodeWithText("Try Again").assertDoesNotExist()
        assertTrue(chrome.mounted)
        assertTrue(client.gets.isEmpty()); assertTrue(client.posts.isEmpty())
    }

    @Test fun row12ExpiredPreferenceSaveKeepsEditsShowsIosMessageAndExpiresOnlyItsSession() {
        val repo = AO3PreferencesRepository(writer())
        show { AO3PreferencesScreen("Avery_Archive", repo) }
        awaitText("AO3 Preferences")
        // The existing local fixture has the real served checkbox and its human label.
        val form = io.github.cidy02.kudos.network.ao3.preferences.AO3PreferencesParser().parse(brief3caFixture("ao3_preferences"))
        val toggle = form.sections.first().toggles.first()
        compose.onNodeWithTag("AO3 preferences").performScrollToNode(hasText(toggle.label))
        compose.onNodeWithContentDescription(toggle.label).performClick()
        client.postError = AO3Error.AuthenticationRequired
        compose.onNodeWithText("Save").performClick()
        val message = "Your AO3 session expired. Sign in again from Account."
        compose.onNodeWithTag("AO3 preferences").performScrollToNode(hasText(message))
        awaitText(message)
        noClipping(message)
        assertTrue(auth.state.value is AO3AuthState.Expired)
        assertEquals(1, client.gets.size); assertEquals(1, client.posts.size)
        assertNull(auth.username())
        // Expiry never performs the successful-save reload or clears the edit flag.
        compose.onNodeWithText("Save").assertIsEnabled()
        compose.onNodeWithTag("AO3 preferences").performScrollToNode(hasText(toggle.label))
        compose.onNodeWithContentDescription(toggle.label).assertIsOn()
    }

    @Test fun row13RestoringAccountShowsSkeletonInsteadOfSignedOutHeader() {
        showAccount(restoring = true)
        compose.onNodeWithTag("Restoring account header").assertExists()
        compose.onNodeWithText("Not signed in").assertDoesNotExist()
        compose.onNodeWithText("Log In to AO3").assertDoesNotExist()
        assertEquals(0, loginTaps); assertTrue(client.gets.isEmpty()); assertTrue(client.posts.isEmpty())
    }
    @Test fun row14RestoringAccountSpeaksIosNameWithNoLoginActionOrRead() {
        showAccount(restoring = true)
        compose.onNodeWithContentDescription("Restoring AO3 session").assertExists().assertHasNoClickAction()
        assertTrue(client.gets.isEmpty()); assertTrue(client.posts.isEmpty())
    }
    @Test fun row18OwnProfile404ShowsUnavailableTitleUnderItsAccountHeaderWithoutRetry() {
        client.dashboardError = AO3Error.NotFound
        showAccount()
        awaitText("Profile unavailable")
        compose.onNodeWithText("AO3 Account", ignoreCase = true).assertExists()
        compose.onNodeWithText("Avery_Archive").assertExists()
        compose.onNodeWithText("Author unavailable").assertDoesNotExist()
        compose.onNodeWithText("Try Again").assertDoesNotExist()
        assertEquals(1, client.gets.size); assertTrue(client.posts.isEmpty())
    }
    @Test fun row19OwnProfile404HasIosMessageWithoutAProbeOrRetry() {
        client.dashboardError = AO3Error.NotFound
        showAccount()
        val message = "AO3 could not load your profile. It may be temporarily unavailable."
        awaitText(message); noClipping(message)
        compose.onNodeWithText("Open on AO3").assertDoesNotExist()
        assertEquals(1, client.gets.size); assertTrue(client.posts.isEmpty())
    }

    @Test fun row24FailedLaterAuthorPageKeepsRowsAndRetriesThatPageExactlyOnce() {
        client.laterPageError = AO3Error.Network("Page two failed")
        showAuthor()
        awaitText("Two Voices at Dawn")
        assertEquals(2, client.gets.size)
        compose.onNodeWithTag("Author profile").performScrollToNode(hasText("Next"))
        compose.onNodeWithText("Next").performClick()
        awaitText("Try Loading More")
        compose.onNodeWithText("Page two failed").assertExists(); noClipping("Try Loading More")
        compose.onNodeWithTag("Author profile").performScrollToNode(hasText("Two Voices at Dawn"))
        compose.onNodeWithText("Two Voices at Dawn").assertExists()
        assertEquals(3, client.gets.size)
        client.laterPageError = null
        compose.onNodeWithTag("Author profile").performScrollToNode(hasText("Try Loading More"))
        compose.onNodeWithText("Try Loading More").performClick()
        awaitText("Page 2 of 3")
        assertEquals(4, client.gets.size)
        assertEquals("2", client.gets.last().toHttpUrl().queryParameter("page"))
        compose.onNodeWithText("Try Loading More").assertDoesNotExist()
        assertTrue(client.posts.isEmpty())
    }
    @Test fun row32MissingAuthorUsesUnavailableTitleAndOpensDashboardWithoutAnotherRead() {
        showAuthor(AO3Error.NotFound)
        awaitText("Author unavailable")
        compose.onNodeWithText("Couldn't load author").assertDoesNotExist()
        compose.onNodeWithText("Try Again").assertDoesNotExist()
        assertEquals(1, client.gets.size)
        compose.onNodeWithText("Open on AO3").performClick()
        assertEquals("https://archiveofourown.org/users/Avery_Archive", opened)
        assertEquals(1, client.gets.size); assertTrue(client.posts.isEmpty())
    }
    @Test fun row33MissingPseudUsesIosMessageAndOpensThatPseudsDashboard() {
        showAuthor(AO3Error.NotFound, pseud = "Avery Writes")
        val message = "AO3 could not find this user or pseud. It may have been renamed or deleted."
        awaitText(message); noClipping(message)
        compose.onNodeWithText("Open on AO3").performClick()
        assertEquals("/users/Avery_Archive/pseuds/Avery%20Writes", opened!!.toHttpUrl().encodedPath)
        assertEquals(1, client.gets.size); assertTrue(client.posts.isEmpty())
    }
    @Test fun row34Non404FailureHasAuthorHeaderAboveErrorAndRetryReadsOnlyAfterHeaderSucceeds() {
        showAuthor(AO3Error.Forbidden, pseud = "Avery Writes")
        awaitText("Couldn't load author")
        compose.onNodeWithText("AO3 Author", ignoreCase = true).assertExists()
        compose.onNodeWithText("Avery Writes").assertExists()
        compose.onNodeWithText("Pseud of Avery_Archive").assertExists()
        compose.onNodeWithText("AO3 denied access.").assertExists()
        assertTrue(compose.onNodeWithText("AO3 Author", ignoreCase = true).fetchSemanticsNode().boundsInRoot.top <
            compose.onNodeWithText("Couldn't load author").fetchSemanticsNode().boundsInRoot.top)
        assertEquals(1, client.gets.size)
        client.dashboardError = null
        compose.onNodeWithText("Try Again").performClick()
        awaitText("Two Voices at Dawn")
        compose.onNodeWithText("Couldn't load author").assertDoesNotExist()
        assertEquals(3, client.gets.size); assertTrue(client.posts.isEmpty())
    }

    @Test fun row36SignedOutNamedSubscriptionsUseIosFailureAndRetryWithoutARead() {
        setAccount(false)
        show {
            val loader = remember { NamedSubscriptionsLoader(lists,
                io.github.cidy02.kudos.network.ao3.account.AO3NamedSubscriptionsScope.Series, 1) }
            SubscriptionsBrowser(emptyList(), emptyMap(), "series", {}, {}, 1, 1, false,
                io.github.cidy02.kudos.ui.subject.LocalKudosTokens.current.scopePalette, {}, {},
                AccountListUiState.AuthRequired, loader,
                io.github.cidy02.kudos.network.ao3.account.AO3NamedSubscriptionsScope.Series,
                {}, { loginTaps++ }, {}, {})
        }
        awaitText("Log in to AO3 to see your subscriptions.")
        compose.onNodeWithText("Couldn't load your list").assertExists()
        noClipping("Log in to AO3 to see your subscriptions.")
        compose.onNodeWithText("Try Again").performClick()
        awaitText("Log in to AO3 to see your subscriptions.")
        compose.onNodeWithText("Log In Again").assertDoesNotExist()
        assertEquals(0, loginTaps); assertTrue(client.gets.isEmpty()); assertTrue(client.posts.isEmpty())
    }

    private fun showComposer(): CommentsViewModel {
        client.comments = true
        val model = CommentsViewModel(AO3CommentRepository(client, writer()), AO3CommentTarget.Work(123),
            currentUsername = { auth.username() })
        models.put("comments", model)
        model.updateDraft("draft")
        show {
            val state by model.state.collectAsState()
            val draft by model.draft.collectAsState()
            if (state is CommentsUiState.Loaded) {
                CommentComposerSheet(null, null, draft, model::updateDraft, false, auth.username(), false,
                    io.github.cidy02.kudos.ui.subject.LocalKudosTokens.current.scopePalette, {}, {}, {})
            }
        }
        awaitText("New comment")
        compose.onNodeWithContentDescription("More formatting options").performClick()
        awaitText("Format Comment")
        assertEquals(1, client.gets.size)
        return model
    }
    @Test fun row37HeadingChipsOfferAllSixLevelsAndWriteEachChosenElementWithoutReads() {
        val model = showComposer()
        for (level in 1..6) {
            // By its spoken name: the Heading tile on the same sheet also reads "h3".
            compose.onNodeWithContentDescription("Heading $level").performScrollTo().assertExists()
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onAllNodesWithText("h$level", useUnmergedTree = true).fetchSemanticsNodes().forEach { node ->
                node.config[SemanticsActions.GetTextLayoutResult].action?.invoke(layouts)
            }
            assertTrue(layouts.isNotEmpty())
            layouts.forEach { assertFalse(it.didOverflowHeight); assertFalse(it.isLineEllipsized(it.lineCount - 1)) }
            compose.onNodeWithContentDescription("Heading $level").performClick()
            compose.waitForIdle()
            assertEquals("draft<h$level></h$level>", model.draft.value)
        }
        assertEquals(1, client.gets.size); assertTrue(client.posts.isEmpty())
        // Re-leveling a word selection preserves the enclosing heading's whole Unicode body.
        val enclosing = "<h3>one 星 & two</h3>"
        val start = enclosing.indexOf("星")
        val changed = CommentMarkup.applyTag(CommentMarkupTag.Heading,
            TextFieldValue(enclosing, TextRange(start, start + 1)), 1)
        assertEquals("<h1>one 星 & two</h1>", changed.text)
        assertEquals(TextRange(4, changed.text.length - 5), changed.selection)
        // The existing Heading tile keeps iOS's default, including invalid explicit levels.
        assertEquals("<h3>x</h3>", CommentMarkup.applyTag(CommentMarkupTag.Heading,
            TextFieldValue("x", TextRange(0, 1)), 7).text)
    }
    @Test fun row38EachHeadingSpeaksIosNameAndItsTapWritesThatExactLevel() {
        val model = showComposer()
        for (level in 1..6) {
            compose.onNodeWithContentDescription("Heading $level").performScrollTo().assertHasClickAction()
            compose.onNodeWithContentDescription("Heading $level").performClick()
            compose.waitForIdle()
            assertEquals("draft<h$level></h$level>", model.draft.value)
        }
        assertEquals(1, client.gets.size); assertTrue(client.posts.isEmpty())
    }

    @Test fun row47NonemptyAccountPageFilteredToZeroHasClearWhichOnlyChangesLocalFilters() {
        val model = AccountListViewModel(AccountListType.Bookmarks, lists, works)
        models.put("bookmarks", model)
        show {
            AccountWorksListScreen(AccountListType.Bookmarks, lists, AO3WriteRepository(writer()), works,
                settings, PrivacyGate(), {}, {}, {}, {}, viewModel = model)
        }
        awaitText("A Recommended Work")
        assertEquals(1, client.gets.size)
        compose.onNodeWithContentDescription("Filter").performClick()
        compose.onNodeWithTag("AO3 filter form").performScrollToNode(hasText("Completion"))
        compose.onNodeWithText("Completion").performClick()
        compose.onNodeWithText("Complete").performClick()
        compose.onNodeWithContentDescription("Done").performClick()
        awaitText("No works on this page match the current filters.")
        compose.onNodeWithText("No matching works").assertExists()
        noClipping("No works on this page match the current filters.")
        assertEquals(1, client.gets.size)
        compose.onNodeWithText("Clear Filters").performClick()
        awaitText("A Recommended Work")
        compose.onNodeWithText("No works on this page match the current filters.").assertDoesNotExist()
        assertEquals(1, client.gets.size); assertTrue(client.posts.isEmpty())
    }
}

private fun brief3caFixture(name: String): String {
    val file = listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
        .map { File("$it/fixtures/$name.html") }.firstOrNull(File::isFile)
        ?: error("Missing local fixture: $name")
    // Coil is an independent loader: remove images so it cannot issue a real request.
    return org.jsoup.Jsoup.parse(file.readText()).apply { select("img").remove() }.outerHtml()
}

private class Brief3caClient : AO3Client, AO3FormPostClient {
    val gets = CopyOnWriteArrayList<String>()
    val posts = CopyOnWriteArrayList<String>()
    @Volatile var dashboardError: AO3Error? = null
    @Volatile var laterPageError: AO3Error? = null
    @Volatile var postError: AO3Error? = null
    @Volatile var emptyWorks = false
    @Volatile var comments = false
    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        gets += url
        val address = url.toHttpUrl()
        val path = address.encodedPath
        val isIndex = path.endsWith("/works") || path.endsWith("/bookmarks") || path == "/works/search"
        val error = if (isIndex && address.queryParameter("page") == "2") laterPageError
            else if (!isIndex && !path.endsWith("/preferences") && !comments) dashboardError else null
        if (error != null) return AO3Result.Failure(error)
        val html = when {
            comments -> "<div id='comments_placeholder'><ol class='thread'></ol></div>" +
                "<form id='new_comment' action='/works/123/comments'><input name='authenticity_token' value='test-token'></form>"
            path.endsWith("/preferences") -> brief3caFixture("ao3_preferences")
            emptyWorks && isIndex -> "<ol class='work index group'></ol>"
            path.endsWith("/bookmarks") -> brief3caFixture("ao3_author_bookmarks")
            isIndex -> brief3caFixture("ao3_author_works")
            else -> brief3caFixture("ao3_author_dashboard")
        }
        return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), html))
    }
    override suspend fun postForm(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        posts += url
        postError?.let { return AO3Result.Failure(it) }
        return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), "<div class='flash notice'>Saved.</div>"))
    }
}
