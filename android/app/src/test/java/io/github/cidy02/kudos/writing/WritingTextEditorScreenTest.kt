package io.github.cidy02.kudos.writing

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.test.core.app.ApplicationProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.compose.LocalLifecycleOwner
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.network.ao3.writing.recovery.WritingTextRecovery
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1600dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WritingTextEditorScreenTest {
    @get:Rule val compose = createComposeRule()
    @get:Rule val temporary = TemporaryFolder()
    private lateinit var session: WritingEditorSession
    private val delivered = mutableListOf<String>()
    private var leaves = 0
    private lateinit var lifecycle: LifecycleRegistry

    private fun show(theme: KudosThemeMode = KudosThemeMode.Light, large: Boolean = false,
        recovery: Boolean = false) {
        val context = ApplicationProvider.getApplicationContext<Application>()
        val store = WritingTextRecovery(temporary.newFolder().toPath())
        if (recovery) {
            val key = store.fileURL("Writer", "work:17", "content")
            store.save("<p>Recovered lantern.</p>", "earlier", store.sessionURL(key))
        }
        val chrome = PushedShellChrome()
        compose.setContent {
            KudosTheme(theme) {
                val density = LocalDensity.current
                val owner = remember { object : LifecycleOwner {
                    override val lifecycle = LifecycleRegistry(this)
                } }
                lifecycle = owner.lifecycle
                CompositionLocalProvider(LocalPushedShellChrome provides chrome,
                    LocalLifecycleOwner provides owner,
                    LocalDensity provides Density(density.density, if (large) 2f else density.fontScale)) {
                    val model = remember {
                        WritingEditorSession(WritingNativeTextField(context, "<p>Lantern.</p>"), "<p>Lantern.</p>",
                            store, "Writer", "work:17", "content",
                            CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate), android.os.SystemClock::uptimeMillis)
                    }
                    session = model
                    Column {
                        Row { chrome.trailingContent?.invoke(this) }
                        WritingTextEditorContent(model, "Chapter text", "Chapter 13", { delivered += it }, { leaves++ })
                    }
                }
            }
        }
    }

    private fun awaitText(text: String) {
        compose.waitUntil(15_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
        compose.waitForIdle()
    }

    @Test fun topButtonsTagOrderNotesAndDoneDeliverExactlyTheRawBuffer() {
        show()
        awaitText("CHAPTER 13")
        compose.onNodeWithText("Recovery copy on this device · Save from the work form").assertExists()
        compose.onNodeWithText("AO3 supports only certain formatting. The toolbar adds formatting that AO3 can keep when you post.").assertExists()
        compose.onNodeWithContentDescription("Bold").performClick()
        compose.onNodeWithContentDescription("Done").performClick()
        assertEquals(listOf("<strong></strong><p>Lantern.</p>"), delivered)
        assertEquals(0, leaves)
    }

    @Test fun previewRetainsTheNativeFieldAndDisablesUndoAndRedo() {
        show()
        compose.runOnIdle { session.editor.view.setSelection(3, 10) }
        compose.onNodeWithContentDescription("Preview").performClick()
        awaitText("Lantern.")
        compose.onNodeWithContentDescription("Undo").assertIsNotEnabled()
        compose.onNodeWithContentDescription("Redo").assertIsNotEnabled()
        compose.onNodeWithContentDescription("Edit").performClick()
        compose.runOnIdle {
            assertEquals("<p>Lantern.</p>", session.editor.takeText())
            assertEquals(3, session.editor.view.selectionStart)
            assertEquals(10, session.editor.view.selectionEnd)
        }
    }

    @Test fun recoverySheetUsesReferenceWordsAndRestoreIsUndoable() {
        show(recovery = true)
        awaitText("Recover unfinished text?")
        awaitText("The text on the form has changed since this copy began. Review the copy before restoring it.")
        compose.onNodeWithText("Keep form text").assertExists()
        compose.onNodeWithText("Delete this local copy").assertExists()
        compose.onNodeWithText("Restore local copy").performClick()
        compose.runOnIdle { assertEquals("<p>Recovered lantern.</p>", session.editor.takeText()) }
        compose.onNodeWithContentDescription("Undo").performClick()
        compose.runOnIdle { assertEquals("<p>Lantern.</p>", session.editor.takeText()) }
    }

    @Test fun keepFormTextLeavesTheRecoveryFileIntact() {
        show(recovery = true)
        awaitText("Recover unfinished text?")
        lateinit var file: java.nio.file.Path
        compose.runOnIdle { file = session.selectedRecovery!!.url }
        compose.onNodeWithText("Keep form text").performClick()
        compose.runOnIdle {
            assertEquals("<p>Lantern.</p>", session.editor.takeText())
            assertTrue(java.nio.file.Files.exists(file))
        }
    }

    @Test fun moreOffersOnlyPlainPasteAndErrorUsesReferenceWords() {
        show()
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithText("Paste as plain text").assertExists()
        compose.onNodeWithText("Preview on AO3").assertDoesNotExist()
        compose.onNodeWithText("Delete chapter").assertDoesNotExist()
        compose.runOnIdle { session.error = "Local recovery could not be saved: disk full" }
        awaitText("Editor error")
        compose.onNodeWithText("Local recovery could not be saved: disk full").assertExists()
        compose.onNodeWithText("OK").performClick()
    }

    @Test fun lightAtAccessibilitySizeKeepsNotesAndActions() { largeTheme(KudosThemeMode.Light) }
    @Test fun darkAtAccessibilitySizeKeepsNotesAndActions() { largeTheme(KudosThemeMode.Dark) }
    @Test fun sepiaAtAccessibilitySizeKeepsNotesAndActions() { largeTheme(KudosThemeMode.Sepia) }
    @Test fun oledAtAccessibilitySizeKeepsNotesAndActions() { largeTheme(KudosThemeMode.Oled) }
    private fun largeTheme(theme: KudosThemeMode) {
        show(theme, large = true)
        awaitText("CHAPTER 13")
        compose.onNodeWithText("Recovery copy on this device · Save from the work form").assertIsDisplayed()
        compose.onNodeWithText("AO3 supports only certain formatting. The toolbar adds formatting that AO3 can keep when you post.").assertIsDisplayed()
        compose.onNodeWithContentDescription("Done").assertIsDisplayed()
    }

    @Test fun wordCountShowsInitialSingularAndCheckpointPluralAndEmpty() {
        show()
        awaitText("1 word")
        compose.runOnIdle { session.editor.setText("two words"); session.done() }
        awaitText("2 words")
        compose.runOnIdle { session.editor.setText(""); session.done() }
        awaitText("0 words")
    }

    @Test fun pauseStopAndLowMemoryForceCheckpointsWithoutFinishingComposition() {
        show()
        compose.runOnIdle {
            lifecycle.currentState = Lifecycle.State.RESUMED
            val editor = session.editor.view
            editor.requestFocus(); editor.setSelection(editor.text.length)
            editor.onCreateInputConnection(android.view.inputmethod.EditorInfo())!!.setComposingText("日本", 1)
            lifecycle.currentState = Lifecycle.State.STARTED // ON_PAUSE
            assertEquals("<p>Lantern.</p>日本", session.checkpointText)
            assertTrue(android.view.inputmethod.BaseInputConnection.getComposingSpanStart(editor.text) >= 0)
            val sequence = session.scheduler.checkpointCount
            lifecycle.currentState = Lifecycle.State.CREATED // ON_STOP, unchanged buffer
            assertEquals(sequence + 1, session.scheduler.checkpointCount)
            ApplicationProvider.getApplicationContext<Application>().onTrimMemory(android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW)
            assertEquals(sequence + 2, session.scheduler.checkpointCount)
            assertTrue(android.view.inputmethod.BaseInputConnection.getComposingSpanStart(editor.text) >= 0)
        }
    }

    @Test fun failedPreviewSaysTheTextIsUnchanged() {
        compose.setContent { KudosTheme(KudosThemeMode.Light) { EditorPreview(WritingBufferPreview.State.Failed) } }
        compose.onNodeWithText("Couldn't render this HTML").assertExists()
        compose.onNodeWithText("Your text is unchanged. Tap Edit to go back to it.").assertExists()
    }
}
