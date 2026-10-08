package io.github.cidy02.kudos.account

import android.app.Application
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.app.Routes
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
class AO3ChallengeSignUpScreenTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var client: PromptMemeReadClient
    private val routes = mutableListOf<String>()
    private val chrome = PushedShellChrome()

    private fun show(fixture: String = signUpFixtures[0], entry: String = "direct", signedIn: Boolean = true,
        theme: KudosThemeMode = KudosThemeMode.Light, scale: Float = 1f) {
        val (auth, reads, repo) = runBlocking { promptMemeSetup(signedIn) }
        client = reads
        val form = signUpForm(fixture)
        val url = AO3ChallengeSignUpUrls.form(form.slug, form.signUpID)
        client.replies[url] = challengeResponse(url, challengeFixture(fixture))
        client.postReply = challengeResponse(form.actionUrl, challengeFixture("ao3_demo_signup_saved"))
        compose.setContent {
            var opened by remember { mutableStateOf(entry == "direct") }
            KudosTheme(themeMode = theme) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale), LocalPushedShellChrome provides chrome) {
                    val open = { routes += Routes.ao3ChallengeSignUp(form.slug, "Demo challenge"); opened = true }
                    if (opened) AO3ChallengeSignUpScreen(form.slug, "Demo challenge", form.signUpID, repo, promptMemeWrites(client, auth))
                    else if (entry == "manage") CollectionManageRow("Your Sign-up", url,
                        onOpenModeration = { error("Wrong route") }, onOpenSettings = { error("Wrong route") },
                        onOpenMaintainers = { error("Wrong route") }, onOpenWebFallback = { error("Opened browser") }, onOpenSignUp = open)
                    else AO3PromptMemeScreen("summer_meme", "Summer Prompt Meme", false, repo, promptMemeWrites(client, auth),
                        onOpenWeb = { error("Opened browser") }, onOpenSignUp = open)
                }
            }
        }
    }
    private fun await(text: String, substring: Boolean = false) = compose.waitUntil(15_000) {
        compose.onAllNodesWithText(text, substring = substring).fetchSemanticsNodes().isNotEmpty()
    }
    private fun reach(text: String) = compose.onNodeWithTag("Challenge sign-up").performScrollToNode(hasText(text))

    @Test fun collectionYourSignUpOpensNativeFormWithOneReadNoPostAndNoWithdrawal() {
        show(entry = "manage")
        compose.onNodeWithText("Your Sign-up").performClick()
        await("REQUEST 1") // a section header is drawn in capitals
        assertEquals(listOf(Routes.ao3ChallengeSignUp("winter_exchange", "Demo challenge")), routes)
        assertEquals(listOf(AO3ChallengeSignUpUrls.form("winter_exchange")), client.gets)
        assertEquals(0, client.posts)
        compose.onNodeWithText("Withdraw").assertDoesNotExist()
        compose.onNodeWithText("Withdraw sign-up").assertDoesNotExist()
    }

    @Test fun memeNewPromptOpensSameNativeRequestOnlyFormWithOneAdditionalRead() {
        show(signUpFixtures[2], entry = "meme")
        await("New prompt")
        compose.onNodeWithText("New prompt").performClick()
        await("REQUEST 1") // a section header is drawn in capitals
        assertEquals(listOf(Routes.ao3ChallengeSignUp("summer_meme", "Demo challenge")), routes)
        assertEquals(listOf(promptFirstUrl, AO3ChallengeSignUpUrls.form("summer_meme")), client.gets)
        assertEquals(0, client.posts)
        compose.onNodeWithText("OFFERS").assertDoesNotExist()
        compose.onNodeWithText("Add an offer").assertDoesNotExist()
        compose.onNodeWithText("Withdraw sign-up").assertDoesNotExist()
    }

    @Test fun existingFormKeepsIosSectionsAndNoWithdrawalControl() {
        show(signUpFixtures[1])
        await("REQUEST 1") // a section header is drawn in capitals
        reach("Offer 1")
        compose.onNodeWithText("Offer 1").assertExists()
        compose.onNodeWithText("Withdraw").assertDoesNotExist()
        compose.onNodeWithText("Withdraw sign-up").assertDoesNotExist()
        assertEquals(1, client.gets.size)
        assertEquals(0, client.posts)
    }

    @Test fun localTagsEditorGetsShellChromeBackAndItsFourIosFieldsWithoutReads() {
        show()
        await("Fandoms")
        val previous = chrome.holder
        compose.onNodeWithText("Fandoms").performClick()
        await("Comma-separated tag names")
        compose.onAllNodesWithContentDescription("Fandoms").filter(hasSetTextAction()).onFirst().performTextReplacement("The Lantern Archipelago, Cloudbound Courier")
        assertNotEquals(previous, chrome.holder)
        assertNotNull(chrome.trailingContent)
        assertNotNull(chrome.onBack)
        compose.runOnIdle { chrome.onBack!!.invoke() }
        await("REQUEST 1") // a section header is drawn in capitals
        assertEquals(1, client.gets.size)
        assertEquals(0, client.posts)
        assertNull(chrome.trailingContent)
    }

    @Test fun refusalReasonsKeepTypedPromptAndSuccessShowsOnlyAfterPost() {
        show()
        await("Prompt")
        compose.onAllNodesWithContentDescription("Prompt").filter(hasSetTextAction()).onFirst().performTextReplacement("Uncharted Lantern & typed 星")
        val refusal = challengeFixture(signUpFixtures[0]).replace("</main>", challengeFixture("ao3_demo_signup_refused") + "</main>")
        compose.runOnIdle { client.postReply = challengeResponse(AO3ChallengeSignUpUrls.form("winter_exchange"), refusal) }
        compose.onNodeWithText("Submit sign-up").performClick()
        await("Description contains Uncharted Lantern", true)
        compose.onNodeWithText("Please revise your prompt and submit again.").assertExists()
        compose.onNodeWithText("Sign-up submitted successfully!").assertDoesNotExist()
        reach("Prompt")
        compose.onNodeWithText("Uncharted Lantern & typed 星").assertExists()
        assertEquals(1, client.posts)
        assertEquals(2, client.gets.size)
        compose.runOnIdle { client.postReply = challengeResponse(AO3ChallengeSignUpUrls.form("winter_exchange"), challengeFixture("ao3_demo_signup_saved")) }
        compose.onNodeWithText("Submit sign-up").performClick()
        await("Sign-up submitted successfully!")
        assertEquals(2, client.posts)
        assertEquals(3, client.gets.size)
    }

    @Test fun signedOutShowsFailureAndReadsNothing() {
        show(signedIn = false)
        await("Couldn't load sign-up")
        compose.onNodeWithText("Log in to AO3 before using this feature.").assertExists()
        assertTrue(client.gets.isEmpty())
        assertEquals(0, client.posts)
        compose.onNodeWithText("Try Again").assertIsNotEnabled()
    }

    @Test fun largeTextLabelsAndActionsHaveHeightAndLastLineInEachTheme() {
        // A single composition, cycled through the four token themes; no renderer assumptions.
        val (_, reads, repo) = runBlocking { promptMemeSetup() }
        val url = AO3ChallengeSignUpUrls.form("winter_exchange")
        reads.replies[url] = challengeResponse(url, challengeFixture(signUpFixtures[0]))
        var theme by mutableStateOf(KudosThemeMode.Light)
        compose.setContent {
            KudosTheme(themeMode = theme) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, 1.8f)) {
                    AO3ChallengeSignUpScreen("winter_exchange", "Winter Exchange 2026", repository = repo,
                        writes = remember { promptMemeWrites(reads, repo.authRepository) })
                }
            }
        }
        await("REQUEST 1") // a section header is drawn in capitals
        for (mode in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { theme = mode }
            for (label in listOf("Add request", "Submit sign-up")) {
                val layouts = mutableListOf<TextLayoutResult>()
                compose.onNodeWithText(label).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
                assertTrue(layouts.isNotEmpty())
                assertTrue(layouts.all { !it.didOverflowHeight && !it.isLineEllipsized(it.lineCount - 1) })
            }
        }
        assertEquals(1, reads.gets.size)
        assertEquals(0, reads.posts)
    }
}
