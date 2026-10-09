package io.github.cidy02.kudos.settings

import android.app.Application
import android.content.Context
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.auth.*
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import io.github.cidy02.kudos.network.ao3.browse.FandomCatalogCache
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.search.SavedSearchRepository
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.converters.EpubBuilder
import java.nio.file.Files
import java.util.UUID
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
class PrivacyDataScreenTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var database: KudosDatabase
    private lateinit var works: WorkRepository
    private lateinit var scanner: LocalDataFootprintScanner
    private lateinit var files: WorkFileStore
    private lateinit var cache: FandomCatalogCache
    private lateinit var auth: AO3AuthRepository
    private val store = MemorySessionStore()
    private val cookies = MemoryCookieStore()
    private val root = Files.createTempDirectory("kudos-privacy-ui")
    private val theme = mutableStateOf(KudosThemeMode.Light)
    private val scale = mutableStateOf(1f)
    private val chrome = PushedShellChrome()

    @Before fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java).build()
        files = WorkFileStore(root)
        works = WorkRepository(database, files)
        cache = FandomCatalogCache(root.resolve("cache"))
        scanner = LocalDataFootprintScanner(database, works, root, root.resolve("cache"))
        auth = AO3AuthRepository(store, cookies) // No validator or HTTP dependency.
    }

    // The database is not closed here: the screen measures on another thread after every Clear, and
    // a test that ended while that was running failed with "connection is closed". It is in memory.
    @After fun tearDown() { root.toFile().deleteRecursively() }

    private fun show() {
        compose.setContent {
            KudosTheme(themeMode = theme.value) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale.value),
                    LocalPushedShellChrome provides chrome) {
                    PrivacyDataScreen(works, cache, KudosSettings.Defaults, auth, scanner)
                }
            }
        }
        await("Privacy")
        reach("Search history")
        await("0") // Empty collections/searches; actual measurement has finished.
    }

    private fun await(text: String) {
        compose.waitUntil(15_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
    }
    private fun reach(text: String) {
        compose.onAllNodes(hasScrollAction()).onFirst().performScrollToNode(hasText(text))
    }
    private fun click(text: String) { reach(text); compose.onNodeWithText(text).performClick() }

    private fun assertSectionsAndCopy() {
        for (heading in listOf("Stored on this device", "Clear", "AO3 session", "Read Aloud downloads")) {
            reach(heading.uppercase()); compose.onNodeWithText(heading.uppercase()).assertExists()
        }
        // Independent literals pin the Swift wording rather than sharing the screen's constants.
        for (text in listOf(
            "No ads or tracking, and no separate Kudos account",
            "Kudos connects to AO3. After you approve a Voice Pack download, it also connects to the service providing the pack. Your library, reading positions, tags, collections, and AO3 sign-in stay on this device.",
            "The sizes shown are measured on this device. Browse keeps fandom and category lists so it opens faster; it rebuilds them when needed, and your device may remove them to free space.",
            "Each option asks before it clears anything and tells you what will change on this device. Your AO3 reading history is separate; clear it from History or turn it off in AO3 Preferences.",
            "Your AO3 sign-in is kept only on this device and is never shared.",
            "Optional Voice Pack downloads stay separate from your reading data.",
            "Kudos never sends a work's text, spoken audio, your AO3 sign-in, saved works, reading history, usage information, or anything that identifies your account to the Voice Pack provider. The provider can see your IP address and basic details about the connection. Kudos tells you this before downloading a Voice Pack, and the installed voices stay on this device."
        )) {
            reach(text); compose.onNodeWithText(text).assertExists()
        }
        for (label in listOf("Free up space", "Clear reading positions", "Clear reading history", "Clear browse cache")) {
            reach(label); compose.onNodeWithText(label).assertExists()
        }
    }

    private suspend fun signedIn() {
        store.session = AO3Session("Reader", listOf(AO3StoredCookie(
            name = AO3StoredCookie.SessionCookieName, value = "local-test")))
        auth.restoreSession()
    }

    @Test fun emptyStorageHidesOnlyConditionalRowsAndIncludesAllFourSectionsAndVerbatimCopy() {
        show()
        for (label in listOf("Downloaded works", "Draft recovery", "Caches", "Reading positions", "Local collections", "Saved searches", "Search history")) {
            reach(label); compose.onNodeWithText(label).assertExists()
        }
        compose.onAllNodesWithText("Works you're reading").assertCountEquals(0)
        compose.onAllNodesWithText("Original files kept").assertCountEquals(0)
        compose.onAllNodesWithText("Imported fonts").assertCountEquals(0)
        reach("Downloaded works")
        for (label in listOf("Downloaded works", "Draft recovery", "Caches")) {
            compose.onNode(hasText("0 bytes") and hasAnyAncestor(hasTestTag("privacy-$label")),
                useUnmergedTree = true).assertExists()
        }
        assertSectionsAndCopy()
        reach("AO3 account")
        compose.onNodeWithText("Not signed in").assertExists()
        compose.onAllNodesWithText("Remove AO3 session").assertCountEquals(0)
        assertTrue(chrome.mounted)
    }

    @Test fun removingSessionRequiresConfirmationAndCancelKeepsTheSession() = runBlocking<Unit> {
        signedIn()
        show()
        assertSectionsAndCopy()
        reach("Signed in")
        compose.onNodeWithText("Reader").assertExists()
        click("Remove AO3 session")
        compose.onNodeWithText("Log out of AO3?").assertExists()
        compose.onNodeWithText("You will be signed out of AO3 on this device. Your Library, downloads, and queues stay.").assertExists()
        assertNotNull(store.session)
        assertFalse(cookies.cleared)
        compose.onNodeWithText("Cancel").performClick()
        assertNotNull(store.session)
        click("Remove AO3 session")
        compose.onNodeWithText("Log Out").performClick()
        compose.waitForIdle()
        compose.waitUntil(15_000) { store.session == null && cookies.cleared }
        await("Not signed in")
        await(PrivacyCopy.session + " Logged out of AO3.")
        compose.onAllNodesWithText("Remove AO3 session").assertCountEquals(0)
    }

    @Test fun expiredNoticeIsAppendedToTheSessionFootnote() = runBlocking<Unit> {
        signedIn()
        auth.sessionDidExpire()
        show()
        reach("AO3 account")
        compose.onNodeWithText("Not signed in").assertExists()
        reach(PrivacyCopy.session + " Your AO3 session expired. Please log in again.")
        compose.onNodeWithText(PrivacyCopy.session + " Your AO3 session expired. Please log in again.").assertExists()
    }

    @Test fun failedLogoutDoesNotReportSuccessOrLeaveTheSignedInRows() = runBlocking<Unit> {
        signedIn()
        store.failDelete = true
        show()
        click("Remove AO3 session")
        compose.onNodeWithText("Log Out").performClick()
        await("Not signed in")
        val expected = PrivacyCopy.session + " Signed out here, but this device couldn't fully remove the saved AO3 session. It won't be restored automatically — we'll keep retrying."
        reach(expected); await(expected)
        assertTrue(store.removalPending)
        assertTrue(cookies.cleared)
        compose.onAllNodesWithText("Remove AO3 session").assertCountEquals(0)
    }

    @Test fun clearRowsRetainTheirEffectsAndRescanDiskAndCounts() = runBlocking<Unit> {
        show()
        val positioned = SavedWork(id = UUID.randomUUID().toString(), title = "Finished reading copy", author = "Reader",
            sourceUrl = "https://archiveofourown.org/works/123", hasEpub = true, isFinished = true,
            lastSpineIndex = 2, lastScrollFraction = 0.5)
        files.writeWorkEpub(positioned.id, EpubBuilder.buildEpub(positioned.title, "<p>Local text</p>"))
        works.upsert(positioned)
        val kept = works.upsert(positioned.copy(id = UUID.randomUUID().toString(), title = "Kept copy", isSaved = true))
        files.writeWorkEpub(kept.id, EpubBuilder.buildEpub(kept.title, "<p>Kept local text</p>"))
        val history = works.upsert(positioned.copy(id = UUID.randomUUID().toString(), title = "History only", hasEpub = false))
        works.createCollection("Measured collection")
        SavedSearchRepository(database.savedSearchDao()).save("Measured search", AO3SearchFilters(query = "city"))
        cache.save(mapOf("TV" to FandomCatalogCache.Entry(listOf(AO3Fandom("Doctor Who", 42)), 1)))
        reach("Clear reading positions"); await("3 works")
        click("Clear reading positions")
        compose.onNodeWithText("Clear Reading Positions?").assertExists()
        compose.onNodeWithText("Clears your place in every work. Your works and their order in Continue Reading stay the same.").assertExists()
        compose.onNodeWithText("Clear 3 Positions").performClick()
        compose.waitForIdle()
        compose.waitUntil(15_000) { compose.onAllNodesWithText("0 works").fetchSemanticsNodes().isNotEmpty() }
        assertEquals(positioned.lastReadDate, works.getWork(positioned.id)!!.lastReadDate)
        assertEquals(0, works.getWork(positioned.id)!!.lastSpineIndex)
        reach("Saved searches")
        compose.waitUntil(15_000) { compose.onAllNodesWithText("1").fetchSemanticsNodes().size == 2 }
        compose.onAllNodesWithText("1").assertCountEquals(2)
        click("Free up space")
        compose.onNodeWithText("Free Up Space?").assertExists()
        compose.onNodeWithText("Removes the copies of works you've finished reading and didn't download, favourite or queue. Kudos gets them again from AO3 if you open them.").assertExists()
        compose.onNodeWithText("Free 1 File").performClick()
        compose.waitForIdle()
        compose.waitUntil(15_000) { compose.onAllNodesWithText("0 files").fetchSemanticsNodes().isNotEmpty() }
        assertFalse(files.workEpubExists(positioned.id))
        assertTrue(files.workEpubExists(kept.id))
        reach("Downloaded works")
        compose.waitUntil(15_000) {
            compose.onAllNodes(hasText("0 files") and hasAnyAncestor(hasTestTag("privacy-Free up space")),
                useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() &&
                compose.onAllNodesWithText("Works you're reading").fetchSemanticsNodes().isEmpty()
        }
        click("Clear reading history")
        compose.onNodeWithText("Clear Reading History?").assertExists()
        compose.onNodeWithText("Moves works that only remain in your reading history to Recently Deleted for 90 days. Your saved and downloaded works stay where they are, and you can download these works from AO3 again.").assertExists()
        compose.onNodeWithText("Clear 2 Works").performClick()
        // Not on "0 works": two rows already say that once the positions are cleared, so that wait
        // passed at once and the assertions raced the Clear.
        compose.waitForIdle()
        compose.waitUntil(15_000) { runBlocking { works.getWork(history.id)!!.isDeleted && works.getWork(positioned.id)!!.isDeleted } }
        compose.waitForIdle()
        assertTrue(works.getWork(history.id)!!.isDeleted)
        assertTrue(works.getWork(positioned.id)!!.isDeleted)
        assertFalse(works.getWork(kept.id)!!.isDeleted)
        click("Clear browse cache")
        compose.onNodeWithText("Clear Browse Cache?").assertExists()
        compose.onNodeWithText("Removes saved fandom and category lists. Your reading, saved works, and downloads stay untouched; Browse rebuilds the lists next time you open it.").assertExists()
        compose.onNodeWithText("Clear " + LocalStorageFootprint.formatted(scanner.measure().cacheBytes)).performClick()
        await("Browse cache cleared")
        assertTrue(cache.load().isEmpty())
        reach("Caches"); await("0 bytes")
    }

    @Test fun fourPalettesAtAccessibilityScaleHaveUnclippedTextAndTheScreenOwnsChrome() {
        show()
        for (mode in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { theme.value = mode; scale.value = 2f }
            for (text in listOf(PrivacyCopy.promiseTitle, "Downloaded works", "Clear reading positions", "AO3 account", PrivacyCopy.voice)) {
                reach(text)
                compose.waitForIdle()
                val layouts = mutableListOf<TextLayoutResult>()
                compose.onNodeWithText(text).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
                assertTrue(layouts.isNotEmpty())
                for (layout in layouts) {
                    assertFalse("$mode: $text", layout.didOverflowHeight)
                    if (layout.lineCount > 0) assertFalse(layout.isLineEllipsized(layout.lineCount - 1))
                }
            }
            assertTrue(chrome.mounted)
        }
    }
}
