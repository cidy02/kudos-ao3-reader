package io.github.cidy02.kudos.search

import android.app.Application
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollToNode
import io.github.cidy02.kudos.network.ao3.search.AO3Category
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3Warning
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** A-509c item 3: the Search sheet's warnings and categories are symbol cards, as iOS `AO3FilterPanel`. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1600dp")
class SearchFilterSheetSymbolCardsTest {
    @get:Rule val compose = createComposeRule()

    @Test fun warningsAndCategoriesAreCardsNotWordRows() {
        val filters = cycleCategory(cycleWarning(AO3SearchFilters(), AO3Warning.VIOLENCE), AO3Category.entries.first())
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                SearchFilterSheet(filters, {}, {}, {}, {}, fandomContext = emptyList(), refine = true, canReset = false)
            }
        }
        val form = compose.onNodeWithTag("AO3 filter form")
        form.performScrollToNode(hasContentDescription(AO3Warning.VIOLENCE.title))
        val warning = compose.onNodeWithContentDescription(AO3Warning.VIOLENCE.title).fetchSemanticsNode().config
        assertEquals("Included", warning.getOrNull(SemanticsProperties.StateDescription))
        // The two groups AO3 prints.
        compose.onNodeWithText("OVERALL").assertExists()
        compose.onNodeWithText("CONTENT").assertExists()
        form.performScrollToNode(hasText(AO3Category.entries.first().title))
        // Cards carry iOS's check circle, not the word rows' "Include" / "Exclude".
        compose.onAllNodesWithTag(FACET_STATUS_WORD_TAG, useUnmergedTree = true).assertCountEquals(0)
    }
}
