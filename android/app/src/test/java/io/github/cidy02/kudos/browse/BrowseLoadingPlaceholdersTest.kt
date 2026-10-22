package io.github.cidy02.kudos.browse

import android.app.Application
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseRepository
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import kotlinx.coroutines.channels.Channel
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** All reads terminate in the channel-backed client; this suite cannot contact AO3. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2000dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class BrowseLoadingPlaceholdersTest {
    @get:Rule val compose = createComposeRule()
    private val replies = Channel<AO3Result<AO3HttpResponse>>(Channel.UNLIMITED)
    private var indexReads = 0
    private val client = object : AO3Client {
        override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
            if (url.endsWith("/media")) {
                indexReads++
                return replies.receive()
            }
            // Category prefetches also stay in-process.
            return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(),
                """<ol class="fandom index group"><li><a class="tag" href="/tags/Test">Test Fandom</a> (5)</li></ol>"""))
        }
    }

    private fun show() {
        val repository = AO3BrowseRepository(client = client)
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                BrowseScreen(onOpenCategory = {}, onOpenWebFallback = {}, repository = repository)
            }
        }
        compose.onAllNodesWithContentDescription("Loading AO3 media categories").assertCountEquals(1)
    }

    private fun success() = AO3Result.Success(AO3HttpResponse("fixture:media", 200, emptyMap(),
        """<ul class="media fandom index group"><li class="medium listbox group">
            <h3 class="heading"><a href="/media/Test/fandoms">Test category</a></h3>
            <a class="tag" href="/tags/Test">Test Fandom</a>
        </li></ul>"""))

    @Test fun firstPageReplacesPlaceholdersAndPullRefreshKeepsItsRows() {
        show()
        replies.trySend(success()).getOrThrow()
        compose.waitUntil(15_000) { compose.onAllNodesWithText("Test category").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithContentDescription("Loading AO3 media categories").assertDoesNotExist()
        compose.onRoot().performTouchInput { swipeDown(startY = top + 80f, endY = bottom - 80f, durationMillis = 700) }
        compose.waitUntil(15_000) { indexReads == 2 }
        compose.onNodeWithText("Test category").assertExists()
        compose.onNodeWithContentDescription("Loading AO3 media categories").assertDoesNotExist()
        replies.trySend(success()).getOrThrow()
        compose.waitForIdle()
    }

    @Test fun failureReplacesPlaceholdersAndRetryCanShowResults() {
        show()
        replies.trySend(AO3Result.Failure(AO3Error.Network("Offline fixture"))).getOrThrow()
        compose.waitUntil(15_000) { compose.onAllNodesWithText("Couldn't load fandoms").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithContentDescription("Loading AO3 media categories").assertDoesNotExist()
        compose.onNodeWithText("Try Again").performClick()
        compose.onAllNodesWithContentDescription("Loading AO3 media categories").assertCountEquals(1)
        replies.trySend(success()).getOrThrow()
        compose.waitUntil(15_000) { compose.onAllNodesWithText("Test category").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithContentDescription("Loading AO3 media categories").assertDoesNotExist()
    }
}
