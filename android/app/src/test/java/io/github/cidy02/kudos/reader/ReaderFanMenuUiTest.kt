package io.github.cidy02.kudos.reader

import android.app.Application
import android.content.Intent
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertHasNoClickAction
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import io.github.cidy02.kudos.app.Routes
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.works.detail.WorkDetailPageActions
import io.github.cidy02.kudos.works.shareWork
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows
import org.robolectric.Robolectric
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1200dp")
class ReaderFanMenuUiTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun commentsAndRetainedSelectionPillsDispatchAndDisabledActionsCannotBeTapped() {
        val calls = mutableListOf<String>()
        compose.setContent {
            MaterialTheme {
                ReaderFanMenu(
                    isOpen = true,
                    onOpenChange = { calls += "close:$it" },
                    pills = readerFanPills(
                        percent = null, searchable = false, ao3WorkId = 123, commentsChapter = 2,
                        onContents = {}, onFind = { calls += "find" },
                        onComments = { id, chapter -> calls += Routes.comments(id, chapterPosition = chapter) },
                        onSettings = {}, onHighlightSelection = { calls += "highlight" },
                        onNoteSelection = { calls += "note" }
                    ),
                    roundActions = listOf(readerKudosAction(123, given = false, working = true) { calls += "kudos" }!!)
                )
            }
        }
        compose.onNodeWithContentDescription("Find in Work").assertHasNoClickAction()
        compose.onNodeWithContentDescription("Give kudos").assertHasNoClickAction()
        compose.onNodeWithContentDescription("Comments").performClick()
        compose.onNodeWithContentDescription("Highlight selection").performClick()
        compose.onNodeWithContentDescription("Add note to selection").performClick()
        assertEquals(listOf("close:false", Routes.comments(123, chapterPosition = 2),
            "close:false", "highlight", "close:false", "note"), calls)
    }

    @Test
    fun markFinishedRemainsReachableOnTheExistingWorkPageForALinklessImport() {
        var toggles = 0
        compose.setContent {
            var finished by remember { mutableStateOf(false) }
            MaterialTheme {
                Column {
                    WorkDetailPageActions(
                        isFinished = finished, hasSourceUrl = false, isWorking = false,
                        onToggleFinished = { toggles++; finished = !finished }, onOpenAo3 = {}
                    )
                }
            }
        }
        compose.onNodeWithText("Mark as Finished").performClick()
        compose.onNodeWithText("Finished").assertExists()
        assertEquals(1, toggles)
    }

    @Test
    fun readerShareTargetCallsTheWorkPageShareEntryPointWithoutOpeningTheWeb() {
        val controller = Robolectric.buildActivity(android.app.Activity::class.java).setup()
        val activity = controller.get()
        val work = SavedWork(title = "Imported story", author = "Author", sourceUrl = "https://example.org/story")
        try {
            shareWork(activity, work.title, readerShareUrl(work)!!)
            val chooser = Shadows.shadowOf(activity).nextStartedActivity
            assertEquals(Intent.ACTION_CHOOSER, chooser.action)
            @Suppress("DEPRECATION")
            val send = chooser.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)!!
            assertEquals(Intent.ACTION_SEND, send.action)
            assertEquals("text/plain", send.type)
            assertEquals("Imported story\nhttps://example.org/story", send.getStringExtra(Intent.EXTRA_TEXT))
        } finally {
            controller.pause().stop().destroy()
        }
    }
}
