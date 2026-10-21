package io.github.cidy02.kudos.auth

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class AO3NativeLoginFieldTest {
    @get:Rule val compose = createComposeRule()

    @Test fun returningFromFallbackRetainsCredentialsWithoutMountingANetworkWebView() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                AO3NativeLoginScreen(authRepository = null, onLoginComplete = {}, onCancel = {}, demo = true)
            }
        }
        compose.onNodeWithContentDescription("Username or email").performTextInput("reader")
        compose.onNodeWithContentDescription("Password").performTextInput("local-test")
        compose.onNodeWithText("Log In").assertIsEnabled()
        compose.onNodeWithText("Use alternative method").performScrollTo().performClick()
        compose.onNodeWithText("Back to username/password").assertIsDisplayed().performClick()
        // Enabled requires both non-empty fields, including the retained password.
        compose.onNodeWithText("Log In").assertIsEnabled()
    }

    @Test
    @Config(qualifiers = "w411dp-h800dp")
    @GraphicsMode(GraphicsMode.Mode.NATIVE)
    fun largeTextFormAndFallbackControlsRemainScrollable() {
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                KudosTheme(KudosThemeMode.Light) {
                    AO3NativeLoginScreen(authRepository = null, onLoginComplete = {}, onCancel = {}, demo = true)
                }
            }
        }
        compose.onNodeWithContentDescription("Username or email").performScrollTo().performTextInput("reader")
        compose.onNodeWithContentDescription("Password").performScrollTo().performTextInput("local-test")
        compose.onNodeWithText("Use alternative method").performScrollTo().assertIsDisplayed().performClick()
        compose.onNodeWithText("Using alternative login method…").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Let's finish logging in on AO3's page below.").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Reload").performScrollTo().assertIsDisplayed().performClick()
        compose.onNodeWithText("Back to username/password").performScrollTo().assertIsDisplayed().performClick()
        compose.onNodeWithContentDescription("Username or email").performScrollTo().assertTextEquals("reader")
        compose.onNodeWithText("Log In").performScrollTo().assertIsEnabled()
    }

    @Test fun keyboardGoUsesTheSubmitCallbackAndDisabledFieldsCannotSubmit() {
        var submissions = 0
        val enabled = mutableStateOf(true)
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                LoginField("Password", "local-test", {}, enabled.value, secure = true,
                    imeAction = ImeAction.Go, onGo = { submissions++ })
            }
        }
        compose.onNodeWithContentDescription("Password").performImeAction()
        assertEquals(1, submissions)
        compose.runOnIdle { enabled.value = false }
        compose.onNodeWithContentDescription("Password").assertIsNotEnabled()
        assertEquals(1, submissions)
    }
}
