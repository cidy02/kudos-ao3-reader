package io.github.cidy02.kudos.reader

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextReplacement
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.ui.subject.KudosTokens
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Only Cancel throws a typed note away; a swipe or Back keeps it (3dz). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class ReaderNoteEditorKeepTest {
    @get:Rule val compose = createComposeRule()
    private val mark = ReadingAnnotation(workID = "w", kindRaw = "highlight", colorRaw = "yellow", selectedText = "a line")
    private val kept = mutableListOf<String>()
    private val done = mutableListOf<String>()
    private var showing by mutableStateOf(true)

    private fun open() = compose.setContent {
        if (showing) {
            CompositionLocalProvider(LocalKudosTokens provides KudosTokens.of(ReaderTheme.Sepia, Color.Red)) {
                ReaderNoteEditor(mark, onCancel = { showing = false }, onDone = { done += it; showing = false },
                    onColorChange = {}, onDelete = { showing = false }, onKeep = { kept += it })
            }
        }
    }

    private fun type() = compose.onNodeWithContentDescription("Note").performTextReplacement("Night bus ")

    @Test fun closingTheSheetAnotherWayKeepsTheTypedNote() {
        open(); type()
        compose.runOnIdle { showing = false }
        compose.runOnIdle { assertEquals(listOf("Night bus"), kept) }
    }

    @Test fun cancelThrowsTheTypedNoteAway() {
        open(); type()
        compose.onNodeWithText("Cancel").performClick()
        compose.runOnIdle { assertEquals(emptyList<String>(), kept) }
    }

    @Test fun doneSavesOnceAndNothingIsKeptTwice() {
        open(); type()
        compose.onNodeWithContentDescription("Done").performClick()
        compose.runOnIdle { assertEquals(listOf("Night bus") to emptyList<String>(), done to kept) }
    }

    @Test fun anUnchangedNoteIsNotWrittenOnClosing() {
        open()
        compose.runOnIdle { showing = false }
        compose.runOnIdle { assertEquals(emptyList<String>(), kept) }
    }
}
