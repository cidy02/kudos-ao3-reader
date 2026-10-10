package io.github.cidy02.kudos.author

import android.app.Application
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
    private var beforeResponse: suspend (String) -> Unit = {}
    private var responseBody: (String, String) -> String = { _, body -> body }
    private val client = object : AO3Client {
        override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
            requests += url
            beforeResponse(url)
            val fixture = DemoNetwork.webFixture(url.toHttpUrl(), source)?.decodeToString() ?: error("Unbundled test address $url")
            // The real hero uses Coil; strip fixture images so even that independent loader has no URL.
            val html = org.jsoup.Jsoup.parse(fixture).apply { select("img").remove() }.outerHtml()
            return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), responseBody(url, html)))
        }
    }

    private fun show() {
        val chrome = PushedShellChrome()
        val repo = AO3AuthorRepository(publicClient = client, parseDispatcher = Dispatchers.Unconfined)
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CompositionLocalProvider(LocalPushedShellChrome provides chrome) {
                    Column {
                        Row { chrome.trailingContent?.invoke(this) }
                        AuthorProfileScreen("Avery_Archive", authorRepository = repo, onOpenWork = {})
                    }
                }
            }
        }
        awaitText("Two Voices at Dawn")
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

    @Test fun applyReadsOnlyPageOneOnceDismissDoesNothingAndNextPageKeepsChoice() {
        show()
        assertEquals(1, indexReads().size); assertEquals(2, requests.size) // Dashboard + Works only.
        compose.onNodeWithTag("Author profile").performScrollToNode(hasText("Next"))
        compose.onNodeWithText("Next").performClick()
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
        compose.onNodeWithTag("Author profile").performScrollToNode(hasText("Next"))
        compose.onNodeWithText("Next").performClick()
        awaitText("Page 2 of 3")
        assertEquals("title_to_sort_on", indexReads().last().toHttpUrl().queryParameter("work_search[sort_column]"))
        assertEquals("2", indexReads().last().toHttpUrl().queryParameter("page"))
    }

    @Test fun completionAndDirectionApplyTogetherResetClearsOnlyLiveFacets() {
        show(); openSheet()
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
        show()
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

    @Test fun funnelOnlyBelongsToWorksAndScopeTapReadsOnceWithoutReloadingHeader() {
        show()
        compose.onNodeWithText("In collections").performClick()
        compose.waitForIdle()
        compose.waitUntil(15_000) { requests.any { it.toHttpUrl().encodedPath.endsWith("/works/collected") } }
        assertEquals(3, requests.size)
        compose.onNodeWithText("In collections").performClick(); compose.waitForIdle()
        assertEquals(3, requests.size)
        compose.onNodeWithText("Series", ignoreCase = true).performClick(); compose.waitForIdle()
        compose.onNodeWithContentDescription("Sort and filter").assertDoesNotExist()
        compose.onNodeWithText("Bookmarks", ignoreCase = true).performClick(); compose.waitForIdle()
        compose.onNodeWithContentDescription("Sort and filter").assertDoesNotExist()
    }

    @Test fun sortSheetWordsAndWrappingAcrossAllThemesAtDoubleTextSize() {
        var theme by mutableStateOf(KudosThemeMode.Light)
        compose.setContent {
            KudosTheme(theme) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                    SearchFilterSheet(AO3SearchFilters(), {}, {}, {}, {}, refine = true, canReset = false,
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
