package io.github.cidy02.kudos.ui.subject

import android.app.Application
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Selection must stay crisp while the work itself is blurred (A73 finding 5): the checkbox sits
 * beside the blurred content, not inside it. Structural, because Robolectric's pixel capture
 * times out here. A hidden row clears its semantics, so the layout is read unhidden; the blur
 * only toggles on the same box.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class WorkLedgerRowSelectionTest {
    @get:Rule val compose = createComposeRule()

    @Test fun theSelectionCheckboxIsNotInsideTheBlurredWorkContent() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                WorkLedgerRow(
                    title = "Private work", author = "Private author", fandoms = listOf("Private fandom"),
                    metadata = "Private author · 1,200 words · 1/1", progress = 0.4, progressState = "Reading",
                    rating = "Explicit", categories = listOf("F/M"), warnings = emptyList(), isComplete = true,
                    obscured = false, favorite = false, selected = true, selecting = true,
                    onClick = {}, onLongClick = {}
                )
            }
        }
        compose.onNode(hasTestTag(WORK_LEDGER_CONTENT_TAG), useUnmergedTree = true).assertExists()
        compose.onNode(isToggleable(), useUnmergedTree = true).assertExists()
        compose.onNode(isToggleable() and hasAnyAncestor(hasTestTag(WORK_LEDGER_CONTENT_TAG)), useUnmergedTree = true)
            .assertDoesNotExist()
    }
}
