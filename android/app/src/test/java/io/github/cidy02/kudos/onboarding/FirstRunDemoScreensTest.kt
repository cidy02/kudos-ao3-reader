package io.github.cidy02.kudos.onboarding

import android.app.Application
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.auth.AO3NativeLoginScreen
import io.github.cidy02.kudos.auth.loginNetworkAllowed
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
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class FirstRunDemoScreensTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun routesRenderTheRealScreenAndDismissWithoutAStore() {
        val route = mutableStateOf("nav:welcome")
        var closed = 0
        compose.setContent {
            KudosTheme(KudosThemeMode.Sepia) {
                FirstRunDemoDestination(
                    requireNotNull(firstRunDemoScreen(route.value, debug = true, demo = true)),
                    onClose = { closed++ }
                )
            }
        }
        compose.onNodeWithText("Welcome to Kudos").assertIsDisplayed()
        compose.onNodeWithText("Continue").performClick()
        assertEquals(1, closed)
        compose.runOnIdle { route.value = "nav:sync-onboarding" }
        compose.onNodeWithText("Protect Your Library").assertIsDisplayed()
        compose.onNodeWithText("Choose Sync Folder").performClick()
        assertEquals(1, closed) // Preview never opens a picker or marks configured.
        compose.onNodeWithText("Don't remind me again").performClick()
        compose.onNodeWithText("Not Now").performClick()
        assertEquals(2, closed)
        compose.runOnIdle { route.value = "nav:whats-new" }
        compose.onNodeWithText("What's New").assertIsDisplayed()
        compose.onNodeWithText("Version 0.2.1").assertIsDisplayed()
        compose.onNodeWithContentDescription("Done").performClick()
        assertEquals(3, closed)
        compose.runOnIdle { route.value = "nav:login" }
        compose.onNodeWithText("Log In to AO3").assertIsDisplayed()
        compose.onNodeWithText("Cancel").performClick()
        assertEquals(4, closed)
    }

    @Test
    fun demoLoginSubmitsNothingIncludingHelpAndVisibleFallback() {
        var root: View? = null
        var completed = 0
        var opened = 0
        compose.setContent {
            root = LocalView.current.rootView
            KudosTheme(KudosThemeMode.Dark) {
                AO3NativeLoginScreen(
                    authRepository = null,
                    onLoginComplete = { completed++ },
                    onCancel = {},
                    onOpenAO3 = { opened++ },
                    demo = true
                )
            }
        }
        assertNoWebView(requireNotNull(root))
        compose.onNodeWithContentDescription("Username or email").performTextInput("reader")
        compose.onNodeWithContentDescription("Password").performTextInput("password")
        compose.onNodeWithText("Log In").performScrollTo().assertIsEnabled().performClick()
        compose.onNodeWithText("Create an AO3 account").performScrollTo().performClick()
        compose.onNodeWithText("Forgot your password?").performScrollTo().performClick()
        assertEquals(0, completed)
        assertEquals(0, opened)
        assertNoWebView(requireNotNull(root))
        compose.onNodeWithText("Use alternative method").performScrollTo().performClick()
        compose.onNodeWithText("Using alternative login method…").assertIsDisplayed()
        compose.onNodeWithText("Reload").performClick()
        assertEquals(0, completed)
        assertNoWebView(requireNotNull(root))
        compose.onNodeWithText("Back to username/password").performClick()
        compose.onNodeWithText("AO3 Account").assertIsDisplayed()
        assertNoWebView(requireNotNull(root))
        assertFalse(loginNetworkAllowed(demo = false, demoNetworkActive = true))
        assertFalse(loginNetworkAllowed(demo = true, demoNetworkActive = false))
        assertTrue(loginNetworkAllowed(demo = false, demoNetworkActive = false))
    }

    @Test
    fun largeTextControlsAndCopyGrowAndScrollAcrossAllFourThemes() {
        val route = mutableStateOf("nav:welcome")
        val theme = mutableStateOf(KudosThemeMode.Light)
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                KudosTheme(theme.value) {
                    FirstRunDemoDestination(
                        requireNotNull(firstRunDemoScreen(route.value, debug = true, demo = true)),
                        onClose = {}
                    )
                }
            }
        }
        listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled).forEach { mode ->
            compose.runOnIdle { theme.value = mode; route.value = "nav:welcome" }
            assertReadable("Welcome to Kudos")
            assertReadable("Found a bug? Shake your device to send a report, or open an issue on " +
                "GitHub. The AO3 team can't help with Kudos, so please don't contact them about it.")
            assertReadable("Continue")
            compose.runOnIdle { route.value = "nav:sync-onboarding" }
            assertReadable("Protect Your Library")
            assertReadable("Choose where Kudos keeps another copy of your library. " +
                "Use the system folder picker. If the folder belongs to a cloud storage app, " +
                "that app can keep it up to date on your devices.")
            assertReadable("Don't remind me again")
            assertReadable("Choose Sync Folder")
            assertReadable("Not Now")
            compose.runOnIdle { route.value = "nav:whats-new" }
            assertReadable("What's New")
            assertReadable("Version 0.2.1")
            assertReadable("Welcome to Kudos — a native Android reader for Archive of Our Own.")
            compose.runOnIdle { route.value = "nav:login" }
            assertReadable("Log In to AO3")
            assertReadable("Kudos submits these credentials only to AO3's official login page. " +
                "Your password is never saved.")
            assertReadable("Create an AO3 account")
            assertReadable("Forgot your password?")
            assertReadable("These open AO3 in the Browse tab. Come back here to log in afterwards.")
        }
    }

    private fun assertNoWebView(view: View) {
        assertFalse("Demo must never create a WebView", view is WebView)
        if (view is ViewGroup) (0 until view.childCount).forEach { assertNoWebView(view.getChildAt(it)) }
    }

    private fun assertReadable(text: String) {
        val node = compose.onNodeWithText(text, useUnmergedTree = true)
        node.performScrollTo().assertIsDisplayed()
        val layouts = mutableListOf<TextLayoutResult>()
        node.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { assertTrue(it(layouts)) }
        val result = layouts.single()
        assertFalse("$text is clipped in height", result.didOverflowHeight)
        assertFalse("$text exceeds its line limit", result.multiParagraph.didExceedMaxLines)
        (0 until result.lineCount).forEach { assertFalse(result.isLineEllipsized(it)) }
    }
}
