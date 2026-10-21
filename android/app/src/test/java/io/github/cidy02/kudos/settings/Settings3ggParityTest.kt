package io.github.cidy02.kudos.settings

import android.app.Application
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.ui.subject.LocalShellWashes
import io.github.cidy02.kudos.ui.subject.ShellWashes
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
class Settings3ggParityTest {
    @get:Rule val compose = createComposeRule()

    @Test fun backupUsesOneHeaderAndReleasesItsChromeWithoutRegisteringAWashInEveryTheme() {
        val chrome = PushedShellChrome()
        val washes = ShellWashes()
        var shown by mutableStateOf(true)
        var theme by mutableStateOf(KudosThemeMode.Light)
        compose.setContent {
            KudosTheme(theme) {
                CompositionLocalProvider(LocalPushedShellChrome provides chrome, LocalShellWashes provides washes) {
                    if (shown) SettingsPage("Backup") { }
                }
            }
        }
        for (mode in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { theme = mode }
            compose.onAllNodesWithText("Backup").assertCountEquals(1)
            compose.onNodeWithText("SETTINGS").assertExists()
            compose.runOnIdle {
                assertTrue(chrome.mounted)
                assertEquals(true, chrome.hasSubjectHeader)
                assertNull(chrome.customTitle)
                val expected = if (mode == KudosThemeMode.Dark) io.github.cidy02.kudos.ui.theme.SurfaceDark else
                    when (mode) {
                        KudosThemeMode.Oled -> io.github.cidy02.kudos.ui.subject.ReaderTheme.Oled.cardBackdrop
                        KudosThemeMode.Sepia -> io.github.cidy02.kudos.ui.subject.ReaderTheme.Sepia.cardBackdrop
                        else -> io.github.cidy02.kudos.ui.subject.ReaderTheme.Light.cardBackdrop
                    }
                assertEquals(expected, chrome.pageBackground)
                assertNull(washes.page)
            }
        }
        compose.runOnIdle { shown = false }
        compose.runOnIdle { assertFalse(chrome.mounted); assertNull(chrome.hasSubjectHeader); assertNull(chrome.pageBackground) }
    }

    @Test fun disabledSeriesLimitDoesNotChangeAndEnabledLimitStillStopsAtItsBounds() {
        var enabled by mutableStateOf(false)
        var value by mutableStateOf(5)
        var theme by mutableStateOf(KudosThemeMode.Light)
        compose.setContent { KudosTheme(theme) { SeriesLimitStepper(value, enabled) { value = it } } }
        for (mode in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { theme = mode }
            compose.onNodeWithText("−").assertIsDisplayed().assertIsNotEnabled().performTouchInput { click() }
            compose.onNodeWithText("+").assertIsDisplayed().assertIsNotEnabled().performTouchInput { click() }
            compose.runOnIdle { assertEquals(5, value) }
        }
        compose.runOnIdle { enabled = true; value = 2 }
        compose.onNodeWithText("−").assertIsNotEnabled()
        compose.onNodeWithText("+").performClick()
        compose.runOnIdle { assertEquals(3, value); value = 25 }
        compose.onNodeWithText("+").assertIsNotEnabled()
        compose.onNodeWithText("−").performClick()
        compose.runOnIdle { assertEquals(24, value) }
    }
}
