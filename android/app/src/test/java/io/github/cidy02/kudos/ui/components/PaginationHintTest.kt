package io.github.cidy02.kudos.ui.components

import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextReplacement
import org.junit.Assert.assertEquals
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performSemanticsAction
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Audit W3, row 17: the page button says what a tap does, and still does it. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PaginationHintTest {
    @get:Rule val compose = createComposeRule()

    /** iOS PageJumpSheet.draftPage: a page past the end clamps to the last; zero, an overflow or
     *  an empty field reads as the current page, so Go has nothing to do. */
    @Test fun exactPageEntryWaitsForGoAndClampsLikeIOS() {
        val loads = mutableListOf<Int>()
        compose.setContent { KudosPaginationBar(1, 5000, { loads += it }) }
        compose.onNodeWithText("Page 1 / 5000").performClick()
        compose.onNode(hasSetTextAction()).performTextReplacement("2731")
        assertEquals(emptyList<Int>(), loads)
        compose.onNodeWithContentDescription("Go to page 2731").assertIsEnabled()
        compose.onNode(hasSetTextAction()).performTextReplacement("5001")
        compose.onNodeWithContentDescription("Go to page 5000").assertIsEnabled()
        listOf("0", "99999999999999999999", "").forEach { nothingToDo ->
            compose.onNode(hasSetTextAction()).performTextReplacement(nothingToDo)
            compose.onNodeWithContentDescription("Go to page 1").assertIsNotEnabled()
        }
        compose.onNode(hasSetTextAction()).performTextReplacement("2731")
        compose.onNodeWithContentDescription("Go to page 2731").performClick()
        assertEquals(listOf(2731), loads)
    }

    @Test fun thePageButtonSaysItOpensThePagePickerAndOpensIt() {
        compose.setContent { KudosPaginationBar(currentPage = 2, totalPages = 9, onPageChange = {}) }
        val button = compose.onNodeWithText("Page 2 / 9", useUnmergedTree = false)
        button.assert(SemanticsMatcher("says \"open the page picker\"") {
            it.config.getOrNull(SemanticsActions.OnClick)?.label == "open the page picker"
        })
        // The label is added beside the button's own action, not in place of it: what TalkBack's
        // double-tap calls still opens the picker.
        compose.onNodeWithText("Go to page").assertDoesNotExist()
        button.performSemanticsAction(SemanticsActions.OnClick)
        compose.onNodeWithText("Go to page").assertExists()
    }

    /** Port of iOS SearchPaginationTests.swift:45 arrowsUseTapForAdjacentAndLongPressForEnds. */
    @Test fun arrowsUseTapForAdjacentAndLongPressForEnds() {
        assertEquals(19, navigationPage(PaginationDirection.BACKWARD, longPress = false, currentPage = 20, totalPages = 100))
        assertEquals(1, navigationPage(PaginationDirection.BACKWARD, longPress = true, currentPage = 20, totalPages = 100))
        assertEquals(21, navigationPage(PaginationDirection.FORWARD, longPress = false, currentPage = 20, totalPages = 100))
        assertEquals(100, navigationPage(PaginationDirection.FORWARD, longPress = true, currentPage = 20, totalPages = 100))
    }

    @Test fun arrowLongPressJumpsToFirstAndLastPage() {
        var page = 20
        compose.setContent {
            KudosPaginationBar(currentPage = page, totalPages = 100, onPageChange = { page = it })
        }
        compose.onNodeWithContentDescription("Previous Page").performTouchInput { longClick() }
        assertEquals(1, page)

        compose.onNodeWithContentDescription("Next Page").performTouchInput { longClick() }
        assertEquals(100, page)
    }
}
