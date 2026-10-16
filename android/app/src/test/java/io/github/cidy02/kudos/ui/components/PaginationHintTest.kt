package io.github.cidy02.kudos.ui.components

import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
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

    @Test fun exactPageEntryWaitsForGoAndRejectsOutOfRangeOrOverflow() {
        val loads = mutableListOf<Int>()
        compose.setContent { KudosPaginationBar(1, 5000, { loads += it }) }
        compose.onNodeWithText("Page 1 of 5000").performClick()
        compose.onNode(hasSetTextAction()).performTextReplacement("2731")
        assertEquals(emptyList<Int>(), loads)
        compose.onNodeWithText("Go").assertIsEnabled()
        listOf("0", "5001", "99999999999999999999", "").forEach { invalid ->
            compose.onNode(hasSetTextAction()).performTextReplacement(invalid)
            compose.onNodeWithText("Go").assertIsNotEnabled()
        }
        compose.onNode(hasSetTextAction()).performTextReplacement("2731")
        compose.onNodeWithText("Go").performScrollTo().performClick()
        assertEquals(listOf(2731), loads)
    }

    @Test fun thePageButtonSaysItOpensThePagePickerAndOpensIt() {
        compose.setContent { KudosPaginationBar(currentPage = 2, totalPages = 9, onPageChange = {}) }
        val button = compose.onNodeWithText("Page 2 of 9", useUnmergedTree = false)
        button.assert(SemanticsMatcher("says \"open the page picker\"") {
            it.config.getOrNull(SemanticsActions.OnClick)?.label == "open the page picker"
        })
        // The label is added beside the button's own action, not in place of it: what TalkBack's
        // double-tap calls still opens the picker.
        compose.onNodeWithText("Go").assertDoesNotExist()
        button.performSemanticsAction(SemanticsActions.OnClick)
        compose.onNodeWithText("Go").assertExists()
    }
}
