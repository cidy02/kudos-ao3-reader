package io.github.cidy02.kudos.app

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import io.github.cidy02.kudos.account.*
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.search.AO3SearchRepository
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.search.SearchScreen
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.ui.theme.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Real screens with fixture-only clients; no sockets, accounts, or dialog windows. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class Brief3hdPaletteTest {
    @get:Rule val compose = createComposeRule()
    private var mode by mutableStateOf(KudosThemeMode.Light)
    private lateinit var view: View
    private lateinit var tokens: KudosTokens
    private val washes = ShellWashes()
    private val themes = listOf(KudosThemeMode.Light, KudosThemeMode.Sepia, KudosThemeMode.Dark, KudosThemeMode.Oled)
    private val subject = "Star Wars - All Media Types"
    private val settings = SettingsRepository(object : DataStore<Preferences> {
        override val data = kotlinx.coroutines.flow.MutableStateFlow(emptyPreferences())
        override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences =
            transform(data.value).also { data.value = it }
    })

    private fun show(content: @Composable () -> Unit) {
        compose.setContent { KudosTheme(mode) {
            view = LocalView.current
            tokens = LocalKudosTokens.current
            CompositionLocalProvider(LocalShellWashes provides washes) {
                Box(Modifier.fillMaxSize().background(tokens.background)) { content() }
            }
        } }
    }

    private fun awaitPager() {
        compose.waitUntil(15_000) {
            compose.onAllNodesWithContentDescription("Next Page").fetchSemanticsNodes().isNotEmpty()
        }
        compose.waitForIdle()
    }

    private fun checkNext(node: SemanticsNodeInteraction, hue: Double) {
        compose.waitForIdle() // palettes recorded by composition must be current before the comparison
        assertEquals(hue, washes.page!!.palette.hue, 0.000001)
        val expected = SubjectPalette.fromHue(hue, tokens.theme).controlInk
        val bounds = node.fetchSemanticsNode().boundsInRoot
        lateinit var bitmap: Bitmap
        compose.runOnIdle {
            bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(Canvas(bitmap))
        }
        val matches = (bounds.top.toInt() until bounds.bottom.toInt()).sumOf { y ->
            (bounds.left.toInt() until bounds.right.toInt()).count { x ->
                val actual = Color(bitmap.getPixel(x, y))
                kotlin.math.abs(actual.red - expected.red) < 0.012f &&
                    kotlin.math.abs(actual.green - expected.green) < 0.012f &&
                    kotlin.math.abs(actual.blue - expected.blue) < 0.012f
            }
        }
        bitmap.recycle()
        assertTrue("Next uses the page's ink in $mode ($matches matching pixels)", matches > 3)
    }

    @Test fun searchHeaderAndFooterUseTheResultsSubjectInEveryTheme() {
        val client = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>) =
                AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), worksPage()))
        }
        val repository = AO3SearchRepository(client)
        show { SearchScreen({}, repository = repository) }
        compose.onNode(hasSetTextAction()).performTextInput("lanterns")
        compose.onNode(hasSetTextAction()).performImeAction()
        awaitPager()
        val list = compose.onNode(SemanticsMatcher.keyIsDefined(SemanticsActions.ScrollToIndex))
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            list.performScrollToIndex(0)
            checkNext(compose.onAllNodesWithContentDescription("Next Page").onFirst(), HomeFacts.coverHue(subject))
            list.performScrollToIndex(2) // header, one work, footer
            checkNext(compose.onAllNodesWithContentDescription("Next Page").onLast(), HomeFacts.coverHue(subject))
        }
    }

    @Test fun emptySearchHeaderAlsoReceivesTheResultsPalette() {
        val repository = AO3SearchRepository(object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>) =
                AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), worksPage(includeWork = false)))
        })
        show { SearchScreen({}, repository = repository) }
        compose.onNode(hasSetTextAction()).performTextInput("lanterns")
        compose.onNode(hasSetTextAction()).performImeAction()
        awaitPager()
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            checkNext(compose.onNodeWithContentDescription("Next Page"), HomeFacts.coverHue(subject))
        }
    }

    @Test fun collectionDetailPagerUsesTheLoadedTitlePalette() {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        runBlocking { auth.restoreSession() }
        val repository = AO3CollectionDetailRepository(object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>) =
                AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(),
                    if (url.contains("/profile")) moderationFixture("ao3_demo_moderation_show")
                        .replace("Winter Exchange 2026", subject) else worksPage()))
        }, auth, parseDispatcher = Dispatchers.Unconfined)
        // The fetched title wins over a stale navigation title, as it does on the page's wash.
        show { AO3CollectionDetailScreen("winter_exchange", "Old title", repository, settings, PrivacyGate(),
            {}, {}, {}, {}, {}, { _, _ -> }, { _, _ -> }) }
        val list = compose.onNode(SemanticsMatcher.keyIsDefined(SemanticsActions.ScrollToIndex))
        compose.waitUntil(15_000) { compose.onAllNodesWithText(subject).fetchSemanticsNodes().isNotEmpty() }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            list.performScrollToNode(hasContentDescription("Next Page"))
            checkNext(compose.onNodeWithContentDescription("Next Page"), HomeFacts.workHue(emptyList(), subject))
        }
    }

    @Test fun moderationPagerUsesTheCollectionTitlePalette() {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        runBlocking { auth.restoreSession() }
        val client = ModerationClient(auth)
        val repository = AO3CollectionDetailRepository(client, auth, parseDispatcher = Dispatchers.Unconfined)
        val writes = AO3WriteRepository(client)
        show { AO3CollectionModerationScreen("winter_exchange", subject, true, repository, writes, {}, {}, {}) }
        compose.waitUntil(15_000) { compose.onAllNodesWithText("AWAITING REVIEW").fetchSemanticsNodes().isNotEmpty() }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            compose.onNode(SemanticsMatcher.keyIsDefined(SemanticsActions.ScrollToIndex))
                .performScrollToNode(hasContentDescription("Next Page"))
            checkNext(compose.onNodeWithContentDescription("Next Page"), HomeFacts.workHue(emptyList(), subject))
        }
        assertTrue(client.posts.isEmpty())
    }

    @Test fun promptMemeWashAndPagerUseTheTitleAndFallBackToSlug() {
        val (_, client, repository) = runBlocking { promptMemeSetup() }
        val writes = promptMemeWrites(client, repository.authRepository)
        var title by mutableStateOf(subject)
        show { AO3PromptMemeScreen("summer_meme", title, true, repository, writes, {}) }
        compose.waitUntil(15_000) { compose.onAllNodesWithText("Lanterns after closing").fetchSemanticsNodes().isNotEmpty() }
        for (name in listOf(subject, "")) {
            compose.runOnIdle { title = name }
            for (theme in themes) {
                compose.runOnIdle { mode = theme }
                compose.onNode(SemanticsMatcher.keyIsDefined(SemanticsActions.ScrollToIndex))
                    .performScrollToNode(hasContentDescription("Next Page"))
                checkNext(compose.onNodeWithContentDescription("Next Page"),
                    HomeFacts.workHue(emptyList(), name.ifEmpty { "summer_meme" }))
            }
        }
        assertEquals(0, client.posts)
    }

    private fun worksPage(includeWork: Boolean = true): String = """
        <div id='main'><h2 class='heading'>1 - 1 of 2 Works in $subject</h2>
        <ol class='pagination actions'><li><a href='?page=1'>1</a></li><li><a href='?page=2'>2</a></li></ol>
        <ol class='work index group'>${if (includeWork) """
        <li class='work blurb group' id='work_123'>
        <h4 class='heading'><a href='/works/123'>Original work</a> by <a rel='author'>Writer</a></h4>
        <h5 class='fandoms heading'><a class='tag'>$subject</a></h5>
        <ul class='required-tags'><li><span class='rating-general-audience'><span class='text'>General Audiences</span></span></li></ul>
        <dl class='stats'><dd class='words'>1,000</dd><dd class='chapters'>1/1</dd></dl>
        <blockquote class='userstuff summary'>A visible summary</blockquote></li>
        """ else ""}</ol></div>
    """.trimIndent()
}
