package io.github.cidy02.kudos.account

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.Density
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.graphics.Color
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
    private lateinit var view: View
    private fun show(meme: Boolean = false, theme: KudosThemeMode = KudosThemeMode.Light, scale: Float = 1f, knownTotal: Int? = null) {
        val (auth, reads, repository) = runBlocking { challengeEditSetup(meme) }
        client = reads
        compose.setContent {
            KudosTheme(themeMode = theme) {
                view = LocalView.current
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale)) {
                    AO3ChallengeSettingsEditScreen(client.slug, if (meme) "Summer Prompt Meme" else "Winter Exchange 2026", true,
                        repository, client.writer(auth), onOpenWeb = { web += it }, onOpenTagSet = { id, _ -> tags += id },
                        onOpenCollection = { collectionOpened = true }, onBack = { backed = true }, knownSignUpTotal = knownTotal)
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

    @Test fun instructionsAndPlaceholderUseFourteenSpSerif() {
        io.github.cidy02.kudos.network.ao3.DemoNetwork.resetForTests()
        io.github.cidy02.kudos.app.DebugShotRequests.clear()
        show()
        reach("SIGN-UP INSTRUCTIONS")
        val field = compose.onNodeWithContentDescription("Sign-up instructions")
        field.performTextClearance()
        compose.waitForIdle()
        val placeholderLayouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
        compose.onNodeWithText("Describe the challenge for people signing up…", useUnmergedTree = true)
            .performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { it(placeholderLayouts) }
        field.performTextInput("Challenge instructions")
        val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
        field.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { it(layouts) }
        for (layout in placeholderLayouts + layouts) {
            assertEquals(androidx.compose.ui.text.font.FontFamily.Serif, layout.layoutInput.style.fontFamily)
            assertEquals(14.sp, layout.layoutInput.style.fontSize)
        }
        assertTrue(placeholderLayouts.isNotEmpty() && layouts.isNotEmpty())
    }

    @Test fun titleSubtitleAndFilledSaveStayVisibleWhileScheduleScrolls() {
        show(scale = 2f)
        // iOS effectiveTitle. This fixture is paginated: an unknown total must stay unknown, never
        // become its page size, so the subtitle is the title alone.
        // The form's Name row carries the title too; this is the header's line.
        compose.onNode(hasText("Winter Exchange 2026") and !hasText("Name")).assertExists()
        compose.onNodeWithText(client.slug).assertDoesNotExist()
        val save = compose.onNodeWithText("Save changes")
        val before = save.fetchSemanticsNode().boundsInRoot
        var fill = Color.Unspecified
        compose.runOnIdle {
            val image = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(Canvas(image))
            fill = Color(image.getPixel((before.left + 20).toInt(), before.center.y.toInt()))
            image.recycle()
        }
        val expected = io.github.cidy02.kudos.ui.subject.SubjectPalette.fromHue(
            io.github.cidy02.kudos.home.HomeFacts.workHue(emptyList(), "Winter Exchange 2026"),
            io.github.cidy02.kudos.ui.subject.ReaderTheme.Light).accent
        assertEquals(expected.red, fill.red, 0.012f)
        assertEquals(expected.green, fill.green, 0.012f)
        assertEquals(expected.blue, fill.blue, 0.012f)
        reach("Assignments sent")
        compose.onNodeWithText("Manual").assertExists()
        val after = save.assertIsDisplayed().fetchSemanticsNode().boundsInRoot
        assertEquals(before.top, after.top, 1f)
        reach("SIGN-UP INSTRUCTIONS")
        compose.onNodeWithContentDescription("Sign-up instructions").performTextReplacement("Updated instructions")
        save.performClick()
        compose.waitUntil(20_000) { client.sent.isNotEmpty() }
    }

    @Test fun paginatedEditorKeepsTheTotalAlreadyReadByTheChallengePageWithoutAnotherRead() {
        show(knownTotal = 1)
        compose.onNodeWithText("Winter Exchange 2026 · 1 sign-up").assertExists()
        assertEquals(client.openingReads, client.gets)
    }

    @Test fun theEditPagesOwnCountWinsAndTakesThePlural() {
        show(meme = true, knownTotal = 4)
        compose.onNodeWithText("Summer Prompt Meme · 0 sign-ups").assertExists()
    }

    /** A92: when the edit page has no count (paginated), the one Challenge Settings already read is used. */
    @Test fun aKnownTotalFillsInWhenTheEditPageHasNone() {
        show(knownTotal = 4)
        compose.onNodeWithText("Winter Exchange 2026 · 4 sign-ups").assertExists()
    }

    @Test fun limitValidationErrorPrecedesTheLimitsPanel() {
        show()
        reach("Requests")
        compose.onNodeWithTag("Requests required").performClick()
        compose.onNodeWithTag("Challenge settings choices").performScrollToNode(hasText("20"))
        compose.onNodeWithText("20").performClick()
        compose.onNodeWithText("Save changes").performClick()
        compose.waitForIdle()
        val error = "Allowed requests cannot be fewer than required requests."
        reach(error)
        compose.onNodeWithText(error).assertIsDisplayed()
        val errorBounds = compose.onNodeWithText(error, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val rowBounds = compose.onNodeWithText("Requests", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue(errorBounds.top < rowBounds.top)
        assertTrue(client.sent.isEmpty())
    }

    @Test fun giftSectionsBasicsLinksMatchingChoicesAndSaveRefusalKeepTypedInstructions() {
        show()
        assertEquals(1, compose.onAllNodesWithText("Save changes").fetchSemanticsNodes().size)
        assertFalse(compose.onAllNodesWithText("Cancel").fetchSemanticsNodes().isNotEmpty())
        click("Name"); assertTrue(collectionOpened)
        reach("SIGN-UP INSTRUCTIONS")
        compose.onNodeWithText("Sign-up instructions").assertDoesNotExist()
        compose.onNodeWithContentDescription("Sign-up instructions").performTextReplacement("Typed moderator instructions")
        client.postResult = AO3Result.Success(AO3HttpResponse("https://archiveofourown.org", 422, emptyMap(), "<div class='flash error'>AO3 refused these instructions.</div>"))
        compose.onNodeWithText("Save changes").performClick()
        await("AO3 refused these instructions.")
        reach("SIGN-UP INSTRUCTIONS")
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
