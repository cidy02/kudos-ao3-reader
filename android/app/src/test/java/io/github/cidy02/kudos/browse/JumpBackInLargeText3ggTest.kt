package io.github.cidy02.kudos.browse

import android.app.Application
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.network.ao3.browse.AO3MediaCategory
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
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1600dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class JumpBackInLargeText3ggTest {
    @get:Rule val compose = createComposeRule()

    @Test fun asynchronouslyArrivingPicksKeepTheirSectionAtDoubleTextSizeInEveryTheme() {
        var picks by mutableStateOf(emptyList<JumpBackIn.Pick>())
        var theme by mutableStateOf(KudosThemeMode.Light)
        val opened = mutableListOf<String>()
        compose.setContent { KudosTheme(theme) {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                JumpBackInSection(picks, listOf(AO3MediaCategory("TV Shows", "/media/TV%20Shows/fandoms")), { opened += it })
            }
        } }
        compose.onAllNodesWithText("JUMP BACK IN").assertCountEquals(0)
        compose.runOnIdle { picks = listOf(JumpBackIn.Pick("Doctor Who", "TV Shows", 100)) }
        for (mode in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { theme = mode }
            compose.onNodeWithText("JUMP BACK IN").assertIsDisplayed()
            compose.onNodeWithText("Doctor Who").assertIsDisplayed().performClick()
        }
        compose.runOnIdle { assertEquals(List(4) { "Doctor Who" }, opened) }
    }
}
