package io.github.cidy02.kudos.author

import android.app.Application
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1600dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class OwnWorkCard3ggTest {
    @get:Rule val compose = createComposeRule()

    @Test fun menuLivesInsideTheCardAndKeepsEveryActionAndFigure() {
        val work = AO3WorkSummary(123, "Work", listOf("Writer"), listOf("Fandom"), "General Audiences",
            emptyList(), emptyList(), kudos = 80, comments = 8, hits = 900, bookmarks = 30, isComplete = false)
        val actions = mutableListOf<String>()
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            OwnWorkRow(work, { actions += it }) { menu ->
                AO3AuthorWorkCard(work, AuthorDisplayMode.Ledger, false, true, {}, actions = menu)
            }
        } }
        val card = compose.onNodeWithContentDescription("Work, by Writer").fetchSemanticsNode().boundsInRoot
        val menu = compose.onNodeWithContentDescription("Actions for Work").fetchSemanticsNode().boundsInRoot
        assertTrue(menu.top >= card.top && menu.bottom <= card.bottom)
        for (label in listOf("KUDOS", "COMMENTS", "HITS", "BOOKMARKS")) compose.onNodeWithText(label).assertExists()
        for ((label, action) in listOf("Edit" to "edit", "Tags" to "tags", "Chapter" to "chapter", "Delete" to "delete")) {
            compose.onNodeWithContentDescription("Actions for Work").performClick()
            compose.onNodeWithText(label).performClick()
            compose.runOnIdle { assertEquals(action, actions.last()) }
        }
    }

    @Test fun absentFigureFieldsStayAbsentRatherThanBecomingZeros() {
        val work = AO3WorkSummary(123, "Work", listOf("Writer"), emptyList(), "", emptyList(), emptyList(), kudos = 80, hits = 900)
        compose.setContent { KudosTheme(KudosThemeMode.Light) { AO3AuthorPerformanceStrip(work) } }
        compose.onNodeWithText("KUDOS").assertExists()
        compose.onNodeWithText("HITS").assertExists()
        compose.onAllNodesWithText("COMMENTS").assertCountEquals(0)
        compose.onAllNodesWithText("BOOKMARKS").assertCountEquals(0)
    }
}
