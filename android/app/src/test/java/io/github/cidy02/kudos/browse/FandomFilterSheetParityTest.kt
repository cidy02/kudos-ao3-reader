package io.github.cidy02.kudos.browse

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
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
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h700dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class FandomFilterSheetParityTest {
    @Test fun dismissCancelsTheDraft() {
        var applied: FandomListFilterOptions? = null
        var closed = false
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            FandomListFilterSheet(FandomListFilterOptions(), emptyList(), true, FandomLibraryIndex.empty,
                LocalKudosTokens.current.scopePalette, onApply = { applied = it }, onDismiss = { closed = true })
        } }
        compose.onNodeWithContentDescription("Favourited only").performScrollTo().assertIsOff().performClick().assertIsOn()
        compose.onNode(SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsActions.Dismiss))
            .performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.Dismiss) { it() }
        compose.runOnIdle { assertTrue(closed); assertNull(applied) }
    }

    @get:Rule val compose = createComposeRule()

    @Test fun showTagsStaysVisibleAtLargestTextAndAppliesTheChoices() {
        var applied: FandomListFilterOptions? = null
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, 2f)) {
                    FandomListFilterSheet(FandomListFilterOptions(),
                        FandomFamily.grouped(listOf(AO3Fandom("Doctor Who", 500))), true, FandomLibraryIndex.empty,
                        LocalKudosTokens.current.scopePalette, onApply = { applied = it }, onDismiss = {})
                }
            }
        }
        compose.onNodeWithText("Show 1 tags").assertIsDisplayed()
        compose.onNodeWithContentDescription("Favourited only").performScrollTo().assertIsOff().performClick().assertIsOn()
        compose.onNodeWithContentDescription("Only fandoms with more than one tag").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Show 0 tags").assertIsDisplayed().performClick()
        compose.runOnIdle { assertTrue(applied?.favouritedOnly == true) }
    }
}
