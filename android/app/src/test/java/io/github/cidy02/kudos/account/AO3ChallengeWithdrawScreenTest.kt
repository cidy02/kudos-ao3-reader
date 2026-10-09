package io.github.cidy02.kudos.account

import android.app.Application
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1800dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AO3ChallengeWithdrawScreenTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var client: PromptMemeReadClient
    private val dismissed = mutableListOf<String>()
    private fun show(reply: String = "ao3_demo_signup_withdrawn", theme: KudosThemeMode = KudosThemeMode.Light, scale: Float = 1f) {
        val (auth, reads, repo) = runBlocking { withdrawalSetup() }
        client = reads
        client.postReply = challengeResponse(withdrawAction, challengeFixture(reply))
        compose.setContent {
            KudosTheme(themeMode = theme) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale)) {
                    AO3ChallengeSignUpScreen("winter_exchange", "Winter Exchange 2026", 4, repo, promptMemeWrites(client, auth),
                        onWithdrawn = { dismissed += it })
                }
            }
        }
    }
    private fun awaitText(text: String) = compose.waitUntil(15_000) {
        compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
    }
    private fun reach(text: String) = compose.onNodeWithTag("Challenge sign-up").performScrollToNode(hasText(text))
    private fun confirm() {
        reach("Withdraw sign-up"); compose.onNodeWithText("Withdraw sign-up").performClick()
        awaitText("Withdraw this sign-up?")
        compose.onNodeWithText("Withdrawing removes your requests and offers from Winter Exchange 2026.").assertExists()
        compose.onNodeWithText("Withdraw Sign-up").performClick()
    }

    @Test fun cancelMakesNoTokenReadConfirmedWriteLeavesAndReportsExactNotice() {
        show()
        awaitText("REQUEST 1")
        reach("Withdraw sign-up"); compose.onNodeWithText("Withdraw sign-up").performClick()
        awaitText("Withdraw this sign-up?")
        assertEquals(listOf(withdrawForm), client.gets)
        compose.onNodeWithText("Cancel").performClick()
        assertEquals(0, client.posts); assertTrue(dismissed.isEmpty())
        confirm()
        compose.waitForIdle()
        compose.waitUntil(15_000) { dismissed.isNotEmpty() }
        assertEquals(listOf("Sign-up withdrawn."), dismissed)
        assertEquals(listOf(withdrawForm, withdrawConfirm), client.gets)
        assertEquals(1, client.posts)
    }

    @Test fun refusalIsAo3sReasonAloneFormKeepsTypedTextAndWithdrawBecomesAvailableAgain() {
        show("ao3_demo_signup_withdraw_refused", KudosThemeMode.Sepia, 1.8f)
        awaitText("REQUEST 1")
        reach("Prompt")
        compose.onAllNodesWithContentDescription("Prompt").filter(hasSetTextAction()).onFirst().performTextReplacement("A writer's unfinished lantern story")
        confirm()
        awaitText("Sign-ups are closed. You cannot delete your sign-up.")
        assertEquals(1, compose.onAllNodesWithText("Sign-ups are closed. You cannot delete your sign-up.").fetchSemanticsNodes().size)
        assertTrue(dismissed.isEmpty())
        reach("Prompt"); compose.onNodeWithText("A writer's unfinished lantern story").assertExists()
        reach("Withdraw sign-up"); compose.onNodeWithText("Withdraw sign-up").assertIsEnabled()
        val layouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText("Withdraw sign-up").performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        assertTrue(layouts.isNotEmpty())
        assertTrue(layouts.all { !it.didOverflowHeight && !it.isLineEllipsized(it.lineCount - 1) })
        assertEquals(listOf(withdrawForm, withdrawConfirm), client.gets); assertEquals(1, client.posts)
    }

    @Test fun unconfirmedIsNotPrefixedWithNotWithdrawnAndDoesNotDismiss() {
        show(theme = KudosThemeMode.Oled)
        compose.runOnIdle { client.postReply = challengeResponse(withdrawAction, "<p>No confirmation</p>") }
        awaitText("REQUEST 1")
        confirm()
        awaitText(io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields.UNCONFIRMED)
        assertTrue(dismissed.isEmpty())
        reach("Withdraw sign-up"); compose.onNodeWithText("Withdraw sign-up").assertIsEnabled()
        assertEquals(1, client.posts)
    }
}
