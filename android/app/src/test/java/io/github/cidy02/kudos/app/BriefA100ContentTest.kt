package io.github.cidy02.kudos.app

import android.app.Application
import android.content.Context
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.InspectableValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.isDebugInspectorInfoEnabled
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.author.AuthorLoadMoreRow
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.home.HomeSectionKind
import io.github.cidy02.kudos.home.HomeSectionListScreen
import io.github.cidy02.kudos.library.*
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.WorkRepository
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** A100: actual filter callers under a different shell tint; no network clients. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h2400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
class BriefA100ContentTest {
    @get:Rule val compose = createComposeRule()
    @get:Rule val temporary = TemporaryFolder()
    private lateinit var database: KudosDatabase
    private lateinit var works: WorkRepository
    private lateinit var library: LibraryRepository
    private lateinit var queues: ReadingQueueRepository
    private lateinit var queue: ReadingQueue
    private lateinit var collection: WorkCollection
    private lateinit var tokens: KudosTokens
    private var mode by mutableStateOf(KudosThemeMode.Light)
    private var scale by mutableStateOf(1f)
    private val themes = listOf(KudosThemeMode.Light, KudosThemeMode.Sepia, KudosThemeMode.Dark, KudosThemeMode.Oled)
    private var oldInspector = false
    private enum class Screen { Library, Home, Queue, Collection }

    @Before fun setUp(): Unit = runBlocking {
        oldInspector = isDebugInspectorInfoEnabled
        isDebugInspectorInfoEnabled = true
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java).allowMainThreadQueries().build()
        works = WorkRepository(database, WorkFileStore(temporary.root.toPath()))
        queues = ReadingQueueRepository(database)
        library = LibraryRepository(works)
        val work = SavedWork(id = "10000000-0000-4000-8000-000000000001", title = "A100 fixture", author = "Writer",
            isSaved = true, hasEpub = true, lastReadDate = Instant.now(), legacyReaderProgress = 0.4)
        works.upsert(work)
        queue = queues.createQueue("A100 queue", hue = 0.47, keepsWorksOffline = false)
        queues.addWork(queue.id, work.id)
        collection = works.createCollection("A100 collection", hue = 0.62, colorHex = "#193B97")
        works.addWorkToCollection(work.id, collection.id)
    }

    @After fun tearDown() {
        database.close()
        isDebugInspectorInfoEnabled = oldInspector
    }

    private fun show(content: @Composable () -> Unit) {
        val chrome = PushedShellChrome()
        compose.setContent {
            KudosTheme(mode) {
                tokens = LocalKudosTokens.current
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale),
                    LocalPushedShellChrome provides chrome,
                    LocalShellWashes provides remember { ShellWashes() }) {
                    // MainScaffold replaces both page locals with the hero's tint. The app
                    // palette must survive that replacement, including when the theme changes.
                    SubjectPaletteTheme(SubjectPalette.fromHue(0.02, tokens.theme)) {
                        Box(Modifier.fillMaxSize()) {
                            content()
                            Row(Modifier.align(Alignment.TopEnd)) { chrome.trailingContent?.invoke(this) }
                        }
                    }
                }
            }
        }
    }

    private fun layout(text: String): TextLayoutResult {
        val results = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(text, useUnmergedTree = true)
            .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(results) }
        return results.single()
    }

    private fun assertInk(text: String, expected: Color) {
        val result = layout(text)
        assertEquals(text, expected, result.layoutInput.style.color)
        assertFalse("$text is ellipsized", (0 until result.lineCount).any(result::isLineEllipsized))
    }

    private fun checkSheet(screen: Screen) {
        val privacy = PrivacyGate()
        show {
            when (screen) {
                Screen.Library -> LibraryScreen(library, works, privacyGate = privacy,
                    section = LibrarySectionKind.ReadingNow, onOpenWork = {}, onOpenReader = {})
                Screen.Home -> HomeSectionListScreen(HomeSectionKind.ReadingNow, library, works, privacy,
                    metadataRefresh = null, onOpenWork = {}, onOpenReader = {})
                Screen.Queue -> QueuePageScreen(queues, queue.id, { 0L }, workRepository = works,
                    onOpenWork = {}, onOpenReader = {}, onManageQueue = {})
                Screen.Collection -> CollectionDetailScreen(collection.id, works, queueRepository = queues,
                    onOpenWork = {}, onOpenReader = {}, onCollectionDeleted = {})
            }
        }
        compose.waitUntil(15_000) { compose.onAllNodesWithContentDescription("Filter").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithContentDescription("Filter").performClick()
        for (theme in themes) for (fontScale in listOf(1f, 2f)) {
            compose.runOnIdle { mode = theme; scale = fontScale }
            compose.waitForIdle() // Read expected tokens only after the new theme has composed.
            // A queue or collection colour stays on the page. Filter controls take the app colour.
            assertInk("Default", tokens.accentInk)
            assertInk("Any rating", tokens.accentInk)
            val colors = compose.onNodeWithContentDescription("Done").fetchSemanticsNode().layoutInfo.getModifierInfo()
                .flatMap { (it.modifier as? InspectableValue)?.inspectableElements?.toList().orEmpty() }
                .filter { it.name == "color" }.map { it.value }
            assertTrue("$screen Done fill should be ${tokens.accent}, was $colors", tokens.accent in colors)
        }
        compose.onNodeWithText("Default").performClick()
        compose.onNodeWithText("Title", useUnmergedTree = true).performClick()
        compose.onNodeWithText("Title").assertExists()
        compose.onNodeWithContentDescription("Done").performClick()
        compose.onNodeWithText("Filters").assertDoesNotExist()
    }

    @Test fun librarySectionFiltersUseTheAppPaletteDespiteTheHeroTint() = checkSheet(Screen.Library)
    @Test fun homeSectionFiltersUseTheAppPaletteDespiteTheHeroTint() = checkSheet(Screen.Home)
    @Test fun queueFiltersKeepTheQueuePalette() = checkSheet(Screen.Queue)
    @Test fun collectionFiltersKeepThePickedCollectionPalette() = checkSheet(Screen.Collection)

    @Test fun loadMoreUsesPrimaryInkWithAndWithoutACardAndStillPagesAndDisablesWhileLoading() {
        var loading by mutableStateOf(false)
        var card by mutableStateOf(false)
        var page by mutableStateOf(1)
        var taps = 0
        show { AuthorLoadMoreRow(page, 4, loading, { taps++ }, showsCard = card) }
        for (showsCard in listOf(false, true)) for (theme in themes) for (fontScale in listOf(1f, 2f)) {
            compose.runOnIdle { card = showsCard; mode = theme; scale = fontScale; loading = false }
            compose.waitForIdle()
            assertInk("Load More", tokens.primaryInk)
            assertInk("Page 1 of 4", tokens.secondaryInk)
            compose.onNodeWithText("Load More").assertIsEnabled().performClick()
            val before = compose.runOnIdle { taps }
            compose.runOnIdle { loading = true }
            compose.waitForIdle()
            assertInk("Loading…", tokens.primaryInk)
            compose.onNodeWithText("Loading…").assertIsNotEnabled().performClick()
            compose.runOnIdle { assertEquals(before, taps) }
        }
        compose.runOnIdle { assertEquals(16, taps); loading = false; page = 4 }
        compose.onNodeWithText("Load More").assertDoesNotExist()
    }
}
