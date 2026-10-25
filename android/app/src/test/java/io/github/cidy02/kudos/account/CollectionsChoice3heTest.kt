package io.github.cidy02.kudos.account

import android.app.Application
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CollectionsChoice3heTest {
    @get:Rule val compose = createComposeRule()

    @Test fun orderByShowsAChoiceIndicatorAndStillOpensItsMenu() {
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            AO3CollectionsFilterPanel(AO3CollectionsFilter(), {})
        } }
        compose.waitForIdle()
        compose.onNode(hasTestTag("Choice indicator") and hasAnyAncestor(hasText("Order by")), useUnmergedTree = true)
            .assertExists()
        compose.onNodeWithText("AO3 order").performClick()
        compose.onNodeWithText("Title").assertIsDisplayed()
    }
}
