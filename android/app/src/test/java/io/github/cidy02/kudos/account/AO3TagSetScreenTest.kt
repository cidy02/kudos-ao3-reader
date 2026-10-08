package io.github.cidy02.kudos.account

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
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
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2000dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AO3TagSetScreenTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var client: TagSetReadClient
    private lateinit var auth: io.github.cidy02.kudos.auth.AO3AuthRepository
    private val web = mutableListOf<String>()
    private val chrome = PushedShellChrome()
    private val moderator = mutableStateOf(false)
    private val longTag = "A very long original fictional tag about lantern couriers carrying postcards across the snowy archipelago"

    private fun show(id: Int = 42, signedIn: Boolean = true, isModerator: Boolean = false,
        title: String = "", theme: KudosThemeMode = KudosThemeMode.Light, scale: Float = 1f,
        hold: Boolean = false, fail: Boolean = false, queueFail: Boolean = false, longField: Boolean = false,
        holdPost: Boolean = false, postBody: String? = null) {
        val (account, reads, repository) = runBlocking { tagSetSetup(id, if (signedIn) "AO3_Reader" else null) }
        auth = account
        client = reads
        client.hold = hold
        client.holdPost = holdPost
        if (postBody != null) client.postReply = AO3Result.Success(AO3HttpResponse(
            AO3TagSetUrls.page(id), 200, emptyMap(), postBody))
        moderator.value = isModerator
        if (fail) client.replies[AO3TagSetUrls.page(id)] = AO3Result.Failure(AO3Error.Forbidden)
        if (queueFail) client.replies[AO3TagSetUrls.nominations(id)] = AO3Result.Failure(AO3Error.Server(503))
        if (longField) client.replies[AO3TagSetUrls.nominations(id)] = AO3Result.Success(AO3HttpResponse(
            AO3TagSetUrls.nominations(id), 200, emptyMap(), tagSetFixture("ao3_demo_tag_set_42_nominations").replace("Snow Map", longTag)))
        val writes = tagSetWrites(client, auth)
        compose.setContent {
            KudosTheme(themeMode = theme) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale), LocalPushedShellChrome provides chrome) {
                    AO3TagSetScreen(id, title, moderator.value, repository, writes, onOpenWeb = { web += it })
                }
            }
        }
    }

    private fun awaitText(text: String) = compose.waitUntil(15_000) {
        compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
    }
    private fun reach(text: String) { compose.onNode(hasScrollAction()).performScrollToNode(hasText(text)) }

    @Test fun mainScreenShowsAllSectionsCountsFlagsQueueAndOnlyIosBrowserDestinations() {
        show(isModerator = true, title = "Passed title")
        awaitText("Passed title · 7 tags")
        compose.onNodeWithText("TAG SET · MODERATOR").assertExists()
        compose.onNodeWithContentDescription("Visible to everyone").assertIsNotEnabled()
        compose.onNodeWithContentDescription("Nominations open").assertIsNotEnabled()
        reach("NO FANDOM LISTED")
        compose.onNodeWithText("Paper Harbor").assertExists()
        compose.onNodeWithText("Mira Vale").assertExists()
        compose.onNodeWithText("Mira Vale/Oren Reed").assertExists()
        compose.onNodeWithText("Snow Map").assertExists()
        compose.onNodeWithText("Letters [Winter]").assertExists()
        compose.onAllNodesWithText("Reject").assertCountEquals(3)
        reach("Delete tag set")
        compose.onNodeWithText("Associate nominations").performClick()
        compose.onNodeWithText("Delete tag set").performClick()
        assertEquals(listOf(AO3TagSetUrls.associations(42), AO3TagSetUrls.edit(42)), web)
        assertEquals(tagSetReadUrls(42), client.gets)
        assertEquals(0, client.posts)
        compose.runOnIdle { moderator.value = false }
        reach("Tag set")
        compose.onNodeWithText("TAG SET · OWNER").assertExists()
        assertEquals(3, client.gets.size) // Role changes header only; never read again.
    }

    @Test fun allFourTagRowsOpenTheSameEditorAndShellBackMakesNoRequests() {
        show()
        awaitText("Winter Exchange Tags · 7 tags")
        for (label in listOf("Fandoms", "Characters", "Relationships", "Additional tags")) {
            reach(label)
            compose.onNodeWithText(label).performClick()
            awaitText("Add tags")
            for (field in AO3TagSetField.entries) {
                reach(field.editorLabel)
                compose.onNodeWithContentDescription(field.editorLabel).assert(
                    SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString("")))
            }
            reach("Save tags")
            compose.onNodeWithText("Save tags").assertHasClickAction()
            assertEquals(3, client.gets.size)
            assertEquals(0, client.posts)
            compose.runOnIdle { chrome.onBack!!.invoke() }
            awaitText("Winter Exchange Tags · 7 tags")
        }
    }

    @Test fun signedOutHasOneAnonymousReadAndAllFiveSectionsUsingOnlyPublicValues() {
        show(signedIn = false)
        awaitText("Winter Exchange Tags · 7 tags")
        reach("NO FANDOM LISTED")
        compose.onNodeWithText("Paper Harbor").assertExists()
        compose.onNodeWithText("Mira Vale").assertDoesNotExist()
        reach("AT AO3")
        compose.onNodeWithText("Delete tag set").assertExists()
        assertEquals(listOf(AO3TagSetUrls.page(42)), client.publicReads)
        assertTrue(client.authenticatedReads.isEmpty())
        assertEquals(0, client.posts)
    }

    @Test fun closedInvisibleSetStillShowsNominationLimitsReviewEmptyStateAndAo3Rows() {
        show(id = 43)
        awaitText("Snowbound Characters · 2 tags")
        reach("No nominations yet")
        compose.onNodeWithText("Nothing has been nominated to this tag set.").assertExists()
        reach("Delete tag set")
        compose.onNodeWithText("Delete tag set").assertExists()
        assertEquals(tagSetReadUrls(43), client.gets)
    }

    @Test fun refusedEditViewerKeepsPublicValuesAndDedicatedNominationsWithNoRefusalPanel() {
        show(id = 44)
        awaitText("Summer Prompt Tags · 3 tags")
        reach("NO FANDOM LISTED")
        compose.onNodeWithText("Tavi Shore").assertExists()
        compose.onNodeWithText("Letters from the Tidelands").assertExists()
        compose.onNodeWithText("Couldn't load tag set").assertDoesNotExist()
        assertEquals(tagSetReadUrls(44), client.gets)
        assertEquals(0, client.posts)
    }

    @Test fun optionalQueueFailureKeepsTheEditModelAndItsQueueOnScreen() {
        show(queueFail = true)
        awaitText("Winter Exchange Tags · 7 tags")
        reach("NO FANDOM LISTED")
        compose.onNodeWithText("Paper Harbor").assertExists()
        compose.onNodeWithText("Couldn't load tag set").assertDoesNotExist()
        assertEquals(tagSetReadUrls(42), client.gets)
    }

    @Test fun loadingAndRequiredFailureReplaceContentAndTryAgainRepeatsOnlyTheRequiredRead() {
        show(hold = true, fail = true)
        awaitText("Loading tag set…")
        compose.onNodeWithText("OWNERSHIP").assertDoesNotExist()
        compose.runOnIdle { client.hold = false; client.release.complete(Unit) }
        awaitText("Couldn't load tag set")
        compose.onNodeWithText("OWNERSHIP").assertDoesNotExist()
        compose.onNodeWithText("Try Again").performClick()
        compose.waitUntil(15_000) { client.gets.size == 2 }
        assertEquals(List(2) { AO3TagSetUrls.page(42) }, client.gets)
        assertEquals(0, client.posts)
    }

    @Test fun logoutLoadsOnlyThePublicPageInTheNewSession() {
        show()
        awaitText("Winter Exchange Tags · 7 tags")
        compose.runOnIdle { runBlocking { auth.logout() } }
        compose.waitUntil(15_000) { client.publicReads.isNotEmpty() }
        awaitText("Winter Exchange Tags · 7 tags")
        assertEquals(tagSetReadUrls(42), client.authenticatedReads)
        assertEquals(listOf(AO3TagSetUrls.page(42)), client.publicReads)
    }

    @Test fun saveWaitsForConfirmationDisablesDuplicateTapAndKeepsDraftAfterSuccessAndBack() {
        show(holdPost = true)
        awaitText("Winter Exchange Tags · 7 tags")
        reach("Fandoms"); compose.onNodeWithText("Fandoms").performClick()
        awaitText("Add tags")
        compose.onNodeWithContentDescription("Fandom tags to add").performTextReplacement("Lantern Harbor")
        reach("Save tags"); compose.onNodeWithText("Save tags").performClick()
        compose.waitUntil(15_000) { client.posts == 1 }
        compose.onNodeWithText("Save tags").assertIsNotEnabled()
        compose.onNodeWithText("Tags saved.").assertDoesNotExist()
        assertEquals(4, client.gets.size)
        compose.runOnIdle { client.postRelease.complete(Unit) }
        awaitText("Tags saved.")
        compose.onNodeWithText("Save tags").assertIsEnabled()
        reach("Fandom tags to add")
        compose.onNodeWithContentDescription("Fandom tags to add").assertTextEquals("Lantern Harbor")
        compose.runOnIdle { chrome.onBack!!.invoke() }
        awaitText("Winter Exchange Tags · 7 tags")
        reach("Characters"); compose.onNodeWithText("Characters").performClick()
        awaitText("Add tags")
        compose.onNodeWithContentDescription("Fandom tags to add").assertTextEquals("Lantern Harbor")
        assertEquals(4, client.gets.size)
        assertEquals(1, client.posts)
    }

    @Test fun saveRefusalRetainsInputAndNamesItsListExactly() {
        val reason = "Character tags to add: Uncharted Lantern could not be added."
        show(postBody = "<div class='flash error'>$reason</div>")
        awaitText("Winter Exchange Tags · 7 tags")
        reach("Characters"); compose.onNodeWithText("Characters").performClick()
        awaitText("Add tags")
        reach("Character tags to add")
        compose.onNodeWithContentDescription("Character tags to add").performTextReplacement("Uncharted Lantern")
        reach("Save tags"); compose.onNodeWithText("Save tags").performClick()
        awaitText(reason)
        compose.onNodeWithText("Tags saved.").assertDoesNotExist()
        reach("Character tags to add")
        compose.onNodeWithContentDescription("Character tags to add").assertTextEquals("Uncharted Lantern")
        assertEquals(4, client.gets.size)
        assertEquals(1, client.posts)
    }

    @Test fun refusedEditStillOpensEditorAndSaveShowsRefusedReadWithoutPost() {
        show(id = 44)
        awaitText("Summer Prompt Tags · 3 tags")
        reach("Fandoms"); compose.onNodeWithText("Fandoms").performClick()
        awaitText("Add tags")
        compose.onNodeWithContentDescription("Fandom tags to add").performTextReplacement("New Tidelands")
        reach("Save tags"); compose.onNodeWithText("Save tags").performClick()
        awaitText("AO3 refused the request (HTTP 403). Wait a while before trying again.")
        reach("Fandom tags to add")
        compose.onNodeWithContentDescription("Fandom tags to add").assertTextEquals("New Tidelands")
        assertEquals(4, client.gets.size)
        assertEquals(0, client.posts)
    }

    @Test fun heldRejectDisablesEveryOtherRejectAndOnlyConfirmationChangesBadgeAndCounts() {
        show(holdPost = true)
        awaitText("Winter Exchange Tags · 7 tags")
        reach("Letters [Winter]")
        compose.onNodeWithContentDescription("Reject Letters [Winter]").performClick()
        compose.waitUntil(15_000) { client.posts == 1 }
        compose.onNodeWithContentDescription("Reject Letters [Winter]").assertIsNotEnabled()
        reach("Paper Harbor")
        compose.onNodeWithContentDescription("Reject Paper Harbor").assertIsNotEnabled()
        reach("Mira Vale/Oren Reed")
        compose.onNodeWithContentDescription("Reject Mira Vale/Oren Reed").assertIsNotEnabled()
        assertEquals(4, client.gets.size)
        compose.runOnIdle { client.postRelease.complete(Unit) }
        compose.waitUntil(15_000) {
            compose.onAllNodesWithContentDescription("Reject Letters [Winter]").fetchSemanticsNodes().isEmpty()
        }
        reach("Letters [Winter]")
        compose.onNodeWithText("Letters [Winter]").assertExists()
        reach("Paper Harbor")
        compose.onNodeWithContentDescription("Reject Paper Harbor").assertIsEnabled()
        reach("Awaiting review")
        // The three counts share one panel, so equal counts are siblings of every label: 2 awaiting, 1 approved, 2 rejected.
        compose.onAllNodes(hasText("2") and hasAnySibling(hasText("Awaiting review"))).assertCountEquals(2)
        compose.onAllNodes(hasText("1") and hasAnySibling(hasText("Awaiting review"))).assertCountEquals(1)
        assertEquals(4, client.gets.size)
        assertEquals(1, client.posts)
    }

    @Test fun refusedRejectKeepsRowAndCountsAndExactPrefixedAo3Reason() {
        show(postBody = "<div class='flash error'>Paper Harbor is locked for this review.</div>")
        awaitText("Winter Exchange Tags · 7 tags")
        reach("Paper Harbor")
        compose.onNodeWithContentDescription("Reject Paper Harbor").performClick()
        awaitText("Couldn't reject “Paper Harbor”: Paper Harbor is locked for this review.")
        reach("Paper Harbor")
        compose.onNodeWithContentDescription("Reject Paper Harbor").assertIsEnabled()
        reach("Awaiting review")
        // Unchanged: 3 awaiting, 1 approved, 1 rejected.
        compose.onAllNodes(hasText("3") and hasAnySibling(hasText("Awaiting review"))).assertCountEquals(1)
        compose.onAllNodes(hasText("1") and hasAnySibling(hasText("Awaiting review"))).assertCountEquals(2)
        assertEquals(4, client.gets.size)
        assertEquals(1, client.posts)
    }

    @Test fun signedOutControlsRemainVisibleAndBothTapsReportIosSignInWordsWithoutRequest() {
        show(signedIn = false)
        awaitText("Winter Exchange Tags · 7 tags")
        reach("Paper Harbor")
        compose.onNodeWithContentDescription("Reject Paper Harbor").performClick()
        awaitText("Couldn't reject “Paper Harbor”: Log in to AO3 first.")
        reach("Fandoms"); compose.onNodeWithText("Fandoms").performClick()
        awaitText("Add tags")
        reach("Save tags"); compose.onNodeWithText("Save tags").performClick()
        awaitText("Log in to AO3 first.")
        assertEquals(1, client.gets.size)
        assertEquals(0, client.posts)
    }

    private fun largeTheme(mode: KudosThemeMode) {
        show(theme = mode, scale = 2f, longField = true)
        awaitText("Winter Exchange Tags · 7 tags")
        reach(longTag)
        val layouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(longTag).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        assertTrue(layouts.isNotEmpty())
        assertTrue(layouts.all { !it.hasVisualOverflow && it.lineCount > 1 })
        reach("Fandoms"); compose.onNodeWithText("Fandoms").performClick()
        awaitText("Add tags")
        for (placeholder in listOf("Comma-separated fandom names…", "Comma-separated character names…",
            "Comma-separated relationships…", "Comma-separated additional tags…")) {
            reach(placeholder)
            val fieldLayouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText(placeholder).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(fieldLayouts) }
            assertTrue(fieldLayouts.isNotEmpty())
            assertTrue(fieldLayouts.all { !it.hasVisualOverflow })
        }
        reach("Save tags")
        val buttonLayouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText("Save tags").performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(buttonLayouts) }
        assertTrue(buttonLayouts.isNotEmpty())
        // Not hasVisualOverflow: a short label narrower than its row reports a width overflow it does not have.
        assertTrue(buttonLayouts.all { !it.didOverflowHeight && !it.isLineEllipsized(it.lineCount - 1) })
        assertEquals(3, client.gets.size)
        assertEquals(0, client.posts)
    }
    @Test fun lightAtAccessibilitySizeWrapsAllTagText() = largeTheme(KudosThemeMode.Light)
    @Test fun darkAtAccessibilitySizeWrapsAllTagText() = largeTheme(KudosThemeMode.Dark)
    @Test fun sepiaAtAccessibilitySizeWrapsAllTagText() = largeTheme(KudosThemeMode.Sepia)
    @Test fun oledAtAccessibilitySizeWrapsAllTagText() = largeTheme(KudosThemeMode.Oled)
}
