package io.github.cidy02.kudos.author

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRepository
import io.github.cidy02.kudos.network.ao3.writing.AO3WorkFormRepository
import io.github.cidy02.kudos.network.ao3.writing.workFixture
import io.github.cidy02.kudos.network.ao3.writes.*
import io.github.cidy02.kudos.ui.theme.*
import io.github.cidy02.kudos.writing.*
import kotlinx.coroutines.*
import okhttp3.Request
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2600dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class OwnWorksScreenTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var setup: WorkFormTestSetup
    private val ids = listOf(995006L, 995008L, 995009L)
    private val recorder = BulkRecordingClient(ids)
    private val requests = mutableListOf<String>()
    private val source = FixtureSource { name -> workFixture(name).encodeToByteArray() }
    private val demo = DemoWorkSaves()
    private var theme by mutableStateOf(KudosThemeMode.Light)
    private var scale by mutableFloatStateOf(1f)
    private val title = "The Cartographer’s \"Second\" Tide & 星"
    private fun show(username: String = "AO3_Reader", signedIn: Boolean = true) {
        setup = runBlocking { workFormSetup(signedIn) }
        val client = object : AO3Client, AO3AuthenticatedClient {
            override fun username() = setup.auth.username()
            override fun sessionGeneration() = setup.auth.generation.value
            override suspend fun getAuthenticated(url: String) = get(url)
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                requests += url
                val html = demo.answer(Request.Builder().url(url).build(), source, null)?.second
                    ?: DemoNetwork.webFixture(url.toHttpUrl(), source)?.decodeToString() ?: error("Unbundled address $url")
                return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), org.jsoup.Jsoup.parse(html).apply { select("img").remove() }.outerHtml()))
            }
            override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> =
                recorder.postAuthenticated(url, formFields, headers)
        }
        val writes = AO3WriteRepository(client)
        val repo = AO3AuthorRepository(client, client, parseDispatcher = Dispatchers.Unconfined)
        val forms = AO3WorkFormRepository(client, setup.auth, parseDispatcher = Dispatchers.Unconfined)
        val chrome = PushedShellChrome()
        compose.setContent {
            KudosTheme(theme) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalPushedShellChrome provides chrome, LocalDensity provides Density(density.density, scale)) {
                    Column {
                        Row {
                            chrome.onBack?.let { back -> androidx.compose.material3.TextButton(onClick = back) { androidx.compose.material3.Text("Back") } }
                            chrome.trailingContent?.invoke(this)
                        }
                        AuthorProfileScreen(username, authorRepository = repo, authRepository = setup.auth, seriesWrites = writes,
                            workFormRepository = forms, onOpenWork = {})
                    }
                }
            }
        }
        if (signedIn && username == "AO3_Reader") {
            compose.waitUntil(15_000) { compose.onAllNodesWithContentDescription("Select Works").fetchSemanticsNodes().isNotEmpty() }
        } else {
            val expectedTitle = if (username == "AO3_Reader") title else "Two Voices at Dawn"
            compose.waitUntil(15_000) { compose.onAllNodesWithText(expectedTitle).fetchSemanticsNodes().isNotEmpty() }
        }
    }
    private fun idleRequests(count: Int) {
        compose.waitForIdle()
        compose.waitUntil(15_000) { requests.size >= count }
    }

    @Test fun ownActionsAndBulkBarAreAbsentForAnotherProfileAndSignedOutReader() {
        show("Avery_Archive")
        compose.onAllNodes(hasContentDescription("Actions for", substring = true)).assertCountEquals(0)
        compose.onNodeWithContentDescription("Menu").performClick()
        compose.onNodeWithText("Select Works").performClick()
        compose.onAllNodesWithText("Collections").assertCountEquals(0)
        compose.onAllNodesWithText("Visibility").assertCountEquals(0)
        compose.onAllNodesWithText("Delete").assertCountEquals(0)
        assertTrue(recorder.posts.isEmpty())
    }
    @Test fun signedOutOwnRouteHasNoWriterActionsOrWriterBulkBar() {
        show(signedIn = false)
        compose.onAllNodes(hasContentDescription("Actions for", substring = true)).assertCountEquals(0)
        compose.onNodeWithContentDescription("Menu").performClick()
        compose.onNodeWithText("Select Works").performClick()
        compose.onAllNodesWithText("Visibility").assertCountEquals(0)
        assertTrue(recorder.posts.isEmpty())
    }
    @Test fun selectingAndCancellingSendNothingAndDeleteRefusalKeepsSelectionThenConfirmationClears() {
        show(); idleRequests(2)
        val opening = requests.size
        compose.onNodeWithContentDescription("Select Works").performClick()
        compose.onNodeWithText("Delete").assertIsNotEnabled()
        compose.onNodeWithContentDescription("Select $title").performClick()
        compose.onNodeWithText("Delete").performClick()
        compose.onNodeWithText("Delete “$title”?").assertExists()
        compose.onNodeWithText("Cancel").performClick()
        assertEquals(opening, requests.size); assertTrue(recorder.posts.isEmpty())
        recorder.status = 422; recorder.reply = "<main id=main><div class='flash error'>The selected work could not be deleted.</div></main>"
        compose.onNodeWithText("Delete").performClick(); compose.onNodeWithText("Delete on AO3").performClick()
        compose.waitUntil(15_000) { compose.onAllNodesWithText("The selected work could not be deleted.").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("OK").performClick()
        compose.onNodeWithText("Edit 1").assertExists()
        assertEquals(1, recorder.posts.size)
        recorder.status = 200; recorder.reply = "<main id=main><div class='flash notice'>Your works were deleted.</div></main>"
        compose.onNodeWithText("Delete").performClick(); compose.onNodeWithText("Delete on AO3").performClick()
        compose.waitUntil(15_000) { compose.onAllNodesWithContentDescription("Select Works").fetchSemanticsNodes().isNotEmpty() }
        compose.onAllNodesWithText("Edit 1").assertCountEquals(0)
        idleRequests(opening + 4) // two preparation reads and the confirmed dashboard + works refresh
        assertEquals(opening + 4, requests.size); assertEquals(2, recorder.posts.size)
    }
    /** A saved bulk edit left the list as it was read before the Save: the rows kept the old rating. */
    @Test fun aSavedBulkEditReadsTheListAgainFromAO3() {
        show(); idleRequests(2)
        val dashboard = requests[0]; val works = requests[1]
        compose.onNodeWithContentDescription("Select Works").performClick()
        compose.onNodeWithContentDescription("Select $title").performClick()
        compose.onNodeWithText("Edit 1").performClick()
        compose.waitUntil(15_000) { compose.onAllNodesWithContentDescription("Save").fetchSemanticsNodes().isNotEmpty() }
        compose.onNode(hasScrollAction()).performScrollToNode(hasText("Add co-creators"))
        compose.onNodeWithText("Pseud").performTextInput("Writer")
        val formOpen = requests.size
        compose.onNodeWithContentDescription("Save").performClick()
        compose.waitUntil(15_000) { requests.drop(formOpen).let { dashboard in it && works in it } }
        compose.waitForIdle()
        compose.onNodeWithText("Edit 1").assertExists() // the selection stays, as on iOS
    }
    /** A work saved from its row's Edit went back to the list as it was read before the Save. */
    @Test fun aWorkSavedFromItsRowReadsTheListAgainFromAO3() {
        show(); idleRequests(2)
        val dashboard = requests[0]; val works = requests[1]
        compose.onNodeWithContentDescription("Actions for $title").performClick()
        compose.onNodeWithText("Edit").performClick()
        compose.waitUntil(15_000) { compose.onAllNodesWithContentDescription("Save").fetchSemanticsNodes().isNotEmpty() || compose.onAllNodesWithText("Save").fetchSemanticsNodes().isNotEmpty() }
        val formOpen = requests.size
        (compose.onAllNodesWithContentDescription("Save").fetchSemanticsNodes().isNotEmpty()).let { described ->
            if (described) compose.onNodeWithContentDescription("Save").performClick() else compose.onNodeWithText("Save").performClick()
        }
        compose.waitUntil(15_000) { requests.drop(formOpen).let { dashboard in it && works in it } }
        compose.waitForIdle()
        compose.onNodeWithContentDescription("Select Works").assertExists() // back on the list
        assertEquals(1, recorder.posts.size)
    }
    @Test fun rowEditAndTagsUseKnownIdWithNoDetailProbeAndBackRestoresChrome() {
        show(); idleRequests(2)
        compose.onNodeWithContentDescription("Actions for $title").performClick()
        compose.onNodeWithText("Edit").performClick()
        compose.waitUntil(15_000) { compose.onAllNodesWithContentDescription("Save").fetchSemanticsNodes().isNotEmpty() || compose.onAllNodesWithText("Save").fetchSemanticsNodes().isNotEmpty() }
        assertEquals(3, requests.size); assertTrue(requests.last().endsWith("/works/995006/edit"))
        assertTrue(recorder.posts.isEmpty())
        compose.onNodeWithText("Back").performClick()
        compose.onNodeWithContentDescription("Actions for $title").performClick()
        compose.onNodeWithText("Tags").performClick()
        compose.waitUntil(15_000) { compose.onAllNodesWithText("Edit tags").fetchSemanticsNodes().isNotEmpty() }
        idleRequests(4)
        assertEquals(4, requests.size); assertTrue(requests.last().endsWith("/works/995006/edit_tags"))
        compose.onNodeWithText("Back").performClick()
        compose.onNodeWithContentDescription("Select Works").assertExists()
        assertEquals(4, requests.size); assertTrue(recorder.posts.isEmpty())
    }
    @Test fun singleAndPluralDeleteNameExactlyTheWorksAndNoLibraryAction() {
        val one = listOf(bulkSummary(11).copy(title = "First 星"))
        assertEquals("Delete “First 星”?", ownWorksDeleteTitle(one))
        assertEquals("This permanently removes the work and its chapters, kudos, comments and bookmarks from AO3 for everyone.", ownWorksDeleteMessage(one))
        val three = one + bulkSummary(22).copy(title = "Second") + bulkSummary(33).copy(title = "Third")
        assertEquals("Delete 3 works?", ownWorksDeleteTitle(three))
        val message = ownWorksDeleteMessage(three)
        for (title in listOf("First 星", "Second", "Third")) assertTrue(message.contains("“$title”"))
        assertTrue(message.endsWith("and their chapters, kudos, comments and bookmarks from AO3 for everyone."))
    }
    @Test fun completeOwnRowHasNoChapterActionAndTagsStillOpenItsOwnForm() {
        show()
        compose.onNodeWithTag("Author profile").performScrollToNode(hasContentDescription("Actions for The Locked Lantern"))
        compose.onNodeWithContentDescription("Actions for The Locked Lantern").performClick()
        compose.onAllNodesWithText("Chapter").assertCountEquals(0)
        compose.onNodeWithText("Tags").performClick()
        idleRequests(3)
        assertTrue(requests.last().endsWith("/works/995008/edit_tags")); assertTrue(recorder.posts.isEmpty())
    }
    @Test fun chapterIsOffForCompleteAndOnForUnknownOrInProgressAndOwnershipNeverUsesPseud() {
        assertFalse(offersOwnWorkChapter(bulkSummary(1).copy(isComplete = true)))
        assertTrue(offersOwnWorkChapter(bulkSummary(1).copy(isComplete = false)))
        assertTrue(offersOwnWorkChapter(bulkSummary(1)))
        assertTrue(isOwnWorks("ao3_reader", "AO3_Reader"))
        assertFalse(isOwnWorks(null, "AO3_Reader")); assertFalse(isOwnWorks("Displayed pseud", "AO3_Reader"))
    }
    @Test fun bulkBarWrapsAtDoubleTextSizeAcrossAllFourThemes() {
        compose.setContent {
            KudosTheme(theme) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale)) {
                    OwnWorksBulkBar(3, false, {}, {})
                }
            }
        }
        for (mode in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { theme = mode; scale = 2f }
            compose.onNodeWithText("Edit 3").assertIsDisplayed()
            compose.onNodeWithText("Collections").assertIsDisplayed()
            compose.onNodeWithText("Visibility").assertIsDisplayed()
            compose.onNodeWithText("Delete").assertIsDisplayed()
            for (label in listOf("Edit 3", "Collections", "Visibility", "Delete")) {
                val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                compose.onNodeWithText(label).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { it(layouts) }
                layouts.forEach { assertFalse(it.didOverflowHeight); assertFalse(it.isLineEllipsized(it.lineCount - 1)) }
            }
        }
    }
}
