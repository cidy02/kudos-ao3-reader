package io.github.cidy02.kudos.library

import androidx.compose.ui.semantics.getOrNull
import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.*
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.search.FilterFacetRow
import io.github.cidy02.kudos.search.FilterRangeSlider
import io.github.cidy02.kudos.search.FilterSelectionState
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1800dp")
class Brief3gpSpokenLabelsTest {
    @get:Rule val compose = createComposeRule()

    @Test fun favoriteDescriptionNamesNewestWorkMetadataAndUnreadOrFallsBackToLibrary() {
        val work = AO3WorkSummary(1, "A new story", listOf("A"), emptyList(), "", emptyList(), emptyList(),
            wordCount = 1200, updatedDate = "2 Sep 2026")
        var newest by mutableStateOf<AO3WorkSummary?>(work)
        var unread by mutableStateOf(true)
        var opened = 0
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                FavoriteAffinityRow(ReadingAffinities.Row("A", worksRead = 2, username = "A"), FavoriteScope.Authors, {},
                    newestWork = newest, newestWorkUnread = unread, onOpenNewestWork = { opened++ })
            }
        }
        compose.onNodeWithContentDescription("A. 2 works read. Newest work: A new story, updated 2 Sep 2026 · 1.2K words. Unread.").assertExists()
        val link = compose.onNode(SemanticsMatcher("title-specific click label") {
            it.config.getOrNull(SemanticsActions.OnClick)?.label == "open A new story"
        })
        link.performClick()
        assertEquals(1, opened)
        compose.runOnIdle { unread = false }
        compose.onNodeWithContentDescription("A. 2 works read. Newest work: A new story, updated 2 Sep 2026 · 1.2K words.").assertExists()
        compose.runOnIdle { newest = null }
        compose.onNodeWithContentDescription("A. 2 works read. No unread works in your library").assertExists()
    }

    @Test fun facetsSpeakIncludedExcludedOrNoStateAndKeepTheirClickAction() {
        var state by mutableStateOf(FilterSelectionState.CLEAR)
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) { FilterFacetRow("Warning", state) { state = state.next } }
        }
        val facet = compose.onNodeWithText("Warning")
        assertNull(facet.fetchSemanticsNode().config.getOrNull(SemanticsProperties.StateDescription))
        assertEquals("include", facet.fetchSemanticsNode().config[SemanticsActions.OnClick].label)
        facet.performClick()
        facet.assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Included"))
        assertEquals("exclude", facet.fetchSemanticsNode().config[SemanticsActions.OnClick].label)
        facet.performClick()
        facet.assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Excluded"))
        assertEquals("clear", facet.fetchSemanticsNode().config[SemanticsActions.OnClick].label)
        facet.performClick()
        assertNull(facet.fetchSemanticsNode().config.getOrNull(SemanticsProperties.StateDescription))
    }

    @Test fun rangeHasOneCombinedValueIncludingOpenAndNumericBoundsAndKeepsAdjustableThumbs() {
        var from by mutableStateOf("")
        var to by mutableStateOf("")
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) { FilterRangeSlider(from, to, 100000) { lower, upper -> from = lower; to = upper } }
        }
        val range = compose.onNodeWithContentDescription("Range")
        range.assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Any to Any"))
        compose.runOnIdle { from = "001000" }
        range.assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "1000 to Any"))
        compose.runOnIdle { to = "2500" }
        range.assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "1000 to 2500"))
        compose.runOnIdle { from = "" }
        range.assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Any to 2500"))
        compose.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsActions.SetProgress), useUnmergedTree = true).assertCountEquals(2)
    }

    @Test fun favoriteStripsHaveNamedSelectedOptionsWithoutExtraGroupDescriptions() {
        var prefs by mutableStateOf(FavoritePreferences(scope = FavoriteScope.Authors))
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                Column { FavoriteScopesStrip(prefs, { prefs = prefs.copy(scope = it) }, { prefs = prefs.copy(order = it) }, {}) }
            }
        }
        compose.onNodeWithContentDescription("Favorites scope").assertDoesNotExist()
        compose.onNodeWithContentDescription("Favorites order").assertDoesNotExist()
        compose.onNode(hasText("Authors") and isSelected()).assertHasClickAction()
        compose.onNodeWithText("Most time").performClick()
        compose.onNode(hasText("Most time") and isSelected()).assertExists()
        compose.onNodeWithText("Works").performClick()
        compose.onNode(hasText("Works") and isSelected()).assertExists()
    }
}
