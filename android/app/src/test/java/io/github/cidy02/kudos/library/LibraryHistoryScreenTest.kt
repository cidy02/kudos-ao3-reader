package io.github.cidy02.kudos.library

import android.app.Application
import android.content.Context
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.SemanticsMatcher
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
import io.github.cidy02.kudos.data.local.entity.ReadingSessionEntity
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
    private val activeId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"

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
        works.upsert(SavedWork(id = activeId, title = "Active", author = "A",
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
        directory.toFile().deleteOnExit()
    }

    private fun show(theme: KudosThemeMode = KudosThemeMode.Light, scale: Float = 1f) {
        val chrome = PushedShellChrome()
        compose.setContent {
            KudosTheme(themeMode = theme) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale), LocalPushedShellChrome provides chrome) {
                    Box {
                        LibraryScreen(repository = library, workRepository = works, settingsRepository = settings, readingLogDao = database.readingLogDao(),
                            onOpenWork = { opened += it }, onOpenReader = { opened += it }, section = kind.value)
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

    private val pageList = hasScrollAction() and
        SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.VerticalScrollAxisRange)

    private fun reach(text: String) {
        compose.onNode(pageList).performScrollToNode(hasText(text))
    }

    private fun selectScope(title: String) {
        reach(title)
        compose.onNodeWithText(title).performClick()
    }

    @Test fun timelineSwitchesScopesAndSummarizesChartInOneSentence() {
        show()
        awaitText("3 works · most recently read first")
        awaitText("This week")
        compose.onNodeWithContentDescription("This week: no reading").assertExists()
        reach("Nothing read this week.")
        compose.onNodeWithText("Nothing read this week.").assertExists()
        reach("ABANDONED")
        compose.onNodeWithText("ABANDONED").assertExists()
        reach("NO READING TIME RECORDED")
        compose.onNodeWithText("NO READING TIME RECORDED").assertExists()
        selectScope("Month")
        awaitText("Nothing read this month.")
        selectScope("Year")
        awaitText("Nothing read this year.")
        selectScope("Week")
        awaitText("This week")
    }

    @Test fun buttonWritesOverrideAndMergeClockAndRebucketsWithoutReload() {
        show()
        awaitText("3 works · most recently read first")
        reach("Move back to In progress")
        compose.onNodeWithText("Move back to In progress").performClick()
        compose.waitUntil(15_000) { compose.onAllNodesWithText("ABANDONED").fetchSemanticsNodes().isEmpty() }
        compose.onNodeWithText("ABANDONED").assertDoesNotExist()
        compose.onNodeWithText("Move back to In progress").assertDoesNotExist()
        val kept = runBlocking { works.getWork(dustyId)!! }
        assertTrue(kept.keepInProgressOverride)
        assertEquals(now, kept.lastModifiedAt)
        assertTrue(kept.lastModifiedAt!! > now.minusSeconds(10))
        assertEquals(now.minusSeconds(30 * 86_400L), kept.lastReadDate)
        assertTrue(opened.isEmpty())
    }

    @Test fun otherSectionsNeverShowTheTimelineScopeStrip() {
        show()
        for (other in LibrarySectionKind.entries.filter { it != LibrarySectionKind.History }) {
            compose.runOnIdle { kind.value = other }
            awaitText(other.title)
            for (title in listOf("Week", "Month", "Year")) compose.onNodeWithText(title).assertDoesNotExist()
        }
    }

    @Test fun timelineRowsKeepLongPressSelectionAndToolbar() {
        show()
        awaitText("3 works · most recently read first")
        reach("Dusty")
        compose.onNodeWithContentDescription("Dusty, by A").performTouchInput { longClick() }
        awaitText("Mark as Finished")
        compose.onNodeWithText("Select").performClick()
        awaitText("Select All")
        compose.onNodeWithText("Move back to In progress").assertDoesNotExist()
        reach("Dusty")
        compose.onAllNodes(isToggleable()).filter(isOn()).assertCountEquals(1)
        compose.onNodeWithText("Deselect All").assertDoesNotExist()
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
            compose.onAllNodesWithContentDescription("More").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithContentDescription("More").assertExists()
    }

    @Test fun bulkDeleteStillAsksWhenSingleWorkDeleteConfirmationIsOff() {
        runBlocking { settings.updateConfirmBeforeDelete(false) }
        show()
        reach("Dusty")
        compose.onNodeWithContentDescription("Dusty, by A").performTouchInput { longClick() }
        awaitText("Mark as Finished")
        compose.onNodeWithText("Select").performClick()
        awaitText("Select All")
        compose.onNodeWithText("Delete").performClick()
        awaitText("Delete 1 work?")
        assertFalse(runBlocking { works.getWork(dustyId)!!.isDeleted })
        compose.onNodeWithText("Cancel").performClick()
        assertFalse(runBlocking { works.getWork(dustyId)!!.isDeleted })
    }

    @Test fun historyRetainsItsRemoveSwipe() {
        show()
        awaitText("3 works · most recently read first")
        reach("Dusty")
        compose.onNodeWithContentDescription("Dusty, by A").performTouchInput { swipeLeft() }
        awaitText("Remove")
        compose.onNodeWithText("Remove").assertExists()
        assertFalse(runBlocking { works.getWork(dustyId)!!.isDeleted })
    }

    @Test fun storedSessionsDriveTimelineSittingsAndFavoritesFactsStrip() {
        runBlocking {
            val active = works.getWork(activeId)!!
            works.upsert(active.copy(chapters = "4/?"))
            for (index in 0..1) database.readingLogDao().upsertSession(
                ReadingSessionEntity(id = "fact-$index", workID = active.id,
                    startedAt = now.minusSeconds(3600L - index * 1800), endedAt = now.minusSeconds(1800L - index * 1800),
                    durationSeconds = 1800.0, endingProgress = 1.0, chapterCountAtVisit = 1,
                    didFinish = true, lastModifiedAt = now))
        }
        show()
        awaitText("1 work · 1 finished")
        reach("TODAY")
        compose.onNodeWithText("TODAY").assertExists()
        reach("Ch. 1 · 30 min · 2nd read")
        compose.onNodeWithText("Ch. 1 · 30 min · 2nd read").assertExists()

        compose.runOnIdle { kind.value = LibrarySectionKind.Favorites }
        awaitText("Favorites")
        for (mode in listOf("Ledger", "Detailed")) {
            compose.onNodeWithContentDescription("More").performClick()
            compose.onNodeWithText("Layout").performClick()
            compose.onNodeWithText(mode).performClick()
            reach("Read ×2")
            compose.onNodeWithText("1h").assertExists()
            compose.onNodeWithText("new chapter", substring = true).assertDoesNotExist()
        }
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithText("Layout").performClick()
        compose.onNodeWithText("Compact").performClick()
        reach("Active")
        compose.onNodeWithText("Read ×2").assertDoesNotExist()
    }

    @Test fun historyAndFavoritesFilterHelpAndScopeControlSelection() {
        show()
        for (section in listOf(LibrarySectionKind.History, LibrarySectionKind.Favorites)) {
            compose.runOnIdle { kind.value = section }
            awaitText(section.title)
            val action = compose.onNodeWithContentDescription("Filter").fetchSemanticsNode().config[SemanticsActions.OnClick]
            assertEquals("Filter the works in this section", action.label)
        }
        compose.runOnIdle { kind.value = LibrarySectionKind.History }
        awaitText("Reading History")
        selectScope("Month")
        compose.waitUntil(15_000) { compose.onAllNodes(hasText("Month") and isSelected()).fetchSemanticsNodes().isNotEmpty() }
        compose.onNode(hasText("Month") and isSelected()).assertHasClickAction()
    }

    @Test fun historyLayoutOffersDetailedAndLedgerAndCardExpansionOnlyInDetailed() {
        show()
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithText("Layout").performClick()
        compose.onNodeWithText("Compact").assertDoesNotExist()
        compose.onNodeWithText("Ledger").assertExists()
        compose.onNodeWithText("Detailed").performClick()
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithText("Expand All Cards").performClick()
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithText("Collapse All Cards").performClick()
    }

    @Test fun favoritesLayoutIncludesWorkingCompactAndOnlyDetailedOffersExpansion() {
        kind.value = LibrarySectionKind.Favorites
        show()
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithText("Layout").performClick()
        compose.onNodeWithText("Ledger").assertExists()
        compose.onNodeWithText("Detailed").assertExists()
        compose.onNodeWithText("Compact").performClick()
        reach("Active")
        compose.onNodeWithText("Active").assertExists()
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithText("Expand All Cards").assertDoesNotExist()
        compose.onNodeWithText("Layout").performClick()
        compose.onNodeWithText("Detailed").performClick()
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithText("Expand All Cards").performClick()
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithText("Collapse All Cards").performClick()
    }

    @Test fun privacyMenuUsesIOSWordsOnHistoryAndFavorites() {
        runBlocking {
            settings.updateHideMatureContent(true)
            works.upsert(SavedWork(id = "mature", title = "Mature work", author = "A", rating = "Mature",
                isSaved = true, isFavorite = true, lastReadDate = now))
        }
        show()
        for (section in listOf(LibrarySectionKind.History, LibrarySectionKind.Favorites)) {
            compose.runOnIdle { kind.value = section }
            awaitText(section.title)
            compose.onNodeWithContentDescription("More").performClick()
            compose.onNodeWithText("Show mature").assertExists()
            compose.onNodeWithText("Show mature works").assertDoesNotExist()
            compose.onNodeWithText("Show mature").performClick()
            compose.onNodeWithContentDescription("More").performClick()
            compose.onNodeWithText("Hide mature").assertExists()
            compose.onNodeWithText("Hide mature works").assertDoesNotExist()
            compose.onNodeWithText("Hide mature").performClick()
        }
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
        listOf("Week", "Month", "Year").forEach(::assertUnclipped)
        assertUnclipped("This week")
        assertUnclipped("ABANDONED")
        assertUnclipped("Move back to In progress")
    }

    @Test fun lightAccessibilityLabelsDoNotClip() = accessibility(KudosThemeMode.Light)
    @Test fun darkAccessibilityLabelsDoNotClip() = accessibility(KudosThemeMode.Dark)
    @Test fun sepiaAccessibilityLabelsDoNotClip() = accessibility(KudosThemeMode.Sepia)
    @Test fun oledAccessibilityLabelsDoNotClip() = accessibility(KudosThemeMode.Oled)
}
