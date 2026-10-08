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
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.work.AO3EpubDownloader
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import io.github.cidy02.kudos.network.ao3.work.WorkTagsRepository
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.WorkImporter
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import java.time.Instant
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
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
class FavoriteScopesScreenTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var database: KudosDatabase
    private lateinit var works: WorkRepository
    private lateinit var settings: SettingsRepository
    private lateinit var library: LibraryRepository
    private lateinit var importer: WorkImporter
    private lateinit var context: Context
    private val directory = Files.createTempDirectory("kudos-favorites-ui")
    private val settingsScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val kind = mutableStateOf<LibrarySectionKind?>(LibrarySectionKind.Favorites)
    private val theme = mutableStateOf(KudosThemeMode.Light)
    private val scale = mutableStateOf(1f)
    private val opened = mutableListOf<String>()
    private val client = RecordingClient()
    private val now = Instant.parse("2026-10-08T12:00:00Z")
    private val longTag = "Found Family with a very long label that needs several lines when text is large"

    private class RecordingClient : AO3Client {
        val requests = CopyOnWriteArrayList<String>()
        override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
            requests += url
            return AO3Result.Failure(AO3Error.Forbidden)
        }
    }

    @Before fun setUp() = runBlocking {
        LibraryFilterRequest.takeFandom(); LibraryFilterRequest.takeFreeform(); LibraryFilterRequest.takeUserTag()
        context = ApplicationProvider.getApplicationContext()
        context.getSharedPreferences("library-dashboard", Context.MODE_PRIVATE).edit().clear().commit()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java).allowMainThreadQueries().build()
        val files = WorkFileStore(directory)
        works = WorkRepository(database, files, tagsRepository = WorkTagsRepository(client), clock = { now })
        importer = WorkImporter(works, AO3WorkMetadataRepository(client), AO3EpubDownloader(client), files, context.cacheDir)
        settings = SettingsRepository(PreferenceDataStoreFactory.create(scope = settingsScope,
            produceFile = { directory.resolve("settings.preferences_pb").toFile() }))
        settings.updateHideMatureContent(false)
        for ((index, author) in listOf("alpha", "bravo", "charlie").withIndex()) {
            val tag = listOf("Slow Burn", "Fix-It", longTag)[index]
            val read = SavedWork(id = "read-$index", title = "Read $index", author = author, isFavorite = true, dateAdded = now.minusSeconds(index.toLong()),
                sourceUrl = "https://archiveofourown.org/works/${100 + index}", ao3WorkID = 100 + index,
                lastReadDate = now, workFandoms = listOf("Fandom $index"), workFreeforms = listOf(tag),
                authorIdentitiesJSON = """[{"kind":"registered","username":"account$index","displayName":"$author"}]""")
            works.upsert(read)
            if (index < 2) {
                works.upsert(read.copy(id = "unread-$index", title = "Waiting $index", lastReadDate = null,
                    isFavorite = false, isSaved = true, sourceUrl = "https://archiveofourown.org/works/${200 + index}"))
                database.readingLogDao().upsertSession(ReadingSessionEntity(id = "session-$index", workID = read.id,
                    startedAt = now.minusSeconds(600), endedAt = now, durationSeconds = 600.0,
                    didFinish = true, lastModifiedAt = now))
            }
        }
        library = LibraryRepository(works, settings.settings)
    }

    @After fun tearDown() {
        LibraryFilterRequest.takeFandom(); LibraryFilterRequest.takeFreeform(); LibraryFilterRequest.takeUserTag()
        settingsScope.cancel()
        database.close()
        directory.toFile().deleteOnExit()
    }

    private fun show() {
        val chrome = PushedShellChrome()
        compose.setContent {
            KudosTheme(themeMode = theme.value) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale.value), LocalPushedShellChrome provides chrome) {
                    Box {
                        LibraryScreen(repository = library, workRepository = works, workImporter = importer,
                            settingsRepository = settings, readingLogDao = database.readingLogDao(),
                            onOpenWork = { opened += "work:$it" }, onOpenReader = {}, section = kind.value,
                            onOpenAuthor = { opened += "author:$it" }, onFilterLibraryFandom = { opened += "fandom:$it" },
                            onFilterLibraryTag = { opened += "tag:$it" })
                        Row(Modifier.align(Alignment.TopEnd).testTag("favorites-toolbar")) { chrome.trailingContent?.invoke(this) }
                    }
                }
            }
        }
        awaitText("Favorites")
        awaitText("Works")
    }

    private fun awaitText(text: String) {
        compose.waitUntil(15_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
    }

    private fun reach(text: String) {
        compose.onAllNodes(hasScrollAction()).onFirst().performScrollToNode(hasText(text))
    }

    private fun selectScope(scope: FavoriteScope) {
        reach(scope.title)
        compose.onNodeWithText(scope.title).performClick()
        val noun = if (scope == FavoriteScope.Works) "works" else scope.title.lowercase()
        if (scope != FavoriteScope.Works) awaitText("3 $noun")
    }

    @Test fun eachScopeOpeningMakesZeroAo3RequestsIncludingRowsBelowTheViewport() {
        show()
        awaitText("Read 0")
        assertEquals("Works", 0, client.requests.size)
        for (scope in listOf(FavoriteScope.Authors, FavoriteScope.Fandoms, FavoriteScope.Tags)) {
            selectScope(scope)
            reach(if (scope == FavoriteScope.Authors) "charlie" else if (scope == FavoriteScope.Fandoms) "Fandom 2" else longTag)
            compose.waitForIdle()
            assertEquals("Opening and scrolling $scope", 0, client.requests.size)
            compose.onAllNodesWithText("Newest work").assertCountEquals(0)
            compose.onAllNodesWithText("With new work").assertCountEquals(0)
        }
    }

    @Test fun rowsUseIosWordingAndOpenOnlyTheirRealDestinations() {
        show()
        selectScope(FavoriteScope.Authors)
        awaitText("alpha")
        compose.onAllNodesWithText("1 unread work · 1 downloaded · 1 in Saved for Later").assertCountEquals(2)
        reach("charlie")
        compose.onNodeWithText("No unread works in your library").assertExists()
        reach("alpha")
        compose.onAllNodesWithContentDescription("Open author page").onFirst().performClick()
        assertEquals("author:account0", opened.last())
        selectScope(FavoriteScope.Fandoms)
        awaitText("Fandom 0")
        compose.onNodeWithText("Fandom 0").performClick()
        assertEquals("fandom:Fandom 0", opened.last())
        assertTrue(compose.onAllNodesWithText("1 work read · 1 favorited", substring = true).fetchSemanticsNodes().isNotEmpty())
        selectScope(FavoriteScope.Tags)
        awaitText("Slow Burn")
        compose.onNodeWithText("Slow Burn").performClick()
        assertEquals("tag:Slow Burn", opened.last())
        assertTrue(compose.onAllNodesWithText("1 work read carries this tag", substring = true).fetchSemanticsNodes().isNotEmpty())
        reach(longTag)
        compose.onNodeWithText("No unread works").assertExists()
        compose.onNodeWithText("Everything tagged this way has been opened").assertExists()
        compose.onAllNodesWithText("IN YOUR LIBRARY").assertCountEquals(3)
    }

    @Test fun workQuickFiltersStayStoredAndDoNotNarrowAggregatesAndToolbarRemains() {
        show()
        reach("Rereads"); compose.onNodeWithText("Rereads").performClick()
        compose.waitUntil(15_000) { compose.onAllNodesWithText("Read 0").fetchSemanticsNodes().isEmpty() }
        for (scope in listOf(FavoriteScope.Authors, FavoriteScope.Fandoms, FavoriteScope.Tags)) {
            selectScope(scope)
            compose.onAllNodesWithText("Rereads").assertCountEquals(0)
            compose.onAllNodesWithText("Offline").assertCountEquals(0)
            compose.onAllNodesWithText("WIP").assertCountEquals(0)
            compose.onNodeWithContentDescription("More options").performClick()
            compose.onNodeWithText("Select").assertExists()
            compose.onNodeWithText("Select").performClick()
            compose.onAllNodesWithText("Done").onFirst().performClick()
        }
        selectScope(FavoriteScope.Works)
        assertEquals("Rereads", context.getSharedPreferences("library-dashboard", Context.MODE_PRIVATE)
            .getString("library.favorites.quickFilter", null))
        compose.onAllNodesWithText("Read 0").assertCountEquals(0)
    }

    @Test fun changingScopeClearsWorkSelectionAndReturningDoesNotReselectHiddenWorks() {
        show()
        compose.onNodeWithContentDescription("More options").performClick()
        compose.onNodeWithText("Select").performClick()
        awaitText("Select All")
        compose.onNodeWithText("Select All").performClick()
        awaitText("Deselect All")
        compose.onNodeWithText("Delete").assertIsEnabled()
        selectScope(FavoriteScope.Authors)
        compose.waitUntil(15_000) { compose.onAllNodes(hasText("Delete") and isNotEnabled()).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Actions").assertIsNotEnabled()
        selectScope(FavoriteScope.Works)
        compose.onNodeWithText("Delete").assertIsNotEnabled()
    }

    @Test fun tagUnreadFilterAndEachAggregateEmptyStateAreTruthful() = runBlocking {
        show()
        selectScope(FavoriteScope.Tags)
        reach("Unread works"); compose.onNodeWithText("Unread works").performClick()
        awaitText("2 tags")
        compose.onAllNodesWithText(longTag).assertCountEquals(0)
        for (work in works.observeLibraryWorks().first()) works.upsert(work.copy(lastReadDate = now))
        awaitText("No unread works")
        compose.onNodeWithText("Every work in your library under these tags has been opened. Tap All to see them again.").assertExists()
        compose.onNodeWithText("All").performClick()
        awaitText("3 tags")
        for (work in works.observeLibraryWorks().first()) works.upsert(work.copy(lastReadDate = null))
        database.readingLogDao().observeSessions().first().forEach { database.readingLogDao().deleteSession(it.id) }
        for (scope in listOf(FavoriteScope.Authors, FavoriteScope.Fandoms, FavoriteScope.Tags)) {
            reach(scope.title); compose.onNodeWithText(scope.title).performClick()
            // The title is the same for all three: wait for this scope's own sentence.
            awaitText("These ${scope.title.lowercase()} come from works you have read and are ranked by your reading. You don't need to favorite them first.")
            compose.onNodeWithText("Nothing read yet").assertExists()
        }
    }

    @Test fun emptyWorksHidesTheStripAsIosDoesAndStoredAuthorsStillCountsUnstarredWorks() = runBlocking<Unit> {
        show()
        for (work in works.observeLibraryWorks().first()) works.upsert(work.copy(isFavorite = false))
        awaitText(LibrarySectionKind.Favorites.emptyMessage)
        compose.onAllNodesWithText("Authors").assertCountEquals(0)
        compose.onAllNodesWithText("Rereads").assertCountEquals(0)
        compose.onAllNodesWithContentDescription("Filter").assertCountEquals(0)
        settings.updateFavoriteScope(FavoriteScope.Authors)
        awaitText("3 authors")
        compose.onNodeWithText("alpha").assertExists()
        // iOS's outer toolbar depends on the Works shelf, not the aggregate tally.
        compose.onAllNodesWithContentDescription("More options").assertCountEquals(0)
    }

    @Test fun additionalTagRequestUsesTheLibraryDashboardPredicateRatherThanPersonalTags() {
        show(); selectScope(FavoriteScope.Tags)
        compose.runOnIdle {
            LibraryFilterRequest.requestFreeform("Slow Burn")
            kind.value = null
        }
        awaitText("READING NOW")
        reach("Read 0")
        assertTrue(compose.onAllNodesWithText("Read 0").fetchSemanticsNodes().isNotEmpty())
        compose.waitUntil(15_000) { compose.onAllNodesWithText("Read 1").fetchSemanticsNodes().isEmpty() }
        assertNull(LibraryFilterRequest.takeFreeform())
        assertEquals(0, client.requests.size)
    }

    @Test fun scopeStripAppearsOnlyInFavoritesEvenWhenItsStoredChoiceIsTags() {
        show(); selectScope(FavoriteScope.Tags)
        for (section in listOf(LibrarySectionKind.ReadingNow, LibrarySectionKind.SavedForLater,
            LibrarySectionKind.Finished, LibrarySectionKind.Downloaded, LibrarySectionKind.History)) {
            compose.runOnIdle { kind.value = section }
            awaitText(section.title)
            compose.onAllNodesWithText("Authors").assertCountEquals(0)
            compose.onAllNodesWithText("Tags").assertCountEquals(0)
        }
    }

    @Test fun longRowsStayReadableOnEveryPaletteAtAccessibilityScale() {
        show(); selectScope(FavoriteScope.Tags)
        for (mode in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { theme.value = mode; scale.value = 2f }
            reach(longTag)
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText(longTag).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertTrue(layouts.isNotEmpty())
            assertFalse(layouts.first().didOverflowHeight)
            assertFalse(layouts.first().isLineEllipsized(layouts.first().lineCount - 1))
            reach("Unread works")
            compose.onNodeWithText("Unread works").assertExists()
        }
    }
}
