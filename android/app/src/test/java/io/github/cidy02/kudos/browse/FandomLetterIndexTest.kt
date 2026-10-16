package io.github.cidy02.kudos.browse

import android.app.Application
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performSemanticsAction
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class FandomLetterIndexTest {
    @get:Rule val compose = createComposeRule()

    @Test fun screenReaderAdjustmentSkipsUnavailableLettersAndClampsAtTheEnds() {
        val picked = mutableListOf<String>()
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) { FandomLetterIndex(setOf("A", "D", "Z"), { picked += it }) }
        }
        val index = compose.onNodeWithContentDescription("Fandom index")
        index.performSemanticsAction(SemanticsActions.SetProgress) { it(1f) }
        index.performSemanticsAction(SemanticsActions.SetProgress) { it(100f) }
        index.performSemanticsAction(SemanticsActions.SetProgress) { it(-1f) }
        assertEquals(listOf("D", "Z", "A"), picked)
    }
}
