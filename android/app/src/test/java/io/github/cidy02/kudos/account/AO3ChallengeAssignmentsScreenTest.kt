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
class AO3ChallengeAssignmentsScreenTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var client: PromptMemeReadClient
    private val chrome = PushedShellChrome()
    private val browser = mutableListOf<String>()
    private fun show(owner: Boolean = true, signedIn: Boolean = true, failure: Boolean = false, hold: Boolean = false) {
        val (auth, reads, repo) = runBlocking { assignmentsSetup(signedIn) }
        client = reads; client.hold = hold
        if (failure) client.replies[assignmentUrl(SignUpAssignmentList.Complete)] = AO3Result.Failure(AO3Error.Server(503))
        val writes = promptMemeWrites(client, auth)
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            CompositionLocalProvider(LocalPushedShellChrome provides chrome) {
                AO3ChallengeAssignmentsScreen("winter_exchange", "Winter Exchange 2026", owner, true, true, repo,
                    writes, { browser += it })
            }
        } }
    }
    private fun awaitText(text: String, substring: Boolean = false) = compose.waitUntil(15_000) {
        compose.onAllNodesWithText(text, substring = substring).fetchSemanticsNodes().isNotEmpty()
    }
    private fun reach(text: String, substring: Boolean = false) = compose.onNodeWithTag("Challenge assignments")
        .performScrollToNode(hasText(text, substring = substring))

    @Test fun segmentsLazyRowsOpenOnAo3PickersConfirmationsAndUnconfirmedAlone() {
        show(); awaitText("Two sign-ups lost their giver")
        assertEquals(assignmentReads + signUpsSettings, client.gets)
        reach("One sign-up lost its giver"); compose.onAllNodesWithText("Open on AO3").onFirst().performClick()
        assertEquals(listOf(assignmentUrl(SignUpAssignmentList.PinchHits)), browser)
        reach("Pinch hits"); compose.onNodeWithText("Pinch hits").performClick()
        reach("Pinch hit #1"); compose.onNodeWithText("Requested by Harbor (AO3_Reader)").assertExists()
        reach("Pinch hit #4"); compose.onNodeWithText("CLAIMED").assertExists()
        reach("Load more pinch hits"); compose.onNodeWithText("Load more pinch hits").performClick()
        compose.waitForIdle(); compose.waitUntil(15_000) { client.gets.size == 6 }
        reach("Pinch hit #5"); awaitText("Claimed by AO3_Reader for Snow Lantern", true)
        compose.onNodeWithText("Claim a pinch hit").performClick()
        compose.onNodeWithText("FormerGiver → Harbor (AO3_Reader)").performClick()
        awaitText("Claim this pinch hit?")
        compose.onNodeWithText("Cancel").performClick(); assertEquals(0, client.posts)
        compose.onNodeWithText("Report a default").performClick()
        compose.onNodeWithText("riverpost → emberpost").performClick()
        awaitText("Report this default?")
        compose.onNodeWithText("This marks riverpost's assignment for emberpost as defaulted on AO3 and adds it to the pinch hits waiting for cover.").assertExists()
        client.postReply = challengeResponse(assignmentAction, "<p>Unconfirmed</p>")
        compose.onNodeWithText("Report default").performClick()
        compose.waitForIdle(); compose.waitUntil(15_000) { client.posts == 1 }
        reach(AO3CollectionFields.UNCONFIRMED); awaitText(AO3CollectionFields.UNCONFIRMED)
        assertEquals(7, client.gets.size) // opening five, explicit further page, one token; no verdict reload
        assertFalse(compose.onAllNodesWithText("Couldn't record the default:", substring = true).fetchSemanticsNodes().isNotEmpty())
    }

    @Test fun confirmedWriteDismissesConfirmationAndReloadsFivePagesWithoutAnotherPost() {
        show(); awaitText("Two sign-ups lost their giver")
        client.postReply = challengeResponse(assignmentAction, "<div class='flash notice'>Assignments updated.</div>")
        compose.onNodeWithText("Report a default").performClick()
        compose.onNodeWithText("riverpost → emberpost").performClick(); awaitText("Report this default?")
        compose.onNodeWithText("Report default").performClick()
        compose.waitForIdle(); compose.waitUntil(15_000) { client.gets.size == 11 }
        compose.waitForIdle()
        compose.onNodeWithText("Report this default?").assertDoesNotExist()
        compose.onNodeWithText("Report a default").assertIsEnabled()
        assertEquals(1, client.posts)
        assertEquals(assignmentReads + signUpsSettings + assignmentUrl(SignUpAssignmentList.Open) + assignmentReads + signUpsSettings, client.gets)
    }

    @Test fun loadingSignedOutAndOneListFailureLeaveOtherSegmentsAvailable() {
        show(failure = true); awaitText("Two sign-ups lost their giver")
        compose.onNodeWithText("Matched").performClick(); awaitText("Couldn't load matched assignments")
        compose.onNodeWithText("Pinch hits").performClick(); reach("Pinch hit #4")
        compose.onNodeWithText("CLAIMED").assertExists()
        assertEquals(listOf(assignmentReads[0], assignmentReads[2], assignmentReads[3], signUpsSettings), client.gets)
        assertEquals(0, client.posts)
    }
    @Test fun loadingRowDoesNotDuplicateItsOpeningRequest() = runBlocking<Unit> {
        show(hold = true); awaitText("Loading assignments…")
        assertEquals(listOf(assignmentReads.first()), client.gets)
        assertNull(chrome.trailingContent)
        compose.onNodeWithText("Claim a pinch hit").assertDoesNotExist()
        client.release.complete(Unit)
        awaitText("Two sign-ups lost their giver")
        assertEquals(assignmentReads + signUpsSettings, client.gets)
    }
    @Test fun signedOutNeverReadsAndHasExactSwiftSentence() {
        show(signedIn = false); awaitText("Sign in to AO3 to view assignments.")
        assertTrue(client.gets.isEmpty()); assertEquals(0, client.posts)
        compose.onNodeWithText("Claim a pinch hit").assertDoesNotExist()
    }
    @Test fun moderatorSeesAllThreeListsButNoOwnerControlsAndNoSettingsRead() {
        show(owner = false); awaitText("Two sign-ups lost their giver")
        assertEquals(assignmentReads, client.gets)
        compose.onNodeWithText("Report a default").assertDoesNotExist()
        compose.onNodeWithText("Claim a pinch hit").assertDoesNotExist()
        compose.onNodeWithText("Pinch hits").performClick(); reach("Pinch hit #1")
        compose.onNodeWithText("Claim").assertDoesNotExist()
    }
    @Test fun heldWriteDisablesOtherWriteControlsAndRefreshDoesNotRead() = runBlocking<Unit> {
        show(); awaitText("Two sign-ups lost their giver")
        compose.onNodeWithText("Claim a pinch hit").performClick()
        compose.onNodeWithText("FormerGiver → Harbor (AO3_Reader)").performClick(); awaitText("Claim this pinch hit?")
        client.holdPost = true; client.postReply = challengeResponse(assignmentAction, "<div class='flash error'>This pinch hit is no longer available.</div>")
        compose.onNodeWithText("Claim").performClick()
        compose.waitForIdle(); compose.waitUntil(15_000) { client.posts == 1 }
        compose.onNodeWithText("Report a default").assertIsNotEnabled()
        compose.onNodeWithText("Claim a pinch hit").assertIsNotEnabled()
        compose.onNodeWithText("Pinch hits").performClick(); reach("Pinch hit #1")
        compose.onAllNodesWithText("Claim").onFirst().assertIsNotEnabled()
        val before = client.gets.size
        compose.runOnIdle { chrome.trailingContent?.let { assertNotNull(it) } }
        client.postRelease.complete(Unit)
        reach("This pinch hit is no longer available."); awaitText("This pinch hit is no longer available.")
        assertEquals(before, client.gets.size)
        compose.onNodeWithText("Report a default").assertIsEnabled()
    }
    @Test fun fourThemesAccessibilityLongRowsAndBottomActionsNeverLoseTheirLastLine() {
        val (auth, reads, repo) = runBlocking { assignmentsSetup() }; client = reads
        val writes = promptMemeWrites(client, auth)
        var theme by mutableStateOf(KudosThemeMode.Light)
        compose.setContent { KudosTheme(theme) {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 1.8f)) {
                AO3ChallengeAssignmentsScreen("winter_exchange", "Winter Exchange 2026", true, true, true, repo, writes, {})
            }
        } }
        awaitText("Two sign-ups lost their giver")
        compose.onNodeWithText("Pinch hits").performClick()
        for (mode in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { theme = mode }
            val long = "Requested by The Keeper of Every Letter Along the Snowbound Harbor"
            reach(long)
            for (label in listOf(long, "Report a default", "Claim a pinch hit")) {
                val layouts = mutableListOf<TextLayoutResult>()
                compose.onNodeWithText(label).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
                assertTrue(layouts.isNotEmpty()); assertTrue(layouts.all { !it.didOverflowHeight && !it.isLineEllipsized(it.lineCount - 1) })
            }
        }
        assertEquals(assignmentReads + signUpsSettings, client.gets)
    }
    @Test fun manageEntranceAndEveryRouteChromeRegistryAreNativeAndEncoded() {
        var route: String? = null
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            CollectionManageRow("Assignments", assignmentUrl(SignUpAssignmentList.Defaults), {}, {}, {},
                { error("Assignments opened browser") }, onOpenAssignments = {
                    route = Routes.ao3ChallengeAssignments("a/b", "Winter & 星", false, true, true)
                })
        } }
        compose.onNodeWithText("Assignments").performClick()
        assertEquals("ao3-challenge-assignments/a%2Fb?title=Winter%20%26%20%E6%98%9F&owner=false&maintainer=true&closed=true", route)
        assertEquals("Assignments", Routes.titleFor(Routes.AO3ChallengeAssignments))
        assertTrue(Routes.hasSubjectHeader(route)); assertTrue(Routes.hidesTabBar(route))
    }
}
