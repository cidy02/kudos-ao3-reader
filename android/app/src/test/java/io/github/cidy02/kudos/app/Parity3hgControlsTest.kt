package io.github.cidy02.kudos.app

import android.app.Application
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.compose.runtime.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.library.QueuePageScreen
import io.github.cidy02.kudos.library.QueueTagManager
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.library.queuePalette
import io.github.cidy02.kudos.reader.ReaderNoteEditor
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.ui.theme.*
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import kotlin.math.abs

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h2000dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class Parity3hgControlsTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var database: KudosDatabase
    private lateinit var works: WorkRepository
    private lateinit var queues: ReadingQueueRepository
    private val directory = Files.createTempDirectory("parity-3hg")
    private var visible by mutableStateOf(true)
    private var mode by mutableStateOf(KudosThemeMode.Light)
    private lateinit var tokens: KudosTokens
    private lateinit var view: View
    private var density = 1f
    private val themes = listOf(KudosThemeMode.Light, KudosThemeMode.Sepia, KudosThemeMode.Dark, KudosThemeMode.Oled)

    @Before fun setUp() {
        io.github.cidy02.kudos.network.ao3.DemoNetwork.resetForTests()
        io.github.cidy02.kudos.network.ao3.AO3PageCache.shared.clear()
        DebugShotRequests.clear()
        io.github.cidy02.kudos.library.QueueShowOnlyTag.name = null
        database = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), KudosDatabase::class.java)
            .allowMainThreadQueries().setQueryExecutor { it.run() }.setTransactionExecutor { it.run() }.build()
        works = WorkRepository(database, WorkFileStore(directory))
        queues = ReadingQueueRepository(database)
    }

    @After fun tearDown() {
        compose.runOnIdle { visible = false }
        compose.waitForIdle()
        database.close()
        directory.toFile().deleteRecursively()
        io.github.cidy02.kudos.library.QueueShowOnlyTag.name = null
        DebugShotRequests.clear()
    }

    private fun show(content: @Composable () -> Unit) {
        compose.setContent { if (visible) KudosTheme(mode) {
            tokens = LocalKudosTokens.current
            view = LocalView.current
            density = LocalDensity.current.density
            content()
        } }
    }

    private fun textColor(label: String): Color {
        val layouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(label, useUnmergedTree = true)
            .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        return layouts.single().layoutInput.style.color
    }

    @Test fun compactQueueCardsShareEachRowAndAnOddLastCardKeepsItsHalfSlot() {
        // One Up Next plus three In Line: exercises a full row and an odd last row.
        val queue = runBlocking {
            queues.createQueue("Compact", keepsWorksOffline = false).also { queue ->
                listOf("Next", "Sodium", "Winter", "Frozen").forEachIndexed { index, title ->
                    val work = SavedWork(id = "work-$index", title = title, author = "A")
                    works.upsert(work)
                    queues.addWork(queue.id, work.id, enqueueMissingEpub = false)
                }
            }
        }
        show { QueuePageScreen(queues, queue.id, { 0L }, workRepository = works,
            onOpenWork = {}, onOpenReader = {}, onManageQueue = {}) }
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Sodium").fetchSemanticsNodes().isNotEmpty() }
        compose.waitForIdle()
        // The clickable parents include the whole covers, rather than just their title text.
        val cards = listOf("Sodium", "Winter", "Frozen").map { title ->
            compose.onNode(hasClickAction() and hasAnyDescendant(hasText(title)), useUnmergedTree = true)
                .assertIsDisplayed().fetchSemanticsNode().boundsInRoot
        }
        val (first, second, last) = cards
        assertTrue(first.width > 0f && second.width > 0f)
        assertEquals(first.width, second.width, 1f)
        assertEquals(first.top, second.top, 1f)
        assertEquals(8f * density, second.left - first.right, 1f)
        assertTrue(last.top > first.top)
        assertEquals(first.left, last.left, 1f)
        assertEquals(first.width, last.width, 1f)
        compose.onNode(hasClickAction() and hasAnyDescendant(hasText("Sodium")), useUnmergedTree = true)
            .performTouchInput { swipeLeft() }
        compose.onNodeWithText("Remove").assertIsDisplayed()
        compose.onNodeWithText("Winter").assertIsDisplayed()
    }

    @Test fun tagManagerDialogsUseTheirQueuePaletteInEveryTheme() {
        val queue = runBlocking {
            queues.createQueue("Neon reread", colorHex = "#733AB5", tagNames = listOf("Rereads", "Comfort"))
                .also { queues.createQueue("Other queue") }
        }
        show { QueueTagManager(queues, queue, queuePalette(tokens.theme, queue), 0, {}, {}) }
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Rereads").fetchSemanticsNodes().isNotEmpty() }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            val expected = tokens.theme.accentInk(queuePalette(tokens.theme, queue).tint)
            compose.onNodeWithText("Rereads").performClick()
            compose.onNodeWithText("Rename").performClick()
            assertEquals(expected, textColor("Cancel"))
            compose.onNodeWithText("Name").performTextReplacement("Night reads")
            compose.waitUntil(5_000) { compose.onAllNodes(hasText("Save") and isEnabled()).fetchSemanticsNodes().isNotEmpty() }
            assertEquals(expected, textColor("Save"))
            compose.onNodeWithText("Cancel").performClick()
            compose.onNodeWithText("Rereads").performClick()
            compose.onNodeWithText("Copy tag to another queue").performClick()
            assertEquals(expected, textColor("Cancel"))
            compose.onNodeWithText("Cancel").performClick()
            compose.onNodeWithText("Rereads").performClick()
            compose.onNodeWithText("Remove from 0 works").performClick()
            assertEquals(expected, textColor("Cancel"))
            compose.onNodeWithText("Cancel").performClick()
        }
    }

    @Test fun noteDoneCheckUsesAccentInkInEveryTheme() {
        val mark = ReadingAnnotation(workID = "local", kindRaw = "highlight", colorRaw = "yellow")
        show { ReaderNoteEditor(mark, {}, {}, {}, {}) }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            val button = compose.onNodeWithContentDescription("Done").assertIsDisplayed().fetchSemanticsNode().boundsInRoot
            var matches = 0
            compose.runOnIdle {
                val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
                view.draw(Canvas(bitmap))
                for (y in button.top.toInt() until button.bottom.toInt()) {
                    for (x in button.left.toInt() until button.right.toInt()) {
                        val pixel = Color(bitmap.getPixel(x, y))
                        if (maxOf(abs(pixel.red - tokens.accentInk.red), abs(pixel.green - tokens.accentInk.green),
                                abs(pixel.blue - tokens.accentInk.blue)) < 0.012f) matches++
                    }
                }
                bitmap.recycle()
            }
            assertTrue("Done has accent pixels in $theme", matches > 5)
        }
    }
}
