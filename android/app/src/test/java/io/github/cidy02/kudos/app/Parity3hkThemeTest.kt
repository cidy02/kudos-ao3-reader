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

/** 3hk: Material primary on Dark and OLED is the accent's readable text step (accentInk). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class Parity3hkThemeTest {
    @get:Rule val compose = createComposeRule()

    @Test fun darkAndOledMaterialPrimaryUsesReadableAccentInk() {
        var mode by mutableStateOf(KudosThemeMode.Dark)
        var accentHex by mutableStateOf(DefaultAccentHex)
        var primary = Color.Unspecified
        lateinit var tokens: KudosTokens
        compose.setContent { KudosTheme(mode, accentColorHex = accentHex) {
            tokens = LocalKudosTokens.current
            primary = MaterialTheme.colorScheme.primary
        } }
        for (hex in listOf(DefaultAccentHex, "#7B2D6B", "#2468AC")) {
            for (theme in listOf(KudosThemeMode.Dark, KudosThemeMode.Oled)) {
                compose.runOnIdle {
                    accentHex = hex
                    mode = theme
                }
                compose.waitForIdle()
                assertEquals("Material primary in $theme ($hex)", tokens.accentInk, primary)
                assertTrue(
                    "Contrast in $theme ($hex): ${contrastRatio(primary, tokens.background)}",
                    contrastRatio(primary, tokens.background) >= 4.5
                )
            }
        }
        compose.runOnIdle {
            accentHex = DefaultAccentHex
            mode = KudosThemeMode.Dark
        }
        compose.waitForIdle()
        assertEquals(AppAccents.Ao3Red.darkInk, primary)
        assertTrue("Primary in Dark is red, not cream: $primary", primary.red - primary.green > 0.2f)
    }
}
