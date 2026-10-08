package io.github.cidy02.kudos.account

import android.app.Application
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
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
class AO3PromptMemeScreenTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var client: PromptMemeReadClient
    private val browser = mutableListOf<String>()
    private val native = mutableListOf<String>()

    private fun show(signedIn: Boolean = true, theme: KudosThemeMode = KudosThemeMode.Light,
        scale: Float = 1f, fromSettings: Boolean = false, fromManage: Boolean = false, configure: (PromptMemeReadClient) -> Unit = {}) {
        val (_, reads, repository) = runBlocking { promptMemeSetup(signedIn) }
        client = reads
        client.replies[ChallengeSettingsDestinations.profile("summer_meme")] = challengeResponse(
            ChallengeSettingsDestinations.profile("summer_meme"), "<dl></dl>")
        configure(client)
        compose.setContent {
            var opened by remember { mutableStateOf(!fromSettings && !fromManage) }
            KudosTheme(themeMode = theme) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale)) {
                    if (opened) AO3PromptMemeScreen("summer_meme", "Summer Prompt Meme", true, repository, onOpenWeb = { browser += it })
                    else if (fromManage) CollectionManageRow("Prompts", promptFirstUrl,
                        onOpenModeration = { error("Wrong destination") }, onOpenSettings = { error("Wrong destination") },
                        onOpenMaintainers = { error("Wrong destination") }, onOpenWebFallback = { error("Manage opened browser") },
                        onOpenPrompts = { native += Routes.ao3PromptMeme("summer_meme", "Summer Prompt Meme"); opened = true })
                    else AO3ChallengeSettingsScreen("summer_meme", "Summer Prompt Meme", true, repository,
                        onOpenWeb = { browser += it }, onOpenExternal = { error("Meme opened matching") },
                        onOpenTagSet = { _, _ -> error("Wrong destination") },
                        onOpenPrompts = { slug, title -> native += Routes.ao3PromptMeme(slug, title); opened = true })
                }
            }
        }
    }

    private fun awaitText(text: String, substring: Boolean = false) {
        compose.waitUntil(15_000) { compose.onAllNodesWithText(text, substring = substring).fetchSemanticsNodes().isNotEmpty() }
    }
    private fun reach(text: String, substring: Boolean = false) {
        compose.onNode(hasScrollAction()).performScrollToNode(hasText(text, substring = substring))
    }
    private fun select(label: String) {
        reach(label)
        compose.onNodeWithText(label).performClick()
    }
    private fun noWrites() {
        listOf("Claim", "Release", "New prompt", "Submit sign-up").forEach { compose.onNodeWithText(it).assertDoesNotExist() }
        assertEquals(0, client.posts)
    }

    @Test fun nativeSettingsRowOpensPromptsWithCollectionArguments() {
        show(fromSettings = true)
        awaitText("Edit settings")
        reach("Claim and fill")
        compose.onNodeWithText("Claim and fill").performClick()
        awaitText("Lanterns after closing")
        assertEquals(listOf(Routes.ao3PromptMeme("summer_meme", "Summer Prompt Meme")), native)
        assertTrue(browser.isEmpty())
        // Three for settings (gift probe, meme, profile), then this screen's three.
        assertEquals(listOf(promptGiftUrl, promptSettingsUrl, ChallengeSettingsDestinations.profile("summer_meme"),
            promptGiftUrl, promptSettingsUrl, promptFirstUrl), client.gets)
        noWrites()
    }

    @Test fun collectionManagePromptsUsesSameNativeScreenWithoutAnExtraRead() {
        show(fromManage = true)
        compose.onNodeWithText("Prompts").performClick()
        awaitText("Lanterns after closing")
        assertEquals(listOf(Routes.ao3PromptMeme("summer_meme", "Summer Prompt Meme")), native)
        assertEquals(listOf(promptGiftUrl, promptSettingsUrl, promptFirstUrl), client.gets)
        assertTrue(browser.isEmpty())
        noWrites()
    }

    @Test fun allFiltersAndBrowserFillKeepExactStatesAndSendNothing() {
        show()
        awaitText("Lanterns after closing")
        reach("Claimed by you")
        compose.onNodeWithText("Claimed by you").assertExists()
        reach("Posted anonymously")
        compose.onNodeWithText("Posted anonymously").assertExists()
        reach("Fill it")
        compose.onNodeWithText("Fill it").performClick()
        assertEquals(listOf(AO3PromptMemeUrls.meme("summer_meme")), browser)
        select("Unclaimed")
        awaitText("Lanterns after closing")
        compose.onNodeWithText("A borrowed constellation").assertDoesNotExist()
        compose.onNodeWithText("Posted anonymously").assertDoesNotExist()
        select("Yours")
        awaitText("A borrowed constellation")
        compose.onNodeWithText("Claimed by you").assertExists()
        compose.onNodeWithText("Lanterns after closing").assertDoesNotExist()
        assertEquals(3, client.gets.size)
        noWrites()
    }

    @Test fun pageReplacesRowsAndLongSummaryStaysWholeWithOneRead() {
        show()
        awaitText("Lanterns after closing")
        reach("Page 1 of 2")
        compose.onNodeWithContentDescription("Next Page").performClick()
        awaitText("Page 2 of 2")
        reach("The orchard beyond the timetable")
        compose.onNodeWithText("Lanterns after closing").assertDoesNotExist()
        compose.onNodeWithText("the smell of warm bread.", substring = true).assertExists()
        select("Yours")
        awaitText("The orchard beyond the timetable")
        compose.onNodeWithText("Posted anonymously").assertDoesNotExist()
        assertEquals(listOf(promptGiftUrl, promptSettingsUrl, promptFirstUrl, promptSecondUrl), client.gets)
        noWrites()
    }

    @Test fun failedFurtherPageShowsWarningAboveOldPageAndReaderCanRetry() {
        show { it.replies[promptSecondUrl] = AO3Result.Failure(AO3Error.Forbidden) }
        awaitText("Lanterns after closing")
        reach("Page 1 of 2")
        compose.onNodeWithContentDescription("Next Page").performClick()
        compose.waitUntil(15_000) { client.gets.size == 4 }
        reach("Couldn't load that page:", substring = true)
        awaitText("Couldn't load that page:", substring = true)
        compose.onNodeWithText("Lanterns after closing").assertExists()
        reach("Page 1 of 2")
        compose.runOnIdle { client.replies.remove(promptSecondUrl) }
        compose.onNodeWithContentDescription("Next Page").performClick()
        awaitText("Page 2 of 2")
        assertEquals(listOf(promptSecondUrl, promptSecondUrl), client.gets.drop(3))
        noWrites()
    }

    @Test fun loadingAndInitialFailureWordsAndRetryWithoutAnotherScheduleRead() {
        show { it.hold = true; it.replies[promptFirstUrl] = AO3Result.Failure(AO3Error.Forbidden) }
        awaitText("Loading prompts…")
        compose.onNodeWithText("Lanterns after closing").assertDoesNotExist()
        compose.runOnIdle { client.hold = false; client.release.complete(Unit) }
        awaitText("Couldn't load prompts")
        compose.onNodeWithText("AO3 refused the request (HTTP 403). Wait a while before trying again.").assertExists()
        compose.runOnIdle { client.replies.remove(promptFirstUrl) }
        compose.onNodeWithText("Try Again").performClick()
        awaitText("Lanterns after closing")
        assertEquals(listOf(promptFirstUrl), client.gets.drop(3))
        noWrites()
    }

    @Test fun signedOutHasPublicEmptyScreenNoLoginSentenceAndOneRead() {
        show(signedIn = false) { it.replies[promptFirstUrl] = challengeResponse(promptFirstUrl, "<h2 class='heading'>Prompts</h2>") }
        awaitText("No prompts yet")
        compose.onNodeWithText("Prompts will appear here once someone posts one.").assertExists()
        compose.onNodeWithText("0 prompts · 0 unclaimed").assertExists()
        compose.onNodeWithText("Log in to AO3 before using this feature.").assertDoesNotExist()
        select("Yours")
        awaitText("No yours prompts")
        compose.onNodeWithText("No prompts on this page match the \"Yours\" filter.").assertExists()
        select("Unclaimed")
        awaitText("No unclaimed prompts")
        assertEquals(listOf(promptFirstUrl), client.gets)
        assertTrue(client.headers.single().isEmpty())
        noWrites()
    }

    private fun accessibleTheme(theme: KudosThemeMode) {
        show(theme = theme, scale = 2f)
        awaitText("Lanterns after closing")
        // The summary chip deliberately cuts one line at normal size, but wraps in this case.
        val tags = AO3PromptMemeParser().parse(challengeFixture("ao3_demo_meme_requests_1")).prompts.first().tags.joinToString(", ")
        reach(tags)
        val tagLayouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(tags).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(tagLayouts) }
        assertTrue(tagLayouts.isNotEmpty())
        assertTrue(tagLayouts.all { !it.didOverflowHeight && !it.isLineEllipsized(it.lineCount - 1) })
        select("Unclaimed")
        val filterLayouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText("Unclaimed").performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(filterLayouts) }
        assertTrue(filterLayouts.isNotEmpty())
        assertTrue(filterLayouts.all { !it.didOverflowHeight && !it.isLineEllipsized(it.lineCount - 1) })
        assertEquals(3, client.gets.size)
        noWrites()
    }
    @Test fun lightAtAccessibilityScale() = accessibleTheme(KudosThemeMode.Light)
    @Test fun darkAtAccessibilityScale() = accessibleTheme(KudosThemeMode.Dark)
    @Test fun sepiaAtAccessibilityScale() = accessibleTheme(KudosThemeMode.Sepia)
    @Test fun oledAtAccessibilityScale() = accessibleTheme(KudosThemeMode.Oled)
}
