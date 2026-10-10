package io.github.cidy02.kudos.account

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.lifecycle.ViewModelStore
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.app.*
import io.github.cidy02.kudos.auth.*
import io.github.cidy02.kudos.author.AuthorProfileScreen
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.author.*
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxRepository
import io.github.cidy02.kudos.network.ao3.series.AO3SeriesRepository
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.ui.theme.*
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.nio.file.Files

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CachedAO3PagesScreenTest {
    @get:Rule val compose = createComposeRule()
    private enum class Screen { Inbox, OwnProfile, Author, Series, Hub }
    private var mode by mutableStateOf(KudosThemeMode.Light)
    private var scale by mutableStateOf(1f)
    private var visit by mutableIntStateOf(0)
    private var clock = 0L
    private val cache = AO3PageCache(now = { clock })
    private val models = ViewModelStore()
    private val session = AO3Session("tester", listOf(AO3StoredCookie(AO3StoredCookie.SessionCookieName, "local")))
    private val auth = AO3AuthRepository(object : AO3SessionStore {
        override suspend fun load() = session
        override suspend fun save(session: AO3Session) { }
        override suspend fun delete() = true
        override suspend fun isRemovalPending() = false
        override suspend fun markRemovalPending() { }
        override suspend fun clearRemovalPending() { }
    }, object : AO3CookieStore {
        override suspend fun captureSession(username: String): AO3Session? = null
        override suspend fun install(session: AO3Session) { }
        override suspend fun clear() { }
    })
    private val reads = java.util.concurrent.atomic.AtomicInteger()
    private var currentScreen = Screen.Author
    private val client = object : AO3Client, AO3AuthenticatedClient {
        @Volatile var offline = false
        @Volatile var failure: AO3Error? = null
        override val sessionChanges get() = auth.generation
        override fun username() = auth.username()
        override fun sessionGeneration() = auth.generation.value
        override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
            reads.incrementAndGet()
            failure?.let { return AO3Result.Failure(it) }
            if (offline) return AO3Result.Failure(AO3Error.Network("offline", offline = true))
            val name = when {
                url.contains("/inbox") -> "ao3_inbox_manage"
                url.contains("/series/321") -> "ao3_demo_dawn_series"
                url.contains("/works") -> "ao3_author_works"
                else -> "ao3_author_dashboard_demo"
            }
            val raw = fixture(name)
            // Never give Coil a remote image URL, even independently of the fake AO3 client.
            val html = org.jsoup.Jsoup.parse(raw).apply { select("img").remove() }.outerHtml()
            return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), html))
        }
        override suspend fun getAuthenticated(url: String) = get(url, emptyMap())
        override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>,
            headers: Map<String, String>): AO3Result<AO3HttpResponse> = error("No writes in this test")
    }
    private val authors = AO3AuthorRepository(client, client, parseDispatcher = Dispatchers.Unconfined, pageCache = cache)
    private val inbox = AO3InboxRepository(client, pageCache = cache)
    private val series = AO3SeriesRepository(client, authenticatedClient = client, pageCache = cache)
    private val comments = AO3CommentRepository(client, client)

    @After fun stopModels() { compose.runOnIdle { models.clear() } }
    // Do not close the database/client after a screen test: off-main reads can still be finishing.

    private fun show(screen: Screen) {
        currentScreen = screen
        runBlocking<Unit> {
            auth.restoreSession()
            when (screen) {
                Screen.Inbox -> inbox.load()
                Screen.Series -> series.detailPage("https://archiveofourown.org/series/321")
                else -> {
                    val route = AO3AuthorRoute(if (screen == Screen.Author) "Avery_Archive" else "tester")
                    authors.loadDashboard(route)
                    if (screen != Screen.Hub) authors.loadWorks(route)
                }
            }
        }
        clock = 300_000L
        client.offline = true
        val app = ApplicationProvider.getApplicationContext<Application>()
        val db = Room.inMemoryDatabaseBuilder(app, KudosDatabase::class.java).allowMainThreadQueries().build()
        val works = WorkRepository(db, WorkFileStore(Files.createTempDirectory("cached-pages-screen")))
        val lists = AccountListRepository(client, auth)
        val chrome = PushedShellChrome()
        compose.setContent {
            KudosTheme(mode) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale), LocalPushedShellChrome provides chrome) {
                    key(visit) {
                        Column {
                            Row { chrome.trailingContent?.invoke(this) }
                            when (screen) {
                                Screen.Inbox -> {
                                    val vm = remember {
                                        AccountInboxViewModel(inbox, comments).also { models.put("inbox-$visit", it) }
                                    }
                                    AccountInboxPane(inbox, comments, "tester", onOpenWorkComments = { _, _ -> }, viewModel = vm)
                                }
                                Screen.Hub -> {
                                    val vm = remember { AccountViewModel(auth, authors).also { models.put("hub-$visit", it) } }
                                    AccountScreen(auth, lists, works, onLogin = {}, onOpenList = {}, viewModel = vm)
                                }
                                Screen.Series -> SeriesWorksScreen("https://archiveofourown.org/series/321", series, onOpenWork = {})
                                else -> AuthorProfileScreen(if (screen == Screen.Author) "Avery_Archive" else "tester",
                                    authorRepository = authors, authRepository = auth, onOpenWork = {})
                            }
                        }
                    }
                }
            }
        }
        awaitBanner()
    }

    private fun awaitBanner() {
        compose.waitUntil(15_000) { compose.onAllNodesWithText(BANNER).fetchSemanticsNodes().size == 1 }
        compose.waitForIdle()
    }
    private fun recoveredOnReopen() {
        val before = reads.get()
        compose.runOnIdle { client.offline = false; visit++ }
        compose.waitForIdle()
        compose.waitUntil(15_000) {
            reads.get() > before && compose.onAllNodesWithText(BANNER).fetchSemanticsNodes().isEmpty() &&
                listOf("Loading author profile", "Loading Inbox", "Loading series…").all {
                    compose.onAllNodesWithText(it).fetchSemanticsNodes().isEmpty()
                }
        }
        compose.waitForIdle()
        if (currentScreen == Screen.Author || currentScreen == Screen.OwnProfile) {
            compose.waitUntil(15_000) {
                compose.onAllNodesWithText("Two Voices at Dawn").fetchSemanticsNodes().isNotEmpty()
            }
        }
        if (currentScreen == Screen.Series) compose.waitUntil(15_000) {
            compose.onAllNodesWithText("The Dawn Cycle").fetchSemanticsNodes().isNotEmpty()
        }
    }
    private fun refuseOnReopen() {
        val before = reads.get()
        compose.runOnIdle { client.offline = false; client.failure = AO3Error.Forbidden; visit++ }
        compose.waitForIdle()
        compose.waitUntil(15_000) {
            reads.get() > before && compose.onAllNodesWithText("AO3 denied access.").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onAllNodesWithText(BANNER).assertCountEquals(0)
        compose.runOnIdle { client.failure = null; client.offline = true; visit++ }
        compose.waitForIdle()
        compose.waitUntil(15_000) {
            compose.onAllNodesWithText(AO3Error.OFFLINE_MESSAGE).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onAllNodesWithText(BANNER).assertCountEquals(0)
    }
    @Test fun inboxRefusalCannotShowOrResurrectTheOldCopy() { show(Screen.Inbox); refuseOnReopen() }
    @Test fun authorRefusalCannotShowOrResurrectTheOldCopy() { show(Screen.Author); refuseOnReopen() }
    @Test fun seriesRefusalCannotShowOrResurrectTheOldCopy() { show(Screen.Series); refuseOnReopen() }

    @Test fun inboxBannerShowsAndClears() { show(Screen.Inbox); recoveredOnReopen() }
    @Test fun ownProfileBannerShowsAndClears() { show(Screen.OwnProfile); recoveredOnReopen() }
    @Test fun authorBannerShowsAndClears() { show(Screen.Author); recoveredOnReopen() }
    @Test fun seriesBannerShowsAndClears() { show(Screen.Series); recoveredOnReopen() }
    @Test fun accountHubBannerShowsAndClears() { show(Screen.Hub); recoveredOnReopen() }

    @Test fun authorPullRefreshBypassesCacheAndClearsBanner() {
        show(Screen.Author)
        val before = reads.get()
        compose.runOnIdle { client.offline = false }
        compose.onNodeWithTag("Author profile").performTouchInput {
            swipeDown(startY = 200f, endY = 1000f, durationMillis = 700)
        }
        compose.waitForIdle()
        compose.waitUntil(15_000) {
            reads.get() >= before + 2 && compose.onAllNodesWithText(BANNER).fetchSemanticsNodes().isEmpty()
        }
        compose.waitForIdle()
    }

    @Test fun allThemesAtAccessibilitySizeHaveNoHeightOverflowOrEllipsis() {
        scale = 2f
        show(Screen.Inbox)
        for (theme in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { mode = theme }
            awaitBanner()
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText(BANNER, useUnmergedTree = true)
                .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertTrue(layouts.isNotEmpty())
            layouts.forEach {
                assertFalse(it.didOverflowHeight)
                if (it.lineCount > 0) assertFalse(it.isLineEllipsized(it.lineCount - 1))
            }
        }
    }

    companion object {
        private const val BANNER = "Showing cached AO3 data"
        private fun fixture(name: String): String = listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
            .map { File("$it/fixtures/$name.html") }.first(File::isFile).readText()
    }
}
