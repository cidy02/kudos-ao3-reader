package io.github.cidy02.kudos.account

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1600dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AccountShortcutsScreenTest {
    @get:Rule val compose = createComposeRule()
    private val dir = Files.createTempDirectory("shortcuts-test").toFile()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val repo = SettingsRepository(PreferenceDataStoreFactory.create(scope = scope,
        produceFile = { File(dir, "settings.preferences_pb") }))

    @After fun close() { scope.cancel(); dir.deleteRecursively() }

    private fun waitText(text: String) {
        compose.waitUntil(15_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
        compose.waitForIdle()
    }

    @Test fun seeAllPushesRealEditorAddRemoveReorderResetAndDoneUpdateCollectedGrid() {
        runBlocking<Unit> { repo.updateAccountShortcuts(listOf(AccountShortcut.Inbox, AccountShortcut.Drafts)) }
        val chrome = PushedShellChrome()
        val opened = mutableListOf<AccountShortcut>()
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CompositionLocalProvider(LocalPushedShellChrome provides chrome) {
                    var editor by remember { mutableStateOf(false) }
                    val chosen by repo.accountShortcuts.collectAsState(initial = AccountShortcutStore.defaults)
                    Column {
                        Row { chrome.trailingContent?.invoke(this) }
                        if (editor) AccountShortcutsEditor(repo) { editor = false }
                        else AccountHubShortcuts(chosen, emptyMap(), { editor = true }, { opened += it })
                    }
                }
            }
        }
        waitText("Inbox")
        assertTrue(compose.onNodeWithText("Inbox").fetchSemanticsNode().boundsInRoot.left <
            compose.onNodeWithText("Drafts").fetchSemanticsNode().boundsInRoot.left)
        compose.onNodeWithContentDescription("See all Shortcuts").performClick()
        // The editor reads the store before it draws its rows: asserting at once failed on a loaded machine.
        compose.waitUntil(15_000) { compose.onAllNodesWithContentDescription("Remove Inbox").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithContentDescription("Remove Inbox").assertExists().performClick()
        compose.waitUntil(15_000) {
            compose.onAllNodesWithContentDescription("Add Inbox").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithContentDescription("Add Inbox").performScrollTo().performClick()
        compose.waitUntil(15_000) {
            compose.onAllNodesWithContentDescription("Move Inbox up").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithContentDescription("Move Inbox up").performScrollTo().performClick()
        compose.waitForIdle()
        compose.waitUntil(15_000) {
            runBlocking { repo.accountShortcuts.first() } == listOf(AccountShortcut.Inbox, AccountShortcut.Drafts)
        }
        compose.onNodeWithContentDescription("Done").performClick()
        waitText("Inbox")
        compose.onNodeWithText("Drafts").performClick()
        assertEquals(listOf(AccountShortcut.Drafts), opened)
        compose.onNodeWithContentDescription("See all Shortcuts").performClick()
        compose.onNodeWithTag("Account shortcuts editor").performScrollToNode(hasText("Reset to Default"))
        compose.onNodeWithText("Reset to Default").performClick()
        compose.waitForIdle()
        compose.waitUntil(15_000) { runBlocking { repo.accountShortcuts.first() } == AccountShortcutStore.defaults }
        compose.onNodeWithTag("Account shortcuts editor").performScrollToNode(hasText("Reset to Default"))
        compose.onNodeWithText("Reset to Default").assertIsNotEnabled()
        compose.onNodeWithText(AccountShortcutStore.emptyFooter).assertDoesNotExist()
        compose.onNodeWithContentDescription("Done").performClick()
        waitText("Dashboard")
        compose.onNodeWithText("Inbox").assertDoesNotExist()
    }

    @Test fun gridRedrawsOnAnExternalPreferenceUpdate() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                val chosen by repo.accountShortcuts.collectAsState(initial = AccountShortcutStore.defaults)
                AccountHubShortcuts(chosen, emptyMap(), {}, {})
            }
        }
        waitText("Dashboard")
        runBlocking<Unit> { repo.updateAccountShortcuts(listOf(AccountShortcut.MarkedForLater, AccountShortcut.Preferences)) }
        waitText("Marked for Later")
        compose.onNodeWithText("Preferences").assertExists()
        compose.onNodeWithText("Dashboard").assertDoesNotExist()
    }

    /** Removing the last shortcut used to bring the six defaults back, on iOS too (audit A27-11). */
    @Test fun footerOnlyDrawsForEmptyContentAndLastRemovalThroughStoreStaysEmpty() {
        compose.setContent { KudosTheme(KudosThemeMode.Light) { AccountShortcutsEditorContent(emptyList(), {}, {}) } }
        compose.onNodeWithText(AccountShortcutStore.emptyFooter).assertExists()
        compose.onNodeWithText("Not on the grid", ignoreCase = true).assertExists()
        runBlocking<Unit> {
            repo.updateAccountShortcuts(listOf(AccountShortcut.Inbox))
            repo.updateAccountShortcuts(repo.accountShortcuts.first().filterNot { it == AccountShortcut.Inbox })
            assertEquals(emptyList<AccountShortcut>(), repo.accountShortcuts.first())
        }
    }

    @Test fun anEmptyGridHidesItsHeaderAndAnAllChosenEditorHasNoAvailableSection() {
        var editor by mutableStateOf(false)
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                if (editor) AccountShortcutsEditorContent(AccountShortcut.entries, {}, {})
                else AccountHubShortcuts(emptyList(), emptyMap(), {}, {})
            }
        }
        compose.onNodeWithText("Shortcuts", ignoreCase = true).assertDoesNotExist()
        compose.onNodeWithContentDescription("See all Shortcuts").assertDoesNotExist()
        compose.runOnIdle { editor = true }
        compose.onNodeWithTag("Account shortcuts editor").performScrollToNode(hasText("Reset to Default"))
        compose.onNodeWithText("Not on the grid", ignoreCase = true).assertDoesNotExist()
    }

    @Test fun allThemesAndAccessibilityLabelsRemainAvailableWithoutEllipsis() {
        var theme by mutableStateOf(KudosThemeMode.Light)
        compose.setContent {
            KudosTheme(theme) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                    AccountShortcutsEditorContent(listOf(AccountShortcut.MarkedForLater), {}, {})
                }
            }
        }
        for (mode in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { theme = mode }
            compose.onNodeWithTag("Account shortcuts editor").performScrollToNode(hasContentDescription("Remove Marked for Later"))
            compose.onNodeWithContentDescription("Remove Marked for Later").assertExists()
            val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithText("Marked for Later", useUnmergedTree = true)
                .performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertTrue(layouts.isNotEmpty())
            layouts.forEach { assertFalse(it.didOverflowHeight); assertFalse(it.isLineEllipsized(it.lineCount - 1)) }
            compose.onNodeWithTag("Account shortcuts editor").performScrollToNode(hasContentDescription("Add More on AO3"))
            compose.onNodeWithContentDescription("Add More on AO3").assertExists()
        }
    }
}
