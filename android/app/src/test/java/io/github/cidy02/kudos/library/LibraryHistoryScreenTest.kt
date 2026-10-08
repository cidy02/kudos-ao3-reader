package io.github.cidy02.kudos.library

import android.app.Application
import android.content.Context
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
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

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h2200dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class LibraryHistoryScreenTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var database: KudosDatabase
    private lateinit var works: WorkRepository
    private lateinit var settings: SettingsRepository
    private lateinit var library: LibraryRepository
    private val directory = Files.createTempDirectory("kudos-history-ui")
    private val settingsScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val kind = mutableStateOf(LibrarySectionKind.History)
    private val opened = mutableListOf<String>()
    private val now = Instant.ofEpochMilli(System.currentTimeMillis())
    private val dustyId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

    @Before fun setUp() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.getSharedPreferences("library-dashboard", Context.MODE_PRIVATE).edit().clear().commit()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java).allowMainThreadQueries().build()
        works = WorkRepository(database, WorkFileStore(directory), clock = { now })
        settings = SettingsRepository(PreferenceDataStoreFactory.create(scope = settingsScope,
            produceFile = { directory.resolve("settings.preferences_pb").toFile() }))
        settings.updateHideMatureContent(false)
        works.upsert(SavedWork(id = dustyId, title = "Dusty", author = "A", isSaved = true,
            dateAdded = now.minusSeconds(40 * 86_400L), lastModifiedAt = now.minusSeconds(10),
            lastReadDate = now.minusSeconds(30 * 86_400L), legacyReaderProgress = 0.4,
            workFandoms = listOf("Doctor Who (2005)")))
        works.upsert(SavedWork(id = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", title = "Active", author = "A",
            isSaved = true, isFavorite = true, lastReadDate = now, legacyReaderProgress = 0.5,
            workFandoms = listOf("Doctor Who")))
        works.upsert(SavedWork(id = "cccccccc-cccc-4ccc-8ccc-cccccccccccc", title = "Freed", author = "A",
            isSaved = true, hasEpub = false, lastReadDate = now.minusSeconds(10 * 86_400L),
            workFandoms = listOf("Naruto")))
        library = LibraryRepository(works, settings.settings)
    }

    @After fun tearDown() {
        database.close()
        settingsScope.cancel()
        // The folder is left for the system's temporary-files sweep. The last tap's write to
        // the settings file may still be on its way: deleting the folder under it failed a
        // test at random, and waiting for it here (on the test's main thread) hung the suite.
        directory.toFile().deleteOnExit()
    }

    private fun show(theme: KudosThemeMode = KudosThemeMode.Light, scale: Float = 1f) {
        val chrome = PushedShellChrome()
        compose.setContent {
            KudosTheme(themeMode = theme) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale), LocalPushedShellChrome provides chrome) {
                    Box {
                        LibraryScreen(repository = library, workRepository = works, settingsRepository = settings,
                            onOpenWork = { opened += it }, onOpenReader = { opened += it }, section = kind.value)
                        // Draw the real pushed screen toolbar supplied to the shell.
                        Row(Modifier.align(Alignment.TopEnd).testTag("history-toolbar")) { chrome.trailingContent?.invoke(this) }
                    }
                }
            }
        }
        awaitText(kind.value.title)
    }

    private fun awaitText(text: String) {
        compose.waitUntil(15_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
    }

    private fun reach(text: String) {
        compose.onNode(hasScrollAction()).performScrollToNode(hasText(text))
    }

    private fun selectGrouping(title: String) {
        reach(title)
        compose.onNodeWithText(title).performClick()
    }

    @Test fun tallyFollowsEveryGroupingAndZerosDisappear() {
        show()
        awaitText("3 works · most recently read first")
        selectGrouping("State")
        awaitText("3 works · 1 in progress · 1 abandoned")
        reach("READ, NOT FINISHED")
        compose.onNodeWithText("READ, NOT FINISHED").assertExists()
        selectGrouping("Fandom")
        awaitText("3 works")
        reach("DOCTOR WHO")
        compose.onNodeWithText("DOCTOR WHO").assertExists()
        selectGrouping("Flat")
        awaitText("3 works · most recently read first")
        reach("ALL")
        compose.onNodeWithText("ALL").assertExists()
        selectGrouping("Time")
        awaitText("3 works · most recently read first")
    }

    @Test fun buttonWritesOverrideAndMergeClockAndRebucketsWithoutReload() {
        show()
        selectGrouping("State")
        awaitText("3 works · 1 in progress · 1 abandoned")
        reach("Move back to In progress")
        compose.onNodeWithText("Move back to In progress").performClick()
        awaitText("3 works · 2 in progress")
        reach("IN PROGRESS")
        compose.onNodeWithText("IN PROGRESS").assertExists()
        compose.onNodeWithText("ABANDONED").assertDoesNotExist()
        compose.onNodeWithText("Move back to In progress").assertDoesNotExist()
        val kept = runBlocking { works.getWork(dustyId)!! }
        assertTrue(kept.keepInProgressOverride)
        assertEquals(now, kept.lastModifiedAt)
        assertTrue(kept.lastModifiedAt!! > now.minusSeconds(10))
        assertEquals(now.minusSeconds(30 * 86_400L), kept.lastReadDate)
        assertTrue(opened.isEmpty())
    }

    @Test fun otherSectionsNeverShowTheGroupingStrip() {
        show()
        for (other in LibrarySectionKind.entries.filter { it != LibrarySectionKind.History }) {
            compose.runOnIdle { kind.value = other }
            awaitText(other.title)
            for (title in listOf("Time", "State", "Fandom", "Flat")) compose.onNodeWithText(title).assertDoesNotExist()
        }
    }

    @Test fun groupedRowsKeepLongPressSelectionAndToolbar() {
        show()
        selectGrouping("State")
        awaitText("3 works · 1 in progress · 1 abandoned")
        reach("Dusty")
        compose.onNodeWithContentDescription("Dusty, by A").performTouchInput { longClick() }
        awaitText("Mark as Finished")
        compose.onNodeWithText("Select").performClick()
        awaitText("Select All")
        compose.onNodeWithText("Move back to In progress").assertDoesNotExist()
        selectGrouping("Flat")
        awaitText("3 works · most recently read first")
        reach("Dusty")
        compose.onAllNodes(isToggleable()).filter(isOn()).assertCountEquals(1)
        compose.onNodeWithText("Deselect All").assertDoesNotExist()
        // A different section hides Dusty: it must leave the selection, as a chip/filter would.
        compose.runOnIdle { kind.value = LibrarySectionKind.Favorites }
        awaitText("Favorites")
        compose.waitUntil(15_000) { compose.onAllNodes(isOn()).fetchSemanticsNodes().isEmpty() }
        compose.runOnIdle { kind.value = LibrarySectionKind.History }
        awaitText("Reading History")
        reach("Dusty")
        compose.onAllNodes(isOn()).assertCountEquals(0)
        compose.onNodeWithText("Select All").performClick()
        awaitText("Deselect All")
        compose.onAllNodesWithText("Done").assertCountEquals(2)
        compose.onNode(hasText("Done") and hasAnyAncestor(hasTestTag("history-toolbar"))).performClick()
        compose.waitUntil(15_000) {
            compose.onAllNodesWithContentDescription("More options").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithContentDescription("More options").assertExists()
    }

    @Test fun groupedHistoryRetainsItsRemoveSwipe() {
        show()
        selectGrouping("State")
        awaitText("3 works · 1 in progress · 1 abandoned")
        reach("Dusty")
        compose.onNodeWithContentDescription("Dusty, by A").performTouchInput { swipeLeft() }
        awaitText("Remove")
        compose.onNodeWithText("Remove").assertExists()
        assertFalse(runBlocking { works.getWork(dustyId)!!.isDeleted })
    }

    private fun assertUnclipped(text: String) {
        reach(text)
        val layouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(text).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        assertTrue(layouts.isNotEmpty())
        layouts.forEach { assertFalse(it.didOverflowHeight); assertFalse(it.isLineEllipsized(it.lineCount - 1)) }
    }

    private fun accessibility(theme: KudosThemeMode) {
        show(theme, scale = 2.4f)
        awaitText("3 works · most recently read first")
        listOf("Time", "State", "Fandom", "Flat").forEach(::assertUnclipped)
        selectGrouping("State")
        awaitText("3 works · 1 in progress · 1 abandoned")
        assertUnclipped("3 works · 1 in progress · 1 abandoned")
        assertUnclipped("ABANDONED")
        assertUnclipped("Move back to In progress")
    }

    @Test fun lightAccessibilityLabelsDoNotClip() = accessibility(KudosThemeMode.Light)
    @Test fun darkAccessibilityLabelsDoNotClip() = accessibility(KudosThemeMode.Dark)
    @Test fun sepiaAccessibilityLabelsDoNotClip() = accessibility(KudosThemeMode.Sepia)
    @Test fun oledAccessibilityLabelsDoNotClip() = accessibility(KudosThemeMode.Oled)
}
