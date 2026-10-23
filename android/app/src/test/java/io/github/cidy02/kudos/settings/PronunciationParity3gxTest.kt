package io.github.cidy02.kudos.settings

import android.app.Application
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.reader.speech.KokoroPronunciationStore
import io.github.cidy02.kudos.ui.theme.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1200dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PronunciationParity3gxTest {
    @get:Rule val compose = createComposeRule()
    @get:Rule val folder = TemporaryFolder()

    @Test fun correctionsHaveNaturalNumericOrderAndCopyShowsItsResultInADialog() {
        val store = KokoroPronunciationStore(folder.root)
        store.setOverride("word10", "ten")
        store.setOverride("word2", "two")
        compose.setContent { KudosTheme(KudosThemeMode.Light) { PronunciationSettingsSheet(store, {}) } }
        compose.waitUntil(5_000) { compose.onAllNodesWithText("word2").fetchSemanticsNodes().isNotEmpty() }
        assertTrue(compose.onNodeWithText("word2").fetchSemanticsNode().boundsInRoot.top <
            compose.onNodeWithText("word10").fetchSemanticsNode().boundsInRoot.top)
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithText("Copy All").performClick()
        compose.onNodeWithText("Pasted Corrections").assertExists()
        compose.onNodeWithText("Copied 2 corrections.").assertExists()
        compose.onNodeWithText("OK").performClick()
        compose.onNodeWithText("Pasted Corrections").assertDoesNotExist()
    }

    @Test fun aNewPronunciationTitleFollowsTheTypedWord() {
        val store = KokoroPronunciationStore(folder.root)
        compose.setContent { KudosTheme(KudosThemeMode.Light) { PronunciationEditor("", "", store, {}) } }
        compose.onNodeWithText("Add Pronunciation").assertExists()
        compose.onNodeWithContentDescription("Word").performTextInput("Hermione")
        compose.onNodeWithText("Add Pronunciation").assertDoesNotExist()
        compose.onAllNodesWithText("Hermione").assertCountEquals(2)
    }
}
