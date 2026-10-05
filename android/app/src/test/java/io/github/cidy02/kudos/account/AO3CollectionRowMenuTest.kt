package io.github.cidy02.kudos.account

import android.app.Application
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import io.github.cidy02.kudos.network.ao3.account.AO3Collection
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** No repository or HTTP client: real card/menu input dispatch under the app's theme. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class AO3CollectionRowMenuTest {
    @get:Rule val compose = createComposeRule()

    @Test fun nonOwnerLongPressShowsBothActionsAndTapsOpenTheCorrectRoutes() {
        var opened = 0
        val routes = mutableListOf<String>()
        compose.setContent {
            KudosTheme(themeMode = KudosThemeMode.Light) {
                AO3CollectionRow(AO3Collection("winter_exchange", "Winter Exchange 2026", viewerIsOwner = false,
                    viewerIsMember = false), onClick = { ++opened }, onAction = { routes += it },
                    palette = LocalKudosTokens.current.scopePalette)
            }
        }
        compose.onNodeWithText("Winter Exchange 2026").performTouchInput { longClick() }
        compose.onNodeWithText("Edit Collection").assertIsDisplayed()
        compose.onNodeWithText("Manage Items").assertIsDisplayed()
        compose.onNodeWithText("Edit Collection").performClick()
        compose.runOnIdle { assertEquals(listOf("ao3-collection-form?slug=winter_exchange"), routes); assertEquals(0, opened) }
        compose.onNodeWithText("Winter Exchange 2026").performTouchInput { longClick() }
        compose.onNodeWithText("Manage Items").performClick()
        compose.runOnIdle {
            assertEquals("ao3-collection-items/winter_exchange?title=Winter%20Exchange%202026", routes.last())
            assertEquals(0, opened)
        }
        compose.onNodeWithText("Winter Exchange 2026").performClick()
        compose.runOnIdle { assertEquals(1, opened) }
    }
}
