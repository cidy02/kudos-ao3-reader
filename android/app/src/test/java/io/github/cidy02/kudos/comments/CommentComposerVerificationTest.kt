package io.github.cidy02.kudos.comments

import android.app.Application
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
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
