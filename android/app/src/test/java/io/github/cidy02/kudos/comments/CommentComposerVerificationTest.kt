package io.github.cidy02.kudos.comments

import android.app.Application
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.isFocused
import androidx.compose.ui.test.hasContentDescription
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1600dp")
class CommentComposerVerificationTest {
    @get:Rule val compose = createComposeRule()

    /** iOS raises the keyboard as the composer opens: its text field takes focus. */
    @Test fun theTextFieldIsFocusedWhenTheComposerOpens() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CommentComposerSheet(null, null, "", {}, submitting = false, currentUsername = "Reader",
                    isScopeByChapter = true, palette = LocalKudosTokens.current.scopePalette,
                    onDismiss = {}, onSubmit = {}, onOpenAuthor = {})
            }
        }
        compose.waitUntil(5_000) {
            compose.onAllNodes(hasContentDescription("Comment text") and isFocused(), useUnmergedTree = true)
                .fetchSemanticsNodes().isNotEmpty()
        }
    }

    @Test fun checkingSentenceIsInTheComposerOnlyWhileVerifying() {
        var checking by mutableStateOf(false)
        val sentence = "We're checking whether this posted before trying again…"
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CommentComposerSheet(null, null, "Draft", {}, submitting = checking, currentUsername = "Reader",
                    isScopeByChapter = true, palette = LocalKudosTokens.current.scopePalette,
                    onDismiss = {}, onSubmit = {}, onOpenAuthor = {}, verifying = checking)
            }
        }
        compose.onNodeWithText(sentence).assertDoesNotExist()
        compose.runOnIdle { checking = true }
        compose.onNodeWithText(sentence).assertExists()
        compose.onNodeWithText("Cancel").assertIsNotEnabled()
        compose.runOnIdle { checking = false }
        compose.onNodeWithText(sentence).assertDoesNotExist()
    }
}
