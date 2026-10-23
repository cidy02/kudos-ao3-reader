package io.github.cidy02.kudos.ui.components

import android.app.Application
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h900dp")
class PageJumpSheetParityTest {
    @get:Rule val compose = createComposeRule()

    @Test fun exactEntryNearbyAndEndsStageOnlyUntilGo() {
        val selected = mutableListOf<Int>()
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                KudosPaginationBar(1, 30, onPageChange = { selected += it })
            }
        }
        compose.onNodeWithContentDescription("Page 1 of 30").performClick()
        compose.onNodeWithText("Go to page").assertExists()
        compose.onNodeWithText("PAGE NUMBER").assertExists()
        compose.onNodeWithText("NEARBY").assertExists()
        compose.onNode(SemanticsMatcher.keyIsDefined(SemanticsProperties.ProgressBarRangeInfo)).assertDoesNotExist()
        compose.onNodeWithContentDescription("Page 3").performClick()
        assertTrue(selected.isEmpty())
        compose.onNodeWithText("Last (30)").performScrollTo().performClick()
        assertTrue(selected.isEmpty())
        compose.onNodeWithText("First page").performClick()
        val field = compose.onNode(hasSetTextAction())
        field.performTextReplacement("page 24")
        compose.onNodeWithContentDescription("Go to page 24").performClick()
        assertEquals(listOf(24), selected)
        compose.onNodeWithText("Go to page").assertDoesNotExist()
    }
}
