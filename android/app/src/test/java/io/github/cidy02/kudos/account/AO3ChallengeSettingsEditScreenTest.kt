package io.github.cidy02.kudos.account

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.account.*
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
class AO3ChallengeSettingsEditScreenTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var client: ChallengeEditClient
    private val web = mutableListOf<String>()
    private val tags = mutableListOf<Int>()
    private var collectionOpened = false
    private var backed = false
    private fun show(meme: Boolean = false, theme: KudosThemeMode = KudosThemeMode.Light, scale: Float = 1f) {
        val (auth, reads, repository) = runBlocking { challengeEditSetup(meme) }
        client = reads
        compose.setContent {
            KudosTheme(themeMode = theme) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale)) {
                    AO3ChallengeSettingsEditScreen(client.slug, if (meme) "Summer Prompt Meme" else "Winter Exchange 2026", true,
                        repository, client.writer(auth), onOpenWeb = { web += it }, onOpenTagSet = { id, _ -> tags += id },
                        onOpenCollection = { collectionOpened = true }, onBack = { backed = true })
                }
            }
        }
        await("BASICS")
        compose.waitForIdle()
        compose.waitUntil(20_000) { client.gets.size == client.openingReads.size }
        assertTrue(client.sent.isEmpty())
    }
    private fun await(text: String) {
        compose.waitUntil(20_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
    }
    private fun reach(text: String) {
        compose.onNodeWithTag("Challenge settings edit").performScrollToNode(hasText(text))
        await(text)
    }
    private fun click(text: String) { reach(text); compose.onNodeWithText(text).performClick(); compose.waitForIdle() }

    @Test fun giftSectionsBasicsLinksMatchingChoicesAndSaveRefusalKeepTypedInstructions() {
        show()
        assertEquals(1, compose.onAllNodesWithText("Save changes").fetchSemanticsNodes().size)
        assertFalse(compose.onAllNodesWithText("Cancel").fetchSemanticsNodes().isNotEmpty())
        click("Name"); assertTrue(collectionOpened)
        reach("Sign-up instructions")
        compose.onNodeWithContentDescription("Sign-up instructions").performTextReplacement("Typed moderator instructions")
        client.postResult = AO3Result.Success(AO3HttpResponse("https://archiveofourown.org", 422, emptyMap(), "<div class='flash error'>AO3 refused these instructions.</div>"))
        compose.onNodeWithText("Save changes").performClick()
        await("AO3 refused these instructions.")
        reach("Sign-up instructions")
        compose.onNodeWithContentDescription("Sign-up instructions").assertTextEquals("Typed moderator instructions")
        reach("SCHEDULE"); reach("Assignments sent"); compose.onNodeWithText("Manual").assertExists()
        reach("SIGN-UP LIMITS"); compose.onNodeWithText("Offers").assertExists()
        reach("TAG SETS"); click("Winter Exchange Tags"); assertEquals(listOf(42), tags)
        reach("MATCHING"); compose.onNodeWithText("Match on").assertExists()
        click("Requests that must match"); await("All"); compose.onNodeWithText("All").performClick()
        click("Run matching"); click("Delete challenge")
        assertEquals(listOf(ChallengeSettingsDestinations.runMatching(client.slug), client.edit), web)
        assertEquals(1, client.sent.size)
    }

    @Test fun memeShowsLockedRowsOwnAnonymousSwitchAndNoMatchingChoices() {
        show(meme = true, theme = KudosThemeMode.Dark)
        reach("Requests")
        compose.onNodeWithText("Offers").assertDoesNotExist()
        reach("Optional tags allowed")
        compose.onNodeWithContentDescription("Optional tags allowed").assertIsNotEnabled()
        reach("Prompts have been added so these settings can no longer be changed.")
        reach("TAG SET")
        compose.onNodeWithText("Summer Prompt Tags").assertExists()
        reach("MATCHING")
        compose.onNodeWithText("Requests that must match").assertDoesNotExist()
        reach("Prompts posted anonymously")
        compose.onNodeWithContentDescription("Prompts posted anonymously").assertIsOn()
        compose.onNodeWithContentDescription("Prompts posted anonymously").performClick()
        compose.onNodeWithText("Save changes").performClick()
        await("Challenge updated.")
        compose.waitForIdle()
        compose.waitUntil(20_000) { client.sent.size == 1 }
        assertEquals(1, client.sent.size)
        assertFalse(client.sent.single().fields.any { it.first == "prompt_meme[anonymous]" }) // no hidden twin was served
        compose.onNodeWithText("Reveal now?").assertDoesNotExist()
    }

    @Test fun revealIsAskedOnlyOnSaveAndCancelSendsNothingThenConfirmedSaveSendsBothForms() {
        show(theme = KudosThemeMode.Sepia)
        reach("Anonymous until reveal")
        compose.onNodeWithContentDescription("Anonymous until reveal").performClick()
        compose.onNodeWithText("Save changes").performClick()
        await("Reveal now?")
        assertTrue(client.sent.isEmpty())
        assertEquals(client.openingReads, client.gets)
        compose.onNodeWithText("Cancel").performClick()
        assertTrue(client.sent.isEmpty())
        compose.onNodeWithText("Save changes").performClick()
        await("You can't reverse either change in Kudos.", substring = true)
        compose.onNodeWithText("Save and reveal").performClick()
        compose.waitForIdle()
        compose.waitUntil(20_000) { client.sent.size == 2 }
        await("Challenge updated. Challenge updated.")
        assertEquals(listOf(client.edit, client.collectionEdit), client.gets.takeLast(2))
    }

    @Test fun oledAccessibilityRowsUseHeightAndLastLineChecksAndDisabledSwitchIsNotClickable() {
        show(meme = true, theme = KudosThemeMode.Oled, scale = 2f)
        for (label in listOf("Description required", "Optional tags allowed", "Fandoms required per request", "Anonymous until reveal", "Closed to new sign-ups")) {
            reach(label)
            val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithText(label).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) {
                assertTrue(it(layouts))
            }
            assertTrue(layouts.isNotEmpty())
            assertTrue(layouts.all { !it.didOverflowHeight && !it.isLineEllipsized(it.lineCount - 1) })
        }
        reach("Optional tags allowed")
        compose.onNodeWithContentDescription("Optional tags allowed").assertIsNotEnabled()
        reach("Prompts posted anonymously")
        compose.onNodeWithContentDescription("Prompts posted anonymously").assertIsEnabled()
        compose.onNodeWithText("Save changes").assertExists()
    }

    private fun await(text: String, substring: Boolean) {
        compose.waitUntil(20_000) { compose.onAllNodesWithText(text, substring = substring).fetchSemanticsNodes().isNotEmpty() }
    }
}
