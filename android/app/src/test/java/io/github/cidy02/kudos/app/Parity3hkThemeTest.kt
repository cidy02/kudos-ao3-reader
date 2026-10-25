package io.github.cidy02.kudos.app

import android.app.Application
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.ui.theme.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** 3hk: bare Material controls in Dark and OLED take the accent's readable ink, as iOS tints them, not cream. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class Parity3hkThemeTest {
    @get:Rule val compose = createComposeRule()

    @Test fun darkAndOledMaterialPrimaryIsTheAccentsReadableInk() {
        var mode by mutableStateOf(KudosThemeMode.Dark)
        var primary = Color.Unspecified
        lateinit var tokens: KudosTokens
        compose.setContent { KudosTheme(mode) {
            tokens = LocalKudosTokens.current
            primary = MaterialTheme.colorScheme.primary
        } }
        for (theme in listOf(KudosThemeMode.Dark, KudosThemeMode.Oled)) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            assertEquals("Material primary in $theme", tokens.theme.accentInk(tokens.accent), primary)
            // The old cream primary was (244,232,215): nearly as green as red. The ink is clearly red.
            assertTrue("Primary in $theme is red, not cream: $primary", primary.red - primary.green > 0.2f)
        }
    }
}
