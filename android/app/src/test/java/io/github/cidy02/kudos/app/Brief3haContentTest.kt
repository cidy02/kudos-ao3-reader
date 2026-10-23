package io.github.cidy02.kudos.app

import android.app.Application
import androidx.compose.material3.Surface
import io.github.cidy02.kudos.account.PreferenceHelpSheet
import io.github.cidy02.kudos.network.ao3.preferences.*
import io.github.cidy02.kudos.network.ao3.writing.AO3BulkEditChanges
import io.github.cidy02.kudos.network.ao3.writing.recovery.WritingTextRecovery
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.junit.rules.TemporaryFolder
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.series.AO3SeriesRepository
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.ui.theme.*
import io.github.cidy02.kudos.writing.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Exercises real content and paints in the activity; no sheet/dialog windows or sockets. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class Brief3haContentTest {
    @get:Rule val compose = createComposeRule()
    @get:Rule val temporary = TemporaryFolder()
    private var mode by mutableStateOf(KudosThemeMode.Light)
    private lateinit var view: View
    private lateinit var tokens: KudosTokens
    private val washes = ShellWashes()
    private val themes = listOf(KudosThemeMode.Light, KudosThemeMode.Sepia, KudosThemeMode.Dark, KudosThemeMode.Oled)
    private fun show(scale: Float = 1f, content: @Composable () -> Unit) {
        compose.setContent { KudosTheme(mode) {
            view = LocalView.current
            tokens = LocalKudosTokens.current
            CompositionLocalProvider(LocalShellWashes provides washes,
                LocalDensity provides Density(LocalDensity.current.density, scale)) {
                Box(Modifier.fillMaxSize().background(tokens.background)) { content() }
            }
        } }
    }
    private fun assertPixel(expected: Color, point: Offset) {
        var actual = Color.Unspecified
        compose.runOnIdle {
            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(Canvas(bitmap))
            actual = Color(bitmap.getPixel(point.x.toInt(), point.y.toInt()))
            bitmap.recycle()
        }
        assertEquals(expected.red, actual.red, 0.012f)
        assertEquals(expected.green, actual.green, 0.012f)
        assertEquals(expected.blue, actual.blue, 0.012f)
    }
    private fun await(text: String) {
        compose.waitUntil(20_000) { compose.onAllNodesWithText(text, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        compose.waitForIdle()
    }

    @Test fun directSeriesReadsItsOwnFactsAndKeepsZeroFiguresOnNeutralGround() {
        val url = "https://archiveofourown.org/series/321"
        val requests = mutableListOf<String>()
        val repo = AO3SeriesRepository(client = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                requests += url
                return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), seriesFixture("ao3_demo_dawn_series")))
            }
        }, pageCache = AO3PageCache())
        show { SeriesWorksScreen(url, repo, {}) }
        await("The Dawn Cycle")
        listOf("62 bookmarks", "Restricted", "08 Jul 2026").forEach {
            compose.onAllNodesWithText(it, useUnmergedTree = true).onFirst().assertExists()
        }
        listOf("0 comments", "0 kudos", "0 bookmarks", "0 hits").forEach {
            compose.onAllNodesWithContentDescription(it, useUnmergedTree = true).onFirst().assertExists()
        }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            compose.runOnIdle { assertNull(washes.page) }
            assertPixel(tokens.background, Offset(4f, 40f))
            val work = compose.onNodeWithContentDescription("First Light, by Avery Writes").fetchSemanticsNode().boundsInRoot
            assertPixel(tokens.cardFill, Offset(work.center.x, work.top + 3f))
        }
        assertEquals(listOf(url), requests)
    }

    @Test fun seriesSelectionAlsoUsesNeutralCardsAndStillToggles() {
        val work = runBlocking {
            val repo = AO3SeriesRepository(client = object : AO3Client {
                override suspend fun get(url: String, headers: Map<String, String>) =
                    AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), seriesFixture("ao3_demo_dawn_series")))
            })
            (repo.seriesPage("https://archiveofourown.org/series/321") as AO3Result.Success).value.works.first()
        }
        var selected by mutableStateOf(false)
        show { SeriesWorkRow(work, true, selected, { selected = !selected }, {}, false) }
        val card = compose.onNodeWithContentDescription("First Light, by Avery Writes").fetchSemanticsNode().boundsInRoot
        assertPixel(tokens.cardFill, Offset(card.center.x, card.top + 3f))
        compose.onNodeWithContentDescription("First Light, by Avery Writes").performClick()
        compose.runOnIdle { assertTrue(selected) }
    }

    @Test fun blankKickerHasNeitherAnEmptyLabelNorAnOrphanRule() {
        show { SubjectHeaderBlock("", "Check Availability", tokens.scopePalette, Modifier.testTag("Header")) }
        val header = compose.onNodeWithTag("Header").fetchSemanticsNode().boundsInRoot
        val title = compose.onNodeWithText("Check Availability").fetchSemanticsNode().boundsInRoot
        assertEquals("Title starts the header; no kicker or rule occupies its top", header.top, title.top, 0.1f)
    }

    @Test fun collectionNameHasOneLabelBesideAddAndAddsOnlyOneTrimmedName() {
        var changes by mutableStateOf(AO3BulkEditChanges(workIDs = emptyList()))
        var scale by mutableFloatStateOf(1f)
        show {
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, scale)) {
                BulkOptionsScreen(BulkPicker("Add to collections", "collections", "names"), emptyList(), changes,
                    { changes = it(changes) }, {})
            }
        }
        for (size in listOf(1f, 2f)) {
            compose.runOnIdle { scale = size }
            compose.onAllNodesWithText("Collection name", useUnmergedTree = true).assertCountEquals(1)
            val input = compose.onNodeWithContentDescription("Collection name")
            compose.onNodeWithText("Add").assertIsNotEnabled()
            val field = input.fetchSemanticsNode().boundsInRoot
            val add = compose.onNodeWithText("Add").fetchSemanticsNode().boundsInRoot
            assertTrue("Add shares the field's row", add.top < field.bottom && add.bottom > field.top)
            assertTrue("Add follows the field", add.left >= field.right)
            input.performTextInput("  Winter  ")
            compose.onNodeWithText("Add").performClick()
            compose.runOnIdle { assertEquals(listOf("Winter"), changes.collectionsToAdd) }
            input.assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString("")))
        }
    }

    @Test fun preferenceHelpPassesTheSheetGroundToItsSheetInEveryTheme() {
        var sheetGround = Color.Unspecified
        show { PreferenceHelpSheet(AO3PreferenceHelpRef("Help", "https://archiveofourown.org/help/preferences"),
            AO3Result.Success(AO3PreferenceHelpContent("Help", listOf(AO3PreferenceHelpEntry("Topic", "Instructions")), "Footer", "")),
            {}, {}, {}, presentSheet = { ground, content ->
                sheetGround = ground
                Surface(color = ground, modifier = Modifier.fillMaxWidth().testTag("Sheet")) { content() }
            }) }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            compose.onNodeWithText("Instructions").assertExists()
            compose.onNodeWithText("Footer").assertExists()
            compose.runOnIdle { assertEquals(tokens.sheetGround, sheetGround) }
            val sheet = compose.onNodeWithTag("Sheet").fetchSemanticsNode().boundsInRoot
            assertPixel(tokens.sheetGround, Offset(sheet.center.x, sheet.top + 2f))
        }
    }

    @Test fun recoveryPassesTheSheetGroundToItsSheetAndRestoreKeepsWorking() {
        val store = WritingTextRecovery(temporary.newFolder().toPath())
        val key = store.fileURL("Writer", "work:17", "content")
        store.save("Recovered text", "Original", store.sessionURL(key))
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        lateinit var session: WritingEditorSession
        var sheetGround = Color.Unspecified
        try {
            show {
                val context = androidx.compose.ui.platform.LocalContext.current
                session = remember { WritingEditorSession(WritingNativeTextField(context, "Original"), "Original", store,
                    "Writer", "work:17", "content", scope, android.os.SystemClock::uptimeMillis) }
                WritingRecoverySheet(session, presentSheet = { ground, content ->
                    sheetGround = ground
                    Surface(color = ground, modifier = Modifier.fillMaxWidth().testTag("Sheet")) { content() }
                })
            }
            await("Recovered text")
            for (theme in themes) {
                compose.runOnIdle { mode = theme }
                compose.onNodeWithText("Recovered text").assertExists()
                compose.runOnIdle { assertEquals(tokens.sheetGround, sheetGround) }
                val sheet = compose.onNodeWithTag("Sheet").fetchSemanticsNode().boundsInRoot
                assertPixel(tokens.sheetGround, Offset(sheet.center.x, sheet.top + 2f))
            }
            compose.onNodeWithText("Restore local copy").performScrollTo().performClick()
            compose.runOnIdle { assertEquals("Recovered text", session.editor.takeText()); assertTrue(session.recoveries.isEmpty()) }
        } finally { scope.cancel() }
    }

}
