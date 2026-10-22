package io.github.cidy02.kudos.ui.subject

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.platform.InspectableValue
import androidx.compose.ui.platform.isDebugInspectorInfoEnabled
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.ui.components.SensitiveWorkRow
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.detail.WorkDetailResumeCard
import io.github.cidy02.kudos.works.detail.WorkDetailTagSections
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h2000dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
class OwnerDecisions3goComposeTest {
    @get:Rule val compose = createComposeRule()
    private var previousInspector = false

    @Before fun inspectModifiers() {
        previousInspector = isDebugInspectorInfoEnabled
        isDebugInspectorInfoEnabled = true
    }
    @After fun restoreInspector() { isDebugInspectorInfoEnabled = previousInspector }

    private fun properties(node: SemanticsNodeInteraction): List<Pair<String, Any?>> =
        node.fetchSemanticsNode().layoutInfo.getModifierInfo().flatMap { info ->
            (info.modifier as? InspectableValue)?.inspectableElements?.map { it.name to it.value }?.toList().orEmpty()
        }

    @Test fun glyphUsesReadableInkForTheSuppliedAccentButTheSquareKeepsItsExactFillOnDarkAndOled() {
        var mode by mutableStateOf(KudosThemeMode.Dark)
        var accent by mutableStateOf(Color(0xFF990000))
        compose.setContent { KudosTheme(mode, accentColorHex = "#00FF00") {
            AccentIconSquare(Icons.Default.Settings, "Glyph", Modifier.testTag("square"), accent)
        } }
        for ((theme, selectedMode) in listOf(ReaderTheme.Dark to KudosThemeMode.Dark, ReaderTheme.Oled to KudosThemeMode.Oled)) {
            for (picked in listOf(Color(0xFF990000), Color(0xFF001166), Color(0xFFFFD54F))) {
                compose.runOnIdle { mode = selectedMode; accent = picked }
                val ink = theme.accentInk(picked)
                assertTrue(contrastRatio(ink, theme.cardBackdrop) >= 4.5)
                assertTrue(properties(compose.onNodeWithContentDescription("Glyph", useUnmergedTree = true))
                    .contains("colorFilter" to ColorFilter.tint(ink)))
                assertTrue(properties(compose.onNodeWithTag("square", useUnmergedTree = true))
                    .contains("color" to picked.withOpacity(0.16)))
            }
        }
    }

    @Test fun aSheetPaletteOwnsControlInkAndFilledSwitchesKeepThePickedColour() {
        val picked = Color(0xFF193B97)
        var mode by mutableStateOf(KudosThemeMode.Light)
        var theme by mutableStateOf(ReaderTheme.Light)
        var primary = Color.Unspecified
        var tokenFill = Color.Unspecified
        var tokenInk = Color.Unspecified
        compose.setContent { KudosTheme(mode, accentColorHex = "#990000") {
            val palette = SubjectPalette.fromColor(picked, theme)
            SubjectPaletteTheme(palette) {
                primary = MaterialTheme.colorScheme.primary
                tokenFill = LocalKudosTokens.current.accent
                tokenInk = LocalKudosTokens.current.accentInk
                SubjectToggle(true, {}, accent = palette.tint, contentDescription = "Keep")
            }
        } }
        for ((nextTheme, nextMode) in listOf(ReaderTheme.Light to KudosThemeMode.Light,
            ReaderTheme.Dark to KudosThemeMode.Dark, ReaderTheme.Oled to KudosThemeMode.Oled, ReaderTheme.Sepia to KudosThemeMode.Sepia)) {
            compose.runOnIdle { theme = nextTheme; mode = nextMode }
            compose.runOnIdle {
                assertEquals(picked, tokenFill)
                assertEquals(nextTheme.accentInk(picked), tokenInk)
                assertEquals(tokenInk, primary)
            }
            assertTrue(properties(compose.onNodeWithContentDescription("Keep")) .contains("color" to picked))
        }
    }

    @Test fun ringsShowThisDownloadsFractionAndReturnToReadingAndCardsDimOnlyWhileDownloading() {
        var fraction by mutableStateOf<Double?>(0.37)
        val work = SavedWork(title = "Work", author = "Author", hasEpub = true)
        compose.setContent { KudosTheme(KudosThemeMode.Dark) {
            Column {
                WorkReadingOrDownloadRing(fraction, 0.12, "Reading", Modifier.testTag("ring"))
                WorkDetailResumeCard("Read", false, fraction, null, null, null,
                    LocalKudosTokens.current.scopePalette, {}, Modifier.testTag("resume"))
                SensitiveWorkRow(work, {}, modifier = Modifier.testTag("row"), downloadFraction = fraction)
            }
        } }
        // A card may clip (also a graphics layer), so the dim is the one extra layer while downloading.
        fun layers(tag: String) = compose.onNodeWithTag(tag).fetchSemanticsNode().layoutInfo.getModifierInfo()
            .count { (it.modifier as? InspectableValue)?.nameFallback == "graphicsLayer" }
        val ring = compose.onNode(hasContentDescription("Reading progress") and hasAnyAncestor(hasTestTag("ring")), useUnmergedTree = true)
        ring.assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "37 percent, Downloading"))
        val resumeWhileDownloading = layers("resume")
        val rowWhileDownloading = layers("row")
        compose.onAllNodesWithContentDescription("Reading progress", useUnmergedTree = true).assertCountEquals(3)
        compose.mainClock.advanceTimeBy(3000)
        ring.assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "37 percent, Downloading"))
        compose.runOnIdle { fraction = null }
        ring.assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "12 percent, Reading"))
        assertEquals(resumeWhileDownloading - 1, layers("resume"))
        assertEquals(rowWhileDownloading - 1, layers("row"))
        compose.onAllNodesWithContentDescription("Reading progress", useUnmergedTree = true).assertCountEquals(1)
    }

    @Test fun noTagsExplainsBothAo3AndUnlinkedImportsAndDisappearsWhenTagsArrive() {
        var ao3 by mutableStateOf(true)
        var tags by mutableStateOf(emptyList<String>())
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            WorkDetailTagSections(emptyList(), emptyList(), emptyList(), emptyList(), tags,
                LocalKudosTokens.current.scopePalette, hasAo3WorkId = ao3)
        } }
        val remote = "AO3 hasn't provided tags for this work yet. Pull down to get the latest details from AO3."
        val imported = "This imported work isn't linked to AO3, so you won't see AO3 tags here."
        compose.onNodeWithText(remote).assertExists()
        compose.runOnIdle { ao3 = false }
        compose.onNodeWithText(remote).assertDoesNotExist()
        compose.onNodeWithText(imported).assertExists()
        compose.runOnIdle { tags = listOf("Fluff") }
        compose.onNodeWithText(imported).assertDoesNotExist()
        compose.onNodeWithText("Fluff").assertExists()
    }
}
