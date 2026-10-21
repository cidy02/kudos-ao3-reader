package io.github.cidy02.kudos.search

import android.app.Application
import androidx.compose.runtime.*
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.core.model.SavedSearch
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
class SavedSearchDeletion3ggTest {
    @get:Rule val compose = createComposeRule()

    @Test fun aTapRunsAndLongPressDeletesWithoutAPermanentTrashButton() {
        val saved = SavedSearch(name = "Doctor Who")
        var searches by mutableStateOf(listOf(saved))
        val ran = mutableListOf<String>()
        val deleted = mutableListOf<String>()
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            SavedSearchesList(searches, { "English" }, { ran += it.id }, { deleted += it.id; searches = emptyList() })
        } }
        compose.onAllNodesWithContentDescription("Delete saved search").assertCountEquals(0)
        compose.onNodeWithText(saved.name).performClick()
        assertEquals(listOf(saved.id), ran)
        compose.onNodeWithText(saved.name).performTouchInput { longClick() }
        compose.onNodeWithText("Delete saved search").performClick()
        compose.onAllNodesWithText(saved.name).assertCountEquals(0)
        assertEquals(listOf(saved.id), deleted)
    }

    @Test fun trailingSwipeDeletesAndAccessibilityHasTheSameAction() {
        val saved = SavedSearch(name = "Doctor Who")
        var searches by mutableStateOf(listOf(saved))
        var deleted = 0
        compose.setContent { KudosTheme(KudosThemeMode.Dark) {
            SavedSearchesList(searches, { null }, {}, { deleted++; searches = emptyList() })
        } }
        val actions = compose.onNodeWithText(saved.name).fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsActions.CustomActions]
        assertTrue(actions.any { it.label == "Delete saved search" })
        compose.onNodeWithText(saved.name).performTouchInput { swipeLeft() }
        compose.waitUntil(5_000) { deleted > 0 }
        assertEquals(1, deleted)
        compose.onAllNodesWithText(saved.name).assertCountEquals(0)
    }
}
