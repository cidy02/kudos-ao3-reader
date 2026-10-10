package io.github.cidy02.kudos.account

import android.app.Application
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.app.Routes
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.account.ChallengeSettingsDestinations
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
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1600dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AO3ChallengeSettingsScreenTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var client: ChallengeReadClient
    private var edits = 0
    private val browser = mutableListOf<String>()
    private val external = mutableListOf<String>()
    private val native = mutableListOf<String>()

    private fun show(owner: Boolean = true, meme: Boolean = false, countFails: Boolean = false,
        signedIn: Boolean = true, formFails: Boolean = false, theme: KudosThemeMode = KudosThemeMode.Light,
        scale: Float = 1f, fromManage: Boolean = false, hold: Boolean = false) {
        val (_, reads, repository) = runBlocking { challengeSetup(signedIn) }
        client = reads
        client.hold = hold
        if (meme) {
            client.replies[giftUrl] = AO3Result.Failure(AO3Error.NotFound)
            client.replies[profileUrl] = challengeResponse(profileUrl,
                "<dl><dt>Tag set:</dt><dd><a href='/tag_sets/44'>Summer Prompt Tags</a></dd></dl>")
        }
        if (countFails) client.replies[signupUrl] = AO3Result.Failure(AO3Error.Forbidden)
        if (formFails) client.replies[giftUrl] = AO3Result.Failure(AO3Error.Forbidden)
        compose.setContent {
            var opened by remember { mutableStateOf(!fromManage) }
            KudosTheme(themeMode = theme) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale)) {
                    if (!opened) CollectionManageRow("Challenge Settings", giftUrl,
                        onOpenModeration = { error("Wrong moderation route") }, onOpenSettings = { error("Wrong collection settings route") },
                        onOpenMaintainers = { error("Wrong maintainers route") }, onOpenWebFallback = { error("Manage opened browser") },
                        onOpenChallengeSettings = {
                            native += Routes.ao3ChallengeSettings("winter_exchange", "Winter Exchange 2026", owner)
                            opened = true
                        })
                    else AO3ChallengeSettingsScreen("winter_exchange", "Winter Exchange 2026", owner, repository,
                        onOpenEditSettings = { edits++ },
                        onOpenWeb = { browser += it }, onOpenExternal = { external += it },
                        onOpenTagSet = { id, title -> native += Routes.ao3TagSet(id, title, isModerator = true) },
                        onOpenPrompts = { slug, title -> native += Routes.ao3PromptMeme(slug, title) },
                        onOpenSignUps = { slug, title -> native += Routes.ao3ChallengeSignUps(slug, title, owner, owner) },
                        onOpenAssignments = { slug, title, closed -> native += Routes.ao3ChallengeAssignments(slug, title, owner, owner, closed) })
                }
            }
        }
    }

    private fun awaitText(text: String) {
        compose.waitUntil(15_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
    }
    private fun reach(text: String) {
        compose.onNode(hasScrollAction()).performScrollToNode(hasText(text))
    }
    private fun click(text: String) { reach(text); compose.onNodeWithText(text).performClick() }

    @Test fun realManageRowOpensNativeScreenAndEveryGiftDisclosureHasItsExactDestination() {
        show(fromManage = true)
        compose.onNodeWithText("Challenge Settings").performClick()
        awaitText("Edit settings")
        assertEquals(listOf(Routes.ao3ChallengeSettings("winter_exchange", "Winter Exchange 2026", true)), native)
        assertEquals(4, client.gets.size)
        click("Edit settings")
        reach("TAG SETS")
        compose.onNodeWithText("TAG SET").assertDoesNotExist()
        click("Winter Exchange Tags")
        click("Snowbound Characters")
        click("Sign-ups")
        // Assignments is also a section heading; click only the disclosure row.
        reach("Defaults and pinch hits")
        compose.onAllNodesWithText("Assignments").filter(hasClickAction()).onFirst().performClick()
        compose.onNodeWithText("Defaults and pinch hits").performClick()
        click("Run matching")
        assertEquals(listOf(Routes.ao3ChallengeSettings("winter_exchange", "Winter Exchange 2026", true),
            Routes.ao3TagSet(42, "Winter Exchange Tags", true), Routes.ao3TagSet(43, "Snowbound Characters", true),
            Routes.ao3ChallengeSignUps("winter_exchange", "Winter Exchange 2026", true, true),
            Routes.ao3ChallengeAssignments("winter_exchange", "Winter Exchange 2026", true, true, false),
            Routes.ao3ChallengeAssignments("winter_exchange", "Winter Exchange 2026", true, true, false)), native)
        assertEquals(1, edits)
        assertTrue(browser.isEmpty())
        assertEquals(listOf(ChallengeSettingsDestinations.runMatching("winter_exchange")), external)
        compose.onNodeWithText("Prompts").assertDoesNotExist()
        assertEquals(4, client.gets.size) // row taps navigate; no native follow-up/read/write here
        assertEquals(0, client.posts)
    }

    @Test fun memeReplacesLowerHalfAndPromptsOpenNativeScreen() {
        show(meme = true)
        awaitText("Edit settings")
        compose.onNodeWithText("Winter Exchange 2026 · Prompt Meme").assertExists()
        click("Edit settings")
        reach("PROMPT REQUIREMENTS")
        compose.onNodeWithText("Prompts per sign-up").assertExists()
        compose.onNodeWithText("Fandoms per prompt").assertExists()
        compose.onNodeWithText("Require a fandom match").assertDoesNotExist()
        reach("TAG SET")
        compose.onNodeWithText("Summer Prompt Tags").assertExists()
        compose.onNodeWithText("Summer Prompt Tags").performClick()
        assertEquals(listOf(Routes.ao3TagSet(44, "Summer Prompt Tags", true)), native)
        compose.onNodeWithText("TAG SETS").assertDoesNotExist()
        reach("Prompts posted anonymously")
        compose.onNodeWithText("Claim and fill").performClick()
        compose.onNodeWithText("Yes").assertExists()
        compose.onNodeWithText("Assignments").assertDoesNotExist()
        compose.onNodeWithText("ASSIGNMENTS").assertDoesNotExist()
        compose.onNodeWithText("AT AO3").assertDoesNotExist()
        assertEquals(1, edits)
        assertTrue(browser.isEmpty())
        assertEquals(listOf(Routes.ao3TagSet(44, "Summer Prompt Tags", true),
            Routes.ao3PromptMeme("winter_exchange", "Winter Exchange 2026")), native)
        assertTrue(external.isEmpty())
        assertEquals(listOf(giftUrl, memeUrl, profileUrl), client.gets)
    }

    @Test fun failedSignupIsFailedButAssignmentRowsHaveNoInventedValues() {
        show(countFails = true)
        awaitText("Edit settings")
        reach("Defaults and pinch hits")
        compose.onNodeWithText("Couldn't load").assertExists()
        compose.onAllNodesWithText("Assignments").filter(hasClickAction()).onFirst().assertTextEquals("Assignments")
        compose.onNodeWithText("Defaults and pinch hits").assertTextEquals("Defaults and pinch hits")
        compose.onNodeWithText("None sent yet").assertDoesNotExist()
        compose.onNodeWithText("0 matched, 0 unmatched").assertDoesNotExist()
        compose.onNodeWithText("0").assertDoesNotExist()
        assertEquals(3, client.gets.size)
        assertTrue(client.gets.none { it.contains("assignments") })
    }

    @Test fun loadingShowsItsWordsAndHidesTheSectionsUntilTheRequiredReadFinishes() {
        show(hold = true)
        awaitText("Loading challenge settings…")
        compose.onNodeWithText("Edit settings").assertDoesNotExist()
        compose.onNodeWithText("TYPE").assertDoesNotExist()
        compose.runOnIdle { client.hold = false; client.release.complete(Unit) }
        awaitText("Edit settings")
        assertEquals(4, client.gets.size)
    }

    @Test fun signedOutFailureUsesIosWordsAndSendsNothing() {
        show(signedIn = false)
        awaitText("Couldn't load challenge settings")
        compose.onNodeWithText("Log in to AO3 before using this feature.").assertExists()
        compose.onNodeWithText("Try Again").performClick()
        assertTrue(client.gets.isEmpty())
    }

    @Test fun formFailureHasRetryThatRepeatsOnlyTheRequiredRead() {
        show(formFails = true)
        awaitText("Couldn't load challenge settings")
        compose.onNodeWithText("AO3 refused the request (HTTP 403). Wait a while before trying again.").assertExists()
        compose.onNodeWithText("Try Again").performClick()
        compose.waitUntil { client.gets.size == 2 }
        assertEquals(listOf(giftUrl, giftUrl), client.gets)
    }

    private fun checkNonOwner(theme: KudosThemeMode) {
        show(owner = false, theme = theme, scale = 2f)
        awaitText("Gift Exchange")
        compose.onNodeWithText("Edit settings").assertDoesNotExist()
        reach("DATES")
        reach("SIGN-UP REQUIREMENTS")
        compose.onNodeWithText("Relationships per request").assertExists()
        reach("Require a fandom match")
        compose.onNodeWithContentDescription("Require a fandom match").assertIsNotEnabled()
        reach("Defaults and pinch hits")
        compose.onNodeWithText("Defaults and pinch hits").assertExists()
        assertEquals(4, client.gets.size)
        assertEquals(0, client.posts)
    }
    @Test fun nonOwnerLightAtAccessibilitySize() = checkNonOwner(KudosThemeMode.Light)
    @Test fun nonOwnerDarkAtAccessibilitySize() = checkNonOwner(KudosThemeMode.Dark)
    @Test fun nonOwnerSepiaAtAccessibilitySize() = checkNonOwner(KudosThemeMode.Sepia)
    @Test fun nonOwnerOledAtAccessibilitySize() = checkNonOwner(KudosThemeMode.Oled)
}
