package io.github.cidy02.kudos.account

import kotlinx.coroutines.Dispatchers
import android.app.Application
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.app.Routes
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemTab
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1600dp")
class AO3CollectionModerationScreenTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var client: ModerationClient
    private val maintainerRoutes = mutableListOf<String>()

    private fun show(owner: Boolean, theme: KudosThemeMode, fromDetail: Boolean = false) {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        runBlocking { auth.restoreSession() }
        client = ModerationClient(auth)
        // Parse on the test thread: see `parseDispatcher`. Off it, this class's first screen
        // sometimes crashed in the list's layout ("Index 2, size 2") or never left "Loading".
        val repository = AO3CollectionDetailRepository(client, auth, parseDispatcher = Dispatchers.Unconfined)
        val writes = AO3WriteRepository(client)
        val prefs = object : DataStore<Preferences> {
            override val data = MutableStateFlow(emptyPreferences())
            override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences {
                val next = transform(data.value); data.value = next; return next
            }
        }
        compose.setContent {
            KudosTheme(theme) {
                var screen by remember { mutableStateOf(if (fromDetail) "detail" else "moderation") }
                var isOwner by remember { mutableStateOf(owner) }
                when (screen) {
                    "detail" -> AO3CollectionDetailScreen("winter_exchange", "Winter Exchange 2026", repository,
                        SettingsRepository(prefs), PrivacyGate(), onOpenWork = {}, onOpenWebFallback = {},
                        onOpenModeration = { isOwner = it; screen = "moderation" }, onOpenSettings = {},
                        onOpenMaintainers = { screen = "maintainers" })
                    "moderation" -> AO3CollectionModerationScreen("winter_exchange", "Winter Exchange 2026", isOwner,
                        repository, writes, onRecentlyDecided = { screen = "items" }, onMaintainers = {
                            maintainerRoutes += Routes.ao3CollectionMaintainers("winter_exchange", "Winter Exchange 2026")
                            screen = "maintainers"
                        }, onMessageCreator = {})
                    "items" -> AO3CollectionItemsScreen("winter_exchange", "Winter Exchange 2026", repository, writes,
                        initialTab = AO3CollectionItemTab.Approved)
                    "maintainers" -> AO3CollectionMaintainersScreen("winter_exchange", "Winter Exchange 2026",
                        repository, writes, onLeft = { screen = "moderation" })
                }
            }
        }
    }

    private fun awaitText(text: String) {
        compose.waitUntil(15_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
        compose.waitForIdle()
    }

    @Test fun manageModerationRowOpensHubAndRecentlyDecidedOpensApprovedItems() {
        show(true, KudosThemeMode.Light, fromDetail = true)
        awaitText("Moderation")
        compose.onNodeWithText("Moderation").performClick()
        awaitText("AWAITING REVIEW")
        compose.onNodeWithText("Moderation").assertExists()
        compose.onNodeWithText("Collection items").assertDoesNotExist()
        compose.onNode(hasScrollAction()).performScrollToNode(hasText("Recently decided"))
        compose.onNodeWithText("Recently decided").performClick()
        awaitText("Collection items")
        compose.waitUntil(15_000) { client.gets.any { it.contains("status=approved") } }
        assertTrue(client.gets.last().contains("status=approved"))
    }

    @Test fun themedRejectDialogCancelSendsNothing() {
        show(true, KudosThemeMode.Light)
        awaitText("The Lantern Ledger")
        compose.onAllNodesWithText("Reject")[0].performClick()
        awaitText("Reject this work?")
        compose.onNodeWithText("This rejects “The Lantern Ledger” from the collection. The work stays on AO3, and its creator receives no reason or email.").assertExists()
        compose.onNodeWithText("Cancel").performClick()
        compose.waitForIdle()
        assertTrue(client.posts.isEmpty()); assertEquals(3, client.gets.size)
    }

    private fun assertNativeMaintainers(row: String) {
        show(true, KudosThemeMode.Light)
        awaitText("The Lantern Ledger")
        compose.onNode(hasScrollAction()).performScrollToNode(hasText(row))
        compose.onNodeWithText(row).performClick()
        awaitText("Maintainers")
        awaitText("Step down as owner")
        compose.onNodeWithText("Winter Exchange 2026 · 4 people").assertExists()
        assertEquals(listOf("ao3-collection-maintainers/winter_exchange?title=Winter%20Exchange%202026"), maintainerRoutes)
        assertTrue(client.posts.isEmpty())
    }

    @Test fun ownersAndModeratorsRowAsksForTheNativeMaintainersRoute() = assertNativeMaintainers("Owners and moderators")
    @Test fun inviteMaintainerRowAsksForTheNativeMaintainersRoute() = assertNativeMaintainers("Invite a maintainer")

    private fun assertNonOwner(theme: KudosThemeMode) {
        show(false, theme)
        awaitText("The Lantern Ledger")
        compose.onNode(hasScrollAction()).performScrollToNode(hasText(
            "Reveal and Remove anonymity are separate actions. You confirm each one, and neither can be undone in Kudos."))
        compose.onNodeWithText("Unrevealed until reveal").assertExists()
        compose.onNodeWithText("Anonymous until reveal").assertExists()
        compose.onNodeWithText("Reveal now").assertDoesNotExist()
        compose.onNodeWithText("Remove anonymity").assertDoesNotExist()
        assertTrue(client.posts.isEmpty())
    }

    @Test fun lightNonOwnerHasSummariesWithoutOwnerActions() = assertNonOwner(KudosThemeMode.Light)
    @Test fun darkNonOwnerHasSummariesWithoutOwnerActions() = assertNonOwner(KudosThemeMode.Dark)
    @Test fun sepiaNonOwnerHasSummariesWithoutOwnerActions() = assertNonOwner(KudosThemeMode.Sepia)
    @Test fun oledNonOwnerHasSummariesWithoutOwnerActions() = assertNonOwner(KudosThemeMode.Oled)
}
