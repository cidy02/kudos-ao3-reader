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
class AO3ChallengeSignUpsScreenTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var client: PromptMemeReadClient
    private val routes = mutableListOf<String>()
    private val chrome = PushedShellChrome()
    private fun show(owner: Boolean = true, maintainer: Boolean = true, signedIn: Boolean = true,
        failAssignments: Boolean = false, hold: Boolean = false, theme: KudosThemeMode = KudosThemeMode.Light, scale: Float = 1f) {
        val (_, reads, repo) = runBlocking { signUpsSetup(signedIn) }
        client = reads; client.hold = hold
        if (failAssignments) client.replies[signUpsAssignmentReads.first()] = AO3Result.Failure(AO3Error.Forbidden)
        compose.setContent {
            KudosTheme(themeMode = theme) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalPushedShellChrome provides chrome, LocalDensity provides Density(density.density, scale)) {
                    AO3ChallengeSignUpsScreen("winter_exchange", "Winter Exchange 2026", owner, maintainer, repo,
                        onOpenSignUp = { routes += Routes.ao3ChallengeSignUp("winter_exchange", "Winter Exchange 2026", it) })
                }
            }
        }
    }
    private fun awaitText(text: String, substring: Boolean = false) = compose.waitUntil(15_000) {
        compose.onAllNodesWithText(text, substring = substring).fetchSemanticsNodes().isNotEmpty()
    }
    private fun reach(text: String) = compose.onNodeWithTag("Challenge sign-ups").performScrollToNode(hasText(text))

    @Test fun listFiltersPageTwoAndParticipantReadUseCollectedRowsAndDetailOwnsShellBackWithoutRead() {
        show()
        awaitText("AO3_Reader")
        assertEquals(signUpsOpeningReads, client.gets)
        reach("AO3_Reader"); compose.onNodeWithText("AO3_Reader").performClick()
        compose.onNodeWithTag("Participant sign-up").assertExists()
        assertNotNull(chrome.onBack)
        assertNull(chrome.trailingContent)
        compose.onNodeWithText("REQUEST 1").assertExists()
        compose.onNodeWithText("OFFER 1").assertExists()
        assertEquals(2, compose.onAllNodesWithText("Fandoms").fetchSemanticsNodes().size)
        assertEquals(2, compose.onAllNodesWithText("A Lamp in the Window").fetchSemanticsNodes().size)
        assertEquals(2, compose.onAllNodesWithText("Any").fetchSemanticsNodes().size)
        assertEquals(signUpsOpeningReads, client.gets)
        compose.runOnIdle { chrome.onBack!!.invoke() }
        compose.onNodeWithTag("Challenge sign-ups").assertExists()
        compose.onNodeWithText("Matched").performClick()
        compose.onNodeWithText("Harbor (AO3_Reader)").assertDoesNotExist()
        compose.onNodeWithText("Unmatched").performClick()
        compose.onNodeWithText("AO3_Reader").assertDoesNotExist()
        compose.onNodeWithText("All").performClick()
        reach("Load page 2 of 2"); compose.onNodeWithText("Load page 2 of 2").performClick()
        compose.waitForIdle()
        compose.waitUntil(15_000) { client.gets.size == 7 }
        reach("emberpost"); awaitText("emberpost")
        assertEquals(signUpsOpeningReads + signUpsLast, client.gets)
        compose.onNodeWithText("Load page 2 of 2").assertDoesNotExist()
        compose.onNodeWithText("Your sign-up").performClick()
        compose.onNodeWithText("Create sign-up").performClick()
        assertEquals(listOf(Routes.ao3ChallengeSignUp("winter_exchange", "Winter Exchange 2026", 4),
            Routes.ao3ChallengeSignUp("winter_exchange", "Winter Exchange 2026")), routes)
        assertEquals(0, client.posts)
    }

    @Test fun failedOptionalReadLeavesListAndUnknownFiltersHonest() {
        show(failAssignments = true)
        awaitText("AO3_Reader")
        assertEquals(4, client.gets.size) // schedule, first attempted assignments, first/last sign-ups
        compose.onNodeWithText("MATCHED").assertDoesNotExist()
        compose.onNodeWithText("UNMATCHED").assertDoesNotExist()
        compose.onNodeWithText("Matched").performClick()
        awaitText("Match state unavailable")
        compose.onNodeWithText("No sign-up can be shown as matched or unmatched without assignments.").assertExists()
        assertEquals(0, client.posts)
    }

    @Test fun signedOutDoesNotReadOrShowParticipantActions() {
        show(signedIn = false)
        awaitText("Log in to AO3 before using this feature.")
        assertTrue(client.gets.isEmpty()); assertEquals(0, client.posts)
        compose.onNodeWithText("Your sign-up").assertDoesNotExist()
        compose.onNodeWithText("Create sign-up").assertDoesNotExist()
    }

    @Test fun loadingAndModeratorAreLimitedReadsNotForbiddenOwnerProbes() {
        show(owner = false, hold = true)
        awaitText("Loading sign-ups…")
        assertEquals(listOf(signUpsFirst), client.gets)
        compose.runOnIdle { client.release.complete(Unit) }
        awaitText("AO3_Reader")
        assertEquals(listOf(signUpsFirst, signUpsLast), client.gets)
        assertEquals(0, client.posts)
    }

    @Test fun accessibilityLongPseudAndBottomActionsHaveHeightAndLastLinesInEveryTheme() {
        val (_, reads, repo) = runBlocking { signUpsSetup() }
        client = reads
        var mode by mutableStateOf(KudosThemeMode.Light)
        compose.setContent {
            KudosTheme(themeMode = mode) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, 1.8f)) {
                    AO3ChallengeSignUpsScreen("winter_exchange", "Winter Exchange 2026", true, true, repo, {})
                }
            }
        }
        awaitText("AO3_Reader")
        for (theme in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { mode = theme }
            val long = "The Keeper of Every Lamp Along the Snowbound Harbor"
            reach(long)
            for (label in listOf(long, "Your sign-up", "Create sign-up")) {
                val layouts = mutableListOf<TextLayoutResult>()
                compose.onNodeWithText(label).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
                assertTrue(layouts.isNotEmpty())
                assertTrue(layouts.all { !it.didOverflowHeight && !it.isLineEllipsized(it.lineCount - 1) })
            }
        }
        assertEquals(signUpsOpeningReads, client.gets); assertEquals(0, client.posts)
    }

    @Test fun realManageEntranceAndRoutesRequestNativeListWithEncodedArgumentsAndAllChromeRegistries() {
        var native: String? = null
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            CollectionManageRow("Sign-ups", signUpsFirst, onOpenModeration = { error("Wrong route") },
                onOpenSettings = { error("Wrong route") }, onOpenMaintainers = { error("Wrong route") },
                onOpenWebFallback = { error("Sign-ups opened browser") },
                onOpenSignUps = { native = Routes.ao3ChallengeSignUps("a/b", "Winter & 星", false, true) })
        } }
        compose.onNodeWithText("Sign-ups").performClick()
        assertEquals("ao3-challenge-sign-ups/a%2Fb?title=Winter%20%26%20%E6%98%9F&owner=false&maintainer=true", native)
        assertEquals("Sign-ups", Routes.titleFor(Routes.AO3ChallengeSignUps))
        assertTrue(Routes.hasSubjectHeader(native))
        assertTrue(Routes.hidesTabBar(native))
    }
}
