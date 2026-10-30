package io.github.cidy02.kudos.author

import androidx.compose.ui.semantics.getOrNull
import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.author.*
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.search.SearchFilterSheet
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import java.io.File
import kotlinx.coroutines.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2000dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AuthorProfileSortScreenTest {
    @org.junit.Before fun clearPageCache() { io.github.cidy02.kudos.network.ao3.AO3PageCache.shared.clear() }
    @get:Rule val compose = createComposeRule()
    private val source = FixtureSource { name ->
        listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
            .map { File("$it/fixtures/$name.html") }.firstOrNull(File::isFile)?.readBytes()
    }
    private val requests = mutableListOf<String>()
    private var failSecondPage = false
    private var beforeResponse: suspend (String) -> Unit = {}
    private var responseBody: (String, String) -> String = { _, body -> body }
    private val client = object : AO3Client {
        override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
            requests += url
            beforeResponse(url)
            if (failSecondPage && url.toHttpUrl().queryParameter("page") == "2")
                return AO3Result.Failure(AO3Error.Network("Offline"))
            val fixture = DemoNetwork.webFixture(url.toHttpUrl(), source)?.decodeToString() ?: error("Unbundled test address $url")
            // The real hero uses Coil; strip fixture images so even that independent loader has no URL.
            val html = org.jsoup.Jsoup.parse(fixture).apply { select("img").remove() }.outerHtml()
            return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), responseBody(url, html)))
        }
    }

    private var logins = 0
    private val subscriptionCalls = mutableListOf<String>()
    private val subscriptionClient = object : io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient {
        override fun username(): String? = null
        override fun sessionGeneration(): Int? = 0
        override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> {
            subscriptionCalls += url
            error("A signed-out subscription must ask before any request")
        }
        override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
            subscriptionCalls += url
            error("A signed-out subscription must never post")
        }
    }
    private var visible by mutableStateOf(true)
    private val openedAbout = mutableListOf<AO3AuthorRoute>()
    private val openedWeb = mutableListOf<String>()
    private var theme by mutableStateOf(KudosThemeMode.Light)
    private lateinit var view: View
    private lateinit var tokens: KudosTokens
    private val washes = ShellWashes()
    private var expectedPalette: SubjectPalette? = null
    private fun show(initialTab: AuthorTab, dashboard: Boolean, withSubscriptionWrites: Boolean = false) {
        val chrome = PushedShellChrome()
        val repo = AO3AuthorRepository(publicClient = client, parseDispatcher = Dispatchers.Unconfined,
            pageCache = AO3PageCache(ttlMillis = 0, staleMillis = 0))
        compose.setContent {
            KudosTheme(theme) {
                view = LocalView.current
                tokens = LocalKudosTokens.current
                expectedPalette = tokens.scopePalette
                CompositionLocalProvider(LocalPushedShellChrome provides chrome, LocalShellWashes provides washes) {
                    Column {
                        Row { chrome.trailingContent?.invoke(this) }
                        if (visible) AuthorProfileScreen("Avery_Archive", onOpenAbout = { openedAbout += it }, initialTab = initialTab, authorRepository = repo, onOpenWork = {},
                            isDashboard = dashboard, onOpenWeb = { openedWeb += it }, onLogin = { logins++ },
                            seriesWrites = if (withSubscriptionWrites) io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository(subscriptionClient) else null)
                    }
                }
            }
        }
        awaitText(when (initialTab) { AuthorTab.Series -> "The Dawn Cycle"; AuthorTab.About -> "Bio"; AuthorTab.Bookmarks -> "A Recommended Work"; else -> "Two Voices at Dawn" })
    }

    @Test fun bookmarksHaveASectionHeadingAndCardLoadMoreThatStillLoadsTheNextPage() {
        show(AuthorTab.Bookmarks, false)
        val heading = compose.onNode(hasText("Bookmarks") and
            SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.Heading),
            useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val first = compose.onNodeWithText("A Recommended Work", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue("Section heading precedes bookmarks", heading.bottom <= first.top)
        for (mode in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { theme = mode }
            val card = compose.onNodeWithContentDescription("A Recommended Work, by Book Pseud").fetchSemanticsNode().boundsInRoot
            assertGround(tokens.cardFill, card.center.x, card.top + 3f)
            val more = compose.onNode(hasText("Load More") and hasClickAction()).fetchSemanticsNode().boundsInRoot
            assertGround(tokens.theme.cardSurface, more.center.x, more.top + 3f)
        }
        val before = requests.size
        compose.onNodeWithText("Load More").performClick()
        awaitText("Page 2 of 4")
        assertEquals(before + 1, requests.size)
        assertTrue(requests.last().contains("page=2"))
    }

    private fun assertGround(expected: Color, x: Float, y: Float) {
        var actual = Color.Unspecified
        compose.runOnIdle {
            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(Canvas(bitmap)); actual = Color(bitmap.getPixel(x.toInt(), y.toInt())); bitmap.recycle()
        }
        assertEquals(expected.red, actual.red, 0.012f)
        assertEquals(expected.green, actual.green, 0.012f)
        assertEquals(expected.blue, actual.blue, 0.012f)
    }

    @Test fun signedOutSubscribeAsksBeforeAnyRequestAndLoginOpensTheLoginRoute() {
        // Give the public dashboard a subscribe form, as AO3 does for a guest.
        responseBody = { url, body ->
            if (url.toHttpUrl().encodedPath == "/users/Avery_Archive") org.jsoup.Jsoup.parse(body).apply {
                select("form[action*=/subscriptions]").remove()
                body().append("""<form action="/users/Avery_Archive/subscriptions" method="post">
                    <input name="authenticity_token" value="test"><input name="subscription[subscribable_id]" value="42">
                    <input name="subscription[subscribable_type]" value="User"><input type="submit" value="Subscribe">
                    </form>""")
            }.outerHtml() else body
        }
        show(AuthorTab.Works, false, withSubscriptionWrites = true)
        val readsBefore = requests.size
        compose.onNodeWithText("Subscribe").performClick()
        compose.onNodeWithText("Log in to AO3").assertExists()
        compose.onNodeWithText("Log in to your AO3 account to do this.").assertExists()
        compose.onNodeWithText("Cancel").performClick()
        assertEquals(0, logins)
        compose.onNodeWithText("Subscribe").performClick()
        compose.onNodeWithText("Log In").performClick()
        assertEquals(1, logins)
        assertTrue(subscriptionCalls.isEmpty())
        assertTrue(openedWeb.isEmpty())
        assertEquals(readsBefore, requests.size)
    }

    @Test fun returningFromAChildKeepsSeriesWithoutEvenAnExpiredCacheRead() {
        show(AuthorTab.Series, false)
        val before = requests.size
        compose.runOnIdle { visible = false }
        compose.waitForIdle()
        compose.runOnIdle { visible = true }
        awaitText("The Dawn Cycle")
        compose.onNodeWithText("The Hidden Cycle").assertExists()
        assertEquals(before, requests.size)
        assertTrue(requests.none { it.toHttpUrl().encodedPath.endsWith("/works") })
    }

    /** The account's Series row asks for the Series tab. The page reset itself to Works as it opened. */
    @Test fun aPageOpenedOnSeriesShowsTheSeriesAndNeverAsksForTheWorks() {
        show(AuthorTab.Series, false)
        compose.onNodeWithText("The Hidden Cycle").assertExists()
        assertTrue(requests.none { it.toHttpUrl().encodedPath.endsWith("/works") })
    }

    @Test fun dashboardFandomsPreviewFiveAndOpenAo3sExactLink() {
        responseBody = { _, body ->
            org.jsoup.Jsoup.parse(body).apply {
                selectFirst("#user-fandoms ul")?.let { list ->
                    (3..6).forEach { list.append("<li><a href='/tags/Fandom$it/works?user_id=4242'>Fandom$it</a> ($it)</li>") }
                }
            }.outerHtml()
        }
        show(AuthorTab.Works, true)
        compose.onNodeWithText("Fandom6 (6)").assertDoesNotExist()
        compose.onNodeWithText("Expand").performClick()
        compose.onNodeWithText("Fandom6 (6)").assertExists()
        compose.onNodeWithText("Star Wars (12)").performClick()
        assertEquals(listOf("https://archiveofourown.org/tags/Star%20Wars/works?user_id=4242"), openedWeb)
        compose.onNodeWithText("Collapse").performClick()
        compose.onNodeWithText("Fandom6 (6)").assertDoesNotExist()
        assertEquals(1, requests.size)
    }

    /** A63 F26. The fixture's works have nothing to fold, so this checks the menu's own state. */
    @Test fun expandAllMenuTogglesToCollapseAllAndBack() {
        show(AuthorTab.Works, false)
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithText("Expand All").performClick()
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithText("Collapse All").performClick()
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithText("Expand All").assertExists()
    }

    @Test fun dashboardAboutActionOpensTheExactNativeAuthorRoute() {
        show(AuthorTab.Works, true)
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithText("About").performClick()
        assertEquals(listOf(AO3AuthorRoute("Avery_Archive")), openedAbout)
        assertEquals(1, requests.size)
    }

    @Test fun aboutDestinationLoadsTheNativeProfileWithoutAWorksRead() {
        show(AuthorTab.About, false)
        compose.onNodeWithText("Bio").assertExists()
        assertTrue(requests.any { it.toHttpUrl().encodedPath.endsWith("/profile") })
        assertTrue(indexReads().isEmpty())
    }

    private fun awaitText(text: String) {
        compose.waitUntil(15_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
        compose.waitForIdle()
    }
    private fun indexReads() = requests.filter { it.toHttpUrl().encodedPath.endsWith("/works") }
    private fun chooseColumn(title: String, current: String = "Date Updated") {
        compose.onNodeWithContentDescription("Sort by, $current, 9 fields").performClick()
        compose.onNodeWithText(title).performClick()
        compose.waitForIdle()
    }
    private fun openSheet() {
        compose.onNodeWithContentDescription("Sort and filter").performClick()
        awaitText("Sort and filter")
    }
    private fun apply() { compose.onNodeWithContentDescription("Apply").performClick(); compose.waitForIdle() }
    private fun dismiss() {
        compose.onNode(SemanticsMatcher.keyIsDefined(SemanticsActions.Dismiss))
            .performSemanticsAction(SemanticsActions.Dismiss) { it() }
        compose.waitForIdle()
    }

    @Test fun sortButtonHasIOSHelpAndActiveCountAfterApplyingSort() {
        show(AuthorTab.Works, false)
        val button = compose.onNodeWithContentDescription("Sort and filter")
        assertEquals("Sort and filter the works on this page", button.fetchSemanticsNode().config[SemanticsActions.OnClick].label)
        assertNull(button.fetchSemanticsNode().config.getOrNull(androidx.compose.ui.semantics.SemanticsProperties.StateDescription))
        openSheet()
        chooseColumn("Title")
        apply()
        awaitText("Page 1 of 3")
        button.assert(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.StateDescription, "1 active"))
        assertEquals("Sort and filter the works on this page", button.fetchSemanticsNode().config[SemanticsActions.OnClick].label)
    }

    @Test fun applyReadsOnlyPageOneOnceDismissDoesNothingAndNextPageKeepsChoice() {
        show(AuthorTab.Works, false)
        assertEquals(1, indexReads().size); assertEquals(2, requests.size) // Dashboard + Works only.
        compose.onNodeWithTag("Author profile").performScrollToNode(hasText("Load More"))
        compose.onNodeWithText("Load More").performClick()
        awaitText("Page 2 of 3")
        assertEquals("2", indexReads().last().toHttpUrl().queryParameter("page"))
        val before = requests.size
        openSheet()
        chooseColumn("Title")
        compose.onNode(hasText("Complete") and isSelectable()).performClick()
        dismiss()
        assertEquals(before, requests.size)
        openSheet()
        compose.onNodeWithContentDescription("Sort by, Date Updated, 9 fields").assertExists()
        compose.onNode(hasText("Any") and SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.Selected)).assertIsSelected()
        compose.onNodeWithContentDescription("Reset filters").assertIsNotEnabled()
        chooseColumn("Title")
        apply()
        awaitText("Page 1 of 3")
        assertEquals(before + 1, requests.size)
        val applied = indexReads().last().toHttpUrl()
        assertNull(applied.queryParameter("page"))
        assertEquals("title_to_sort_on", applied.queryParameter("work_search[sort_column]"))
        assertNull(applied.queryParameter("work_search[sort_direction]"))
        val first = compose.onNodeWithText("A Name Withheld").fetchSemanticsNode().boundsInRoot.top
        assertTrue(first < compose.onNodeWithText("Two Voices at Dawn").fetchSemanticsNode().boundsInRoot.top)
        openSheet(); apply() // Unchanged Apply costs no read, as Swift's sortToCommit.
        assertEquals(before + 1, requests.size)
        compose.onNodeWithTag("Author profile").performScrollToNode(hasText("Load More"))
        compose.onNodeWithText("Load More").performClick()
        awaitText("Page 2 of 3")
        assertEquals("title_to_sort_on", indexReads().last().toHttpUrl().queryParameter("work_search[sort_column]"))
        assertEquals("2", indexReads().last().toHttpUrl().queryParameter("page"))
    }

    @Test fun loadMoreKeepsEarlierWorksOnFailureAndAppendsWithoutDuplicatesOnRetry() {
        responseBody = { url, body ->
            if (url.toHttpUrl().queryParameter("page") == "2")
                body.replace("Two Voices at Dawn", "A second page work").replace("1001", "100199") else body
        }
        show(AuthorTab.Works, false)
        failSecondPage = true
        compose.onNodeWithTag("Author profile").performScrollToNode(hasText("Load More"))
        compose.onNodeWithText("Load More").performClick()
        awaitText("Try Loading More")
        compose.onNodeWithTag("Author profile").performScrollToNode(hasText("Two Voices at Dawn"))
        compose.onNodeWithText("Two Voices at Dawn").assertExists()
        failSecondPage = false
        compose.onNodeWithTag("Author profile").performScrollToNode(hasText("Try Loading More"))
        compose.onNodeWithText("Try Loading More").performClick()
        compose.waitForIdle()
        compose.onNodeWithTag("Author profile").performScrollToNode(hasText("A second page work"))
        compose.onNodeWithText("A second page work").assertExists()
        compose.onNodeWithTag("Author profile").performScrollToNode(hasText("Two Voices at Dawn"))
        compose.onNodeWithText("Two Voices at Dawn").assertExists()
        assertEquals(listOf("2", "2"), indexReads().drop(1).map { it.toHttpUrl().queryParameter("page") })
    }

    @Test fun completionAndDirectionApplyTogetherResetClearsOnlyLiveFacets() {
        show(AuthorTab.Works, false); openSheet()
        chooseColumn("Title")
        compose.onNodeWithText("Descending").performClick()
        compose.onNode(hasText("Complete") and isSelectable()).performClick()
        compose.onNodeWithText("Include Not Rated").assertExists()
        // Chapters is a page-local facet; a change/reset must leave the sort draft intact.
        compose.onNodeWithTag("AO3 filter form").performScrollToNode(hasText("Chapters"))
        compose.onNodeWithText("Chapters").performClick()
        compose.onNodeWithText("Single Chapter Only").performClick()
        compose.onNodeWithContentDescription("Reset filters").assertIsEnabled().performClick()
        compose.onNodeWithTag("AO3 filter form").performScrollToNode(hasContentDescription("Sort by, Title, 9 fields"))
        compose.onNodeWithContentDescription("Sort by, Title, 9 fields").assertExists()
        compose.onNode(hasText("Complete") and isSelectable()).assertIsSelected()
        assertEquals(2, requests.size)
        apply(); awaitText("Two Voices at Dawn")
        val url = indexReads().last().toHttpUrl()
        assertEquals("desc", url.queryParameter("work_search[sort_direction]"))
        assertEquals("T", url.queryParameter("work_search[complete]"))
        compose.onNodeWithText("A Name Withheld").assertDoesNotExist()
        assertEquals(3, requests.size)
    }

    @Test fun aLateAnswerForAnOlderAppliedSortCannotReplaceTheNewerList() {
        show(AuthorTab.Works, false)
        val gate = CompletableDeferred<Unit>()
        beforeResponse = { url ->
            if (url.toHttpUrl().queryParameter("work_search[sort_column]") == "title_to_sort_on") {
                withContext(NonCancellable) { gate.await() }
            }
        }
        responseBody = { url, html -> if (url.toHttpUrl().queryParameter("work_search[sort_column]") == "title_to_sort_on")
            html.replace("Two Voices at Dawn", "OLD SORT ANSWER") else html }
        openSheet(); chooseColumn("Title"); apply()
        compose.waitForIdle()
        compose.waitUntil(15_000) { indexReads().size == 2 }
        openSheet(); chooseColumn("Kudos", current = "Title"); apply()
        awaitText("A Name Withheld")
        val reads = requests.size
        compose.runOnIdle { gate.complete(Unit) }
        compose.waitForIdle()
        compose.onNodeWithText("OLD SORT ANSWER").assertDoesNotExist()
        assertEquals(reads, requests.size)
        assertEquals("kudos_count", indexReads().last().toHttpUrl().queryParameter("work_search[sort_column]"))
    }

    @Test fun anotherReadersPageUsesTheAppScopePaletteAcrossAllThemes() {
        show(AuthorTab.Works, false)
        for (mode in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { theme = mode }
            compose.waitForIdle()
            // Read the actual palette registered by subjectScreenWash, including the shell's wash.
            compose.runOnIdle { assertEquals(expectedPalette, washes.page?.palette) }
        }
    }

    @Test fun anotherReaderHasNoOwnWorksScopesAndTheFunnelOnlyBelongsToWorks() {
        show(AuthorTab.Works, false)
        compose.onNodeWithText("In collections").assertDoesNotExist()
        compose.onNodeWithText("Gifts").assertDoesNotExist()
        compose.onNodeWithContentDescription("Sort and filter").assertExists()
        assertEquals(2, requests.size)
        compose.onNodeWithText("Series", ignoreCase = true).performClick(); compose.waitForIdle()
        compose.onNodeWithContentDescription("Sort and filter").assertDoesNotExist()
        compose.onNodeWithText("Bookmarks", ignoreCase = true).performClick(); compose.waitForIdle()
        compose.onNodeWithContentDescription("Sort and filter").assertDoesNotExist()
    }

    @Test fun scopeIsAMenuAndChoosingAPseudChangesTheRoute() {
        show(AuthorTab.Works, false)
        compose.onNodeWithText("Scope").assertExists()
        compose.onNodeWithText("NightShift").assertDoesNotExist()
        compose.onNodeWithContentDescription("Author scope").performClick()
        compose.onNodeWithText("NightShift").performClick()
        // The reads run when the screen settles; waitUntil's polling did not let them run.
        compose.waitForIdle()
        assertTrue(indexReads().any { "/pseuds/NightShift/works" in it })
        compose.onNodeWithContentDescription("Author scope").performClick()
        compose.onNodeWithText("All Pseuds").performClick()
        compose.waitForIdle()
        // Back on the whole account: its list is kept from the first visit, not read again.
        compose.onNodeWithContentDescription("Author scope").assertTextContains("All Pseuds")
        assertEquals(1, indexReads().count { "/pseuds/" !in it })
    }

    @Test fun sortSheetWordsAndWrappingAcrossAllThemesAtDoubleTextSize() {
        var theme by mutableStateOf(KudosThemeMode.Light)
        compose.setContent {
            KudosTheme(theme) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                    SearchFilterSheet(AO3SearchFilters(), {}, {}, {}, {}, fandomContext = emptyList(), refine = true, canReset = false,
                        worksSort = AO3AuthorWorksSort())
                }
            }
        }
        for (mode in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { theme = mode }
            compose.onNodeWithText("Sort and filter").assertExists()
            compose.onNodeWithContentDescription("Apply").assertExists()
            compose.onNodeWithTag("AO3 filter form").performScrollToNode(hasText(WorksSortFooter))
            compose.onNodeWithText(WorksSortFooter).assertExists()
            val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithText(WorksSortFooter).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertTrue(layouts.isNotEmpty())
            layouts.forEach { assertFalse(it.didOverflowHeight); assertFalse(it.isLineEllipsized(it.lineCount - 1)) }
        }
    }
}
