package io.github.cidy02.kudos.browse

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import android.content.Context
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseRepository
import io.github.cidy02.kudos.ui.subject.LocalShellWashes
import io.github.cidy02.kudos.ui.subject.ShellWashes
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.ui.theme.*
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import kotlinx.coroutines.CompletableDeferred
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1100dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class FandomResultsParityTest {
    @get:Rule val compose = createComposeRule()
    private val directory = Files.createTempDirectory("fandom-results")
    private val database = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), KudosDatabase::class.java)
        .allowMainThreadQueries().setQueryExecutor { it.run() }.setTransactionExecutor { it.run() }.build()
    private val works = WorkRepository(database, WorkFileStore(directory))
    private var answer = AO3Result.Success(AO3HttpResponse("https://archiveofourown.org/works", 200, emptyMap(), page())) as AO3Result<AO3HttpResponse>
    private var gate: CompletableDeferred<Unit>? = null
    private var requests = 0
    private var visible by mutableStateOf(true)
    private val client = object : AO3Client {
        override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
            requests++
            gate?.await()
            return answer
        }
    }
    private val repository = AO3BrowseRepository(client = client)
    private val importer = io.github.cidy02.kudos.works.WorkImporter(works,
        io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository(client),
        io.github.cidy02.kudos.network.ao3.work.AO3EpubDownloader(client), WorkFileStore(directory), directory.toFile())
    @After fun close() {
        compose.runOnIdle { visible = false }
        compose.waitForIdle()
        database.close()
        directory.toFile().deleteRecursively()
    }

    private val washes = ShellWashes()
    private lateinit var view: View
    private var mode by mutableStateOf(KudosThemeMode.Light)

    private fun show(tag: Boolean = false, fandom: String = "A fandom") {
        val chrome = PushedShellChrome()
        compose.setContent { if (visible) KudosTheme(mode) {
            view = LocalView.current
            CompositionLocalProvider(LocalPushedShellChrome provides chrome, LocalShellWashes provides washes) {
                Box {
                    FandomWorksScreen(fandom, works, {}, repository = repository, isTag = tag, workImporter = importer)
                    Row(Modifier.align(Alignment.TopEnd)) { chrome.trailingContent?.invoke(this) }
                }
            }
        } }
        // Parsing runs on Dispatchers.Default after the request has started.
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Original work").fetchSemanticsNodes().isNotEmpty() }
        assertEquals(1, requests)
    }

    @Test fun pagingKeepsUsableRowsClearsSelectionAndKeepsThemAfterFailure() {
        show()
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithText("Select").performClick()
        compose.onNodeWithText("Original work").performClick()
        compose.onNodeWithText("1 selected").assertExists()
        val pending = CompletableDeferred<Unit>()
        gate = pending
        answer = AO3Result.Failure(AO3Error.Forbidden)
        // Both top and bottom pagers have Next. Use the first one.
        compose.onAllNodesWithContentDescription("Next Page")[0].performClick()
        compose.waitUntil(5_000) { requests == 2 }
        compose.onNodeWithText("Original work").assertExists()
        compose.onNodeWithText("Select works").assertExists()
        compose.onAllNodesWithContentDescription("Next Page")[0].assertIsNotEnabled()
        pending.complete(Unit)
        compose.waitUntil(5_000) { compose.onAllNodesWithText(AO3Error.Forbidden.displayMessage()).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Original work").assertExists()
        compose.onAllNodesWithContentDescription("Next Page")[0].assertIsEnabled()
    }

    @Test fun aFailedFandomIndexRefreshKeepsTheExistingRows() {
        answer = AO3Result.Success(AO3HttpResponse("https://archiveofourown.org/media/Test/fandoms", 200, emptyMap(),
            """<ol class="fandom index group"><li><a class="tag" href="/tags/Original/works">Original fandom</a> (12)</li></ol>"""))
        compose.setContent { if (visible) KudosTheme(KudosThemeMode.Light) {
            FandomListScreen(io.github.cidy02.kudos.network.ao3.browse.AO3MediaCategory("Test", "/media/Test/fandoms"),
                {}, {}, {}, repository = repository)
        } }
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Original fandom").fetchSemanticsNodes().isNotEmpty() }
        val pending = CompletableDeferred<Unit>()
        gate = pending
        answer = AO3Result.Failure(AO3Error.Forbidden)
        compose.onNode(hasScrollToIndexAction()).performTouchInput {
            swipeDown(startY = top + 20f, endY = bottom - 20f, durationMillis = 700)
        }
        compose.waitUntil(5_000) { requests == 2 }
        compose.onNodeWithText("Original fandom").assertExists()
        compose.runOnIdle { pending.complete(Unit) }
        compose.waitForIdle()
        compose.onNodeWithText("Original fandom").assertExists()
        compose.onNodeWithText("Couldn't load fandoms").assertDoesNotExist()
    }

    @Test fun aGenericTagsFilterOffersTheFandomPicker() {
        show(tag = true)
        compose.onNodeWithContentDescription("Filter").performClick()
        compose.onNodeWithTag("AO3 filter form").performScrollToNode(hasText("Fandoms"))
        compose.onNodeWithText("Fandoms").assertHasClickAction().performClick()
        compose.onNodeWithText("Type above to search AO3 fandoms.").assertExists()
    }

    @Test fun fandomChipAndCountDescribeTheFixedFandomWhenTheResultHeadingNamesAnotherSubject() {
        answer = AO3Result.Success(AO3HttpResponse("https://archiveofourown.org/works", 200, emptyMap(),
            "<div id='main'><h2 class='heading'>1 - 1 of 12 Works in Star Wars - All Media Types</h2>" + page() + "</div>"))
        show(fandom = "Doctor Who")
        compose.onNodeWithText("Doctor Who").assertExists()
        compose.onNodeWithContentDescription("1 Filters").assertExists()
        compose.onNodeWithContentDescription("0 Filters").assertDoesNotExist()
    }

    @Test fun fandomWashUsesTheResultSubjectAndNotTheNavigationFandom() {
        answer = AO3Result.Success(AO3HttpResponse("https://archiveofourown.org/works", 200, emptyMap(),
            "<div id='main'><h2 class='heading'>1 - 1 of 12 Works in Star Wars - All Media Types</h2>" + page() + "</div>"))
        show(fandom = "Doctor Who")
        compose.runOnIdle { assertEquals(HomeFacts.coverHue("Star Wars - All Media Types"), washes.page!!.palette.hue, 0.000001) }
    }

    @Test fun tagWashAlsoUsesTheResultSubjectAndDoesNotInventAFandomFilter() {
        answer = AO3Result.Success(AO3HttpResponse("https://archiveofourown.org/works", 200, emptyMap(),
            "<div id='main'><h2 class='heading'>1 - 1 of 12 Works in Star Wars - All Media Types</h2>" + page() + "</div>"))
        show(tag = true, fandom = "Doctor Who")
        compose.onNodeWithContentDescription("0 Filters").assertExists()
        compose.onNodeWithText("Doctor Who").assertDoesNotExist()
        compose.runOnIdle { assertEquals(HomeFacts.coverHue("Star Wars - All Media Types"), washes.page!!.palette.hue, 0.000001) }
    }

    @Test fun fandomPagersUseTheFixedAppColour() = checkPagerPalette(false)
    @Test fun tagPagersUseTheFixedAppColour() = checkPagerPalette(true)
    private fun checkPagerPalette(tag: Boolean) {
        show(tag = tag, fandom = "Star Wars - All Media Types")
        for (theme in listOf(KudosThemeMode.Light, KudosThemeMode.Sepia, KudosThemeMode.Dark, KudosThemeMode.Oled)) {
            compose.runOnIdle { mode = theme }
            val next = compose.onAllNodesWithContentDescription("Next Page")[0].fetchSemanticsNode().boundsInRoot
            val palette = washes.page!!.palette
            val image = run {
                lateinit var bitmap: Bitmap
                compose.runOnIdle { bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888); view.draw(Canvas(bitmap)) }
                bitmap
            }
            val expectedInk = palette.controlInk
            val matches = (next.top.toInt() until next.bottom.toInt()).sumOf { y ->
                (next.left.toInt() until next.right.toInt()).count { x ->
                    val pixel = Color(image.getPixel(x, y))
                    kotlin.math.abs(pixel.red - expectedInk.red) < 0.012f &&
                        kotlin.math.abs(pixel.green - expectedInk.green) < 0.012f &&
                        kotlin.math.abs(pixel.blue - expectedInk.blue) < 0.012f
                }
            }
            image.recycle()
            assertTrue("Page next arrow uses the app ink ($theme)", matches > 3)
        }
    }

    companion object {
        private fun page() = """<ol class='pagination actions'><li><a href='?page=1'>1</a></li><li><a href='?page=2'>2</a></li></ol>
            <ol class='work index group'><li class='work blurb group' id='work_123'>
            <h4 class='heading'><a href='/works/123'>Original work</a> by <a rel='author'>Writer</a></h4>
            <h5 class='fandoms heading'><a class='tag'>A fandom</a></h5>
            <ul class='required-tags'><li><span class='rating-general-audience'><span class='text'>General Audiences</span></span></li></ul>
            <dl class='stats'><dd class='words'>1,000</dd><dd class='chapters'>1/1</dd></dl>
            <blockquote class='userstuff summary'>A visible summary</blockquote></li></ol>""".trimIndent()
    }
}
