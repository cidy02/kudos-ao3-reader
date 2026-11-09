package io.github.cidy02.kudos.home

import android.app.Application
import androidx.compose.ui.test.assertDoesNotExist
import androidx.compose.ui.test.assertExists
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class HomeProfileButtonTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun signedInProfileShowsUnreadBadgeAndOpensAccount() {
        var opened = false
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                HomeProfileButton(true, "Avery", null, 12, { opened = true })
            }
        }

        compose.onNodeWithText("12", useUnmergedTree = true).assertExists()
        compose.onNodeWithContentDescription("Account").performClick()
        assertTrue(opened)
    }

    @Test
    fun signedOutProfileDoesNotShowUnreadBadge() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                HomeProfileButton(false, null, null, 12, {})
            }
        }

        compose.onNodeWithText("12", useUnmergedTree = true).assertDoesNotExist()
    }
}
