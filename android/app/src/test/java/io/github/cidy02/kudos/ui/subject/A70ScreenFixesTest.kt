package io.github.cidy02.kudos.ui.subject

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.browse.JumpBackIn
import io.github.cidy02.kudos.browse.JumpBackInSection
import io.github.cidy02.kudos.network.ao3.browse.AO3MediaCategory
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** A70: screen differences from the iPhone that carry a rule, not only a colour. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1600dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class A70ScreenFixesTest {
    @get:Rule val compose = createComposeRule()

    private fun top(description: String) =
        compose.onNodeWithContentDescription(description).fetchSemanticsNode().boundsInRoot.top

    @Test fun aFourFigureStripTakesTwoRowsAtTheAccessibilitySizesAsIOSDoes() {
        var scale by mutableStateOf(1f)
        val cells = listOf("1" to "Queues", "2" to "Works", "3" to "Words", "4" to "Hours")
            .map { (value, label) -> SubjectStatCell(value, label) }
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, scale)) {
                SubjectStatStrip(cells, SubjectPalette.fromHue(0.3, ReaderTheme.Light))
            }
        } }
        assertEquals(1, setOf(top("1 Queues"), top("2 Works"), top("3 Words"), top("4 Hours")).size)
        compose.runOnIdle { scale = 2f }
        compose.waitForIdle()
        assertEquals(top("1 Queues"), top("2 Works"))
        assertEquals(top("3 Words"), top("4 Hours"))
        assertTrue("the second pair goes under the first", top("3 Words") > top("1 Queues"))
    }

    /**
     * Pins the behaviour only: the strip opening scrolled sideways was seen on the emulator (A70)
     * and is fixed there (A70c), but neither this sequence nor categories arriving late reproduces
     * it under Robolectric, so this passes with the fix removed too.
     */
    @Test fun aJumpBackInPickArrivingInFrontIsShownWholeNotCutAtTheLeftEdge() {
        var picks by mutableStateOf(listOf(
            JumpBackIn.Pick("Sherlock", "TV Shows", 100), JumpBackIn.Pick("Supernatural", "TV Shows", 100)
        ))
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            JumpBackInSection(picks, listOf(AO3MediaCategory("TV Shows", "/media/TV%20Shows/fandoms")), {})
        } }
        compose.onNodeWithText("Sherlock").assertExists()
        compose.runOnIdle { picks = listOf(JumpBackIn.Pick("Doctor Who", "TV Shows", 100)) + picks }
        compose.waitForIdle()
        val first = compose.onNodeWithText("Doctor Who").fetchSemanticsNode().boundsInRoot
        val second = compose.onNodeWithText("Sherlock").fetchSemanticsNode().boundsInRoot
        assertTrue("the new first card starts on screen (left ${first.left})", first.left >= 0f)
        assertTrue(first.left < second.left)
    }
}
