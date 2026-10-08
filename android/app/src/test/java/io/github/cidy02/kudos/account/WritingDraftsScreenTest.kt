package io.github.cidy02.kudos.account

import android.app.Application
import android.content.Intent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1600dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WritingDraftsScreenTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var client: DraftsMemoryClient
    private lateinit var auth: AO3AuthRepository
    private val opened = mutableListOf<String>()
    private val clock = DraftsTestClock()
    private lateinit var lifecycle: LifecycleRegistry
    private var savedRevision by mutableStateOf(0)

    private fun show(theme: KudosThemeMode = KudosThemeMode.Light, accountRow: Boolean = false,
        signedIn: Boolean = true, largeText: Boolean = false, body: String? = null, error: AO3Error? = null,
        beforeResponse: suspend () -> Unit = {}) {
        val setup = runBlocking { draftsSetup(signedIn) }
        auth = setup.first; client = setup.second
        client.body = body; client.failure = error
        client.beforeResponse = beforeResponse
        val repository = setup.third // Explicit parseDispatcher = Dispatchers.Unconfined in draftsSetup.
        val chrome = PushedShellChrome()
        compose.setContent {
            KudosTheme(theme) {
                val density = LocalDensity.current
                val owner = remember { object : LifecycleOwner {
                    override val lifecycle = LifecycleRegistry(this)
                } }
                lifecycle = owner.lifecycle
                CompositionLocalProvider(LocalPushedShellChrome provides chrome,
                    LocalLifecycleOwner provides owner,
                    LocalDensity provides Density(density.density, if (largeText) 2f else density.fontScale)) {
                    var drafts by remember { mutableStateOf(!accountRow) }
                    Column {
                        Row { chrome.trailingContent?.invoke(this) }
                        if (drafts) WritingDraftsScreen(repository, onOpenWork = { opened += it }, clock = clock,
                            savedRevision = savedRevision)
                        else AccountDraftsRow { drafts = true }
                    }
                }
            }
        }
    }

    private fun awaitText(text: String) {
        compose.waitUntil(15_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
        compose.waitForIdle()
    }

    @Test fun theRealAccountDraftsRowOpensNativeListAndDraftTapRequestsEditAddress() {
        show(accountRow = true)
        assertTrue(client.gets.isEmpty())
        compose.onNodeWithText("Drafts").performClick()
        awaitText("Lanterns Above the Mill")
        assertEquals(1, client.gets.size)
        compose.onNodeWithText("Lanterns Above the Mill").performClick()
        assertEquals(listOf("writing-work?workId=995001"), opened)
        assertEquals(1, client.gets.size) // A tap just hands off an address; no editor-form read here.
    }

    @Test fun sharedTopRightAddIsNamedNewWorkAndRequestsNewWorkAddressWithoutARead() {
        show()
        awaitText("Lanterns Above the Mill")
        compose.onNodeWithContentDescription("New Work").performClick()
        assertEquals(listOf("writing-work"), opened)
        assertEquals(1, client.gets.size)
        compose.onNodeWithText("Post").assertDoesNotExist()
        compose.onNodeWithText("Delete").assertDoesNotExist()
        compose.onNodeWithText("AO3 deletes an unposted draft 30 days after you create it.").assertExists()
        compose.onNodeWithText("Recovery copies", substring = true).assertDoesNotExist()
    }

    @Test fun confirmedSaveReturnReadsTheCurrentDraftsPageOnceAndShowsTheServedChange() {
        show()
        awaitText("Lanterns Above the Mill")
        compose.runOnIdle {
            client.body = draftsFixture(1).replace("Lanterns Above the Mill", "Lanterns after Save")
            savedRevision += 1
        }
        awaitText("Lanterns after Save")
        assertEquals(2, client.gets.size)
        compose.onNodeWithText("Lanterns Above the Mill").assertDoesNotExist()
        compose.waitForIdle()
        assertEquals(2, client.gets.size)
    }

    @Test fun confirmedSaveReturnKeepsTheSelectedDraftsPage() {
        show()
        awaitText("page 1 of 2 · 1 expiring this week on this page")
        compose.onNode(hasScrollAction()).performScrollToNode(hasContentDescription("Next Page"))
        compose.onNodeWithContentDescription("Next Page").performClick()
        awaitText("page 2 of 2 · 2 expiring this week on this page")
        compose.runOnIdle { savedRevision += 1 }
        // A wait on something that is not on screen does not let the screen recompose here.
        compose.waitForIdle()
        compose.waitUntil(15_000) { client.gets.size == 3 }
        awaitText("page 2 of 2 · 2 expiring this week on this page")
        assertEquals(client.gets[1], client.gets[2])
        assertTrue(client.gets[2].endsWith("page=2"))
    }

    @Test fun pageTurnReadsOnlyThatPageAndDayChangeUpdatesChipsWithoutReading() {
        show()
        awaitText("page 1 of 2 · 1 expiring this week on this page")
        compose.onNode(hasScrollAction()).performScrollToNode(hasContentDescription("Next Page"))
        compose.onNodeWithContentDescription("Next Page").performClick()
        awaitText("One More Ferry")
        assertEquals(2, client.gets.size)
        assertTrue(client.gets.last().endsWith("?page=2"))
        compose.onNodeWithContentDescription("1 day left").assertExists()
        compose.onNodeWithContentDescription("Last day").assertExists()
        clock.now = Instant.parse("2026-10-06T12:00:00Z")
        ApplicationProvider.getApplicationContext<Application>().sendBroadcast(Intent(Intent.ACTION_DATE_CHANGED))
        compose.waitUntil(15_000) {
            compose.onAllNodesWithContentDescription("Last day").fetchSemanticsNodes().size == 2
        }
        assertEquals(2, client.gets.size)
    }

    @Test fun signedOutShowsIosErrorAndTryAgainReadsNothing() {
        show(signedIn = false)
        awaitText("Log in to AO3 first.")
        compose.onNodeWithText("Try Again").performClick()
        compose.waitForIdle()
        assertTrue(client.gets.isEmpty())
    }

    @Test fun resumingUpdatesCalendarCopyAndDoesNotRereadTheList() {
        show()
        awaitText("Lanterns Above the Mill")
        compose.runOnIdle {
            lifecycle.currentState = Lifecycle.State.RESUMED
            lifecycle.currentState = Lifecycle.State.STARTED
            clock.now = Instant.parse("2026-10-06T12:00:00Z")
            lifecycle.currentState = Lifecycle.State.RESUMED
        }
        compose.waitUntil(15_000) {
            compose.onAllNodesWithContentDescription("28 days left").fetchSemanticsNodes().isNotEmpty()
        }
        assertEquals(1, client.gets.size)
    }

    @Test fun recognizedEmptyListUsesIosFootnoteAndZeroTally() {
        show(body = "<ol class='work index group'></ol>")
        awaitText("Works you save as drafts appear here.")
        compose.onNodeWithText("0 drafts").assertExists()
        assertEquals(1, client.gets.size)
    }

    @Test fun loadingUsesIosWordsUntilTheOneIndexReadFinishes() {
        val release = CompletableDeferred<Unit>()
        show(beforeResponse = { release.await() })
        awaitText("Loading drafts…")
        assertEquals(1, client.gets.size)
        release.complete(Unit)
        awaitText("Lanterns Above the Mill")
        compose.onNodeWithText("Loading drafts…").assertDoesNotExist()
    }

    @Test fun pullToRefreshReadsTheCurrentPageOnce() {
        show()
        awaitText("Lanterns Above the Mill")
        compose.onRoot().performTouchInput { swipeDown(startY = height * 0.2f, endY = height * 0.8f) }
        compose.waitUntil(15_000) { client.gets.size == 2 }
        awaitText("Lanterns Above the Mill")
        assertEquals(client.gets.first(), client.gets.last())
        assertEquals(2, client.gets.size)
    }

    @Test fun failedListShowsIosErrorAndExplicitTryAgainReadsOnce() {
        show(error = AO3Error.Forbidden)
        awaitText("AO3 refused the request (HTTP 403). Wait a while before trying again.")
        client.failure = null
        compose.onNodeWithText("Try Again").performClick()
        awaitText("Lanterns Above the Mill")
        assertEquals(2, client.gets.size)
    }

    private fun themed(theme: KudosThemeMode, largeText: Boolean = false) {
        show(theme, largeText = largeText)
        awaitText("Lanterns Above the Mill")
        compose.onNodeWithContentDescription("29 days left").assertExists()
        compose.onNode(hasScrollAction()).performScrollToNode(hasText("A Map Without a Date"))
        compose.onNodeWithText("A Map Without a Date").assertExists()
        compose.onNodeWithText("1 word").assertExists()
        // A missing notice cannot borrow p.datetime for either badge or Created.
        compose.onNode(hasText("A Map Without a Date") and hasText("Created ", substring = true)).assertDoesNotExist()
        assertEquals(1, client.gets.size)
    }

    @Test fun lightUsesDraftCardFields() = themed(KudosThemeMode.Light)
    @Test fun darkUsesDraftCardFields() = themed(KudosThemeMode.Dark)
    @Test fun sepiaUsesDraftCardFields() = themed(KudosThemeMode.Sepia)
    @Test fun oledUsesDraftCardFields() = themed(KudosThemeMode.Oled)
    @Test fun accessibilityTextKeepsSummaryAndMetadataAvailable() = themed(KudosThemeMode.Light, true)
}

private class DraftsTestClock : Clock() {
    var now: Instant = Instant.parse("2026-10-05T12:00:00Z")
    override fun instant(): Instant = now
    override fun getZone(): ZoneId = ZoneOffset.UTC
    override fun withZone(zone: ZoneId): Clock = Clock.fixed(now, zone)
}
