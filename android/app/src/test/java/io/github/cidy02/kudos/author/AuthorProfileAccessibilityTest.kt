package io.github.cidy02.kudos.author

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.network.ao3.author.*
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
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2000dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AuthorProfileAccessibilityTest {
    @get:Rule val compose = createComposeRule()

    @Test fun subscribeAndScopeRemainUnclippedAtLargestTextAcrossAllThemes() {
        var theme by mutableStateOf(KudosThemeMode.Light)
        var route by mutableStateOf(AO3AuthorRoute("Avery_Archive"))
        val pseud = AO3AuthorPseud("The Keeper of Every Lamp", AO3AuthorRoute("Avery_Archive", "The Keeper of Every Lamp"))
        val form = AO3AuthorSubscriptionForm("Subscribe", "unused", emptyList(), "", "unused")
        val header = AO3AuthorHeader("Avery_Archive", "Avery_Archive", null, null, listOf(pseud), emptyList(), form,
            listOf(AO3AuthorWebAction("Mute", "unused", AO3AuthorWebAction.Kind.Mute),
                AO3AuthorWebAction("Block", "unused", AO3AuthorWebAction.Kind.Block)))
        compose.setContent {
            KudosTheme(theme) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, 2.4f)) {
                    Column(Modifier.fillMaxWidth()) {
                        AO3AuthorHero(header, route, "", false, {}, {})
                        AuthorPseudSelector(listOf(pseud), route) { route = it }
                    }
                }
            }
        }
        for (mode in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { theme = mode }
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText("Subscribe", useUnmergedTree = true)
                .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertTrue(layouts.isNotEmpty())
            layouts.forEach { layout ->
                assertFalse(layout.didOverflowHeight)
                assertFalse(layout.isLineEllipsized(layout.lineCount - 1))
                // A fixed-height parent can clip a text layout that measured correctly.
                val text = compose.onNodeWithText("Subscribe", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
                assertTrue(text.height >= layout.size.height - 1)
            }
            compose.onNodeWithContentDescription("Author scope").performClick()
            compose.onNodeWithText(pseud.name).performClick()
            compose.onNodeWithText("Scope").assertExists()
            // The chosen pseud is named twice: under the hero and as the Scope row's value.
            val pseudNodes = compose.onAllNodesWithText(pseud.name, useUnmergedTree = true)
            assertTrue(pseudNodes.fetchSemanticsNodes().isNotEmpty())
            val scopeLayouts = mutableListOf<TextLayoutResult>()
            pseudNodes.fetchSemanticsNodes().indices.forEach { index ->
                pseudNodes[index].performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(scopeLayouts) }
            }
            scopeLayouts.forEach { assertFalse(it.didOverflowHeight); assertFalse(it.isLineEllipsized(it.lineCount - 1)) }
            compose.runOnIdle { route = AO3AuthorRoute("Avery_Archive") }
        }
    }
}
