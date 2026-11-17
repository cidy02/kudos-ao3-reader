package io.github.cidy02.kudos.browse

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.network.ao3.browse.AO3MediaCategory
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1200dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CategoryPanelDensityTest {
    @get:Rule val compose = createComposeRule()

    @Test fun compactCardKeepsFandomTapTargetAndTextAtTwoTimesFontScale() {
        val category = AO3MediaCategory("TV Shows", "/media/TV/fandoms")
        val stats = CategoryStats(fandomCount = 1, clusterFandoms = listOf(
            CategoryStats.ClusterFandom("doctor-who", listOf("Doctor Who"), "Doctor Who", 12, false)
        ))
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                KudosTheme(KudosThemeMode.Light) {
                    CategoryPanel(category, stats, onOpen = {}, onOpenFandom = {})
                }
            }
        }
        val chip = compose.onNodeWithContentDescription("Doctor Who, 12 works")
        chip.assertExists()
        assertTrue(chip.fetchSemanticsNode().boundsInRoot.height >= 48f * compose.density.density)
        val panel = compose.onNodeWithContentDescription("TV Shows. Open fandoms.")
        assertTrue(panel.fetchSemanticsNode().boundsInRoot.height >= 48f * compose.density.density)
        listOf("TV Shows", "Doctor Who").forEach { text ->
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText(text, useUnmergedTree = true)
                .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertTrue(layouts.isNotEmpty())
            layouts.forEach { result ->
                assertFalse(result.didOverflowHeight)
                assertFalse(result.multiParagraph.didExceedMaxLines)
                (0 until result.lineCount).forEach { assertFalse(result.isLineEllipsized(it)) }
            }
        }
    }
}
