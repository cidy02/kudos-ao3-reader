package io.github.cidy02.kudos.comments

import android.app.Application
import android.content.Context
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.app.DebugShotRequests
import io.github.cidy02.kudos.app.debugShot
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.DemoNetwork
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentTarget
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writes.success
import io.github.cidy02.kudos.network.ao3.writes.writeResource
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** A99: the `thread` screenshot opens the Thread page through the Comments page's own push (as "Continue thread"). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1200dp")
class CommentThreadShotTest {
    @get:Rule val compose = createComposeRule()

    /** Serves the same four-conversation page to every read: AO3_Reader (with a reply), a guest, an anonymous creator. */
    private class Page : AO3Client, AO3AuthenticatedClient {
        private fun answer(): AO3Result<AO3HttpResponse> = success(writeResource("ao3/comments/comments_basic.html"))
        override fun username() = "alice"
        override suspend fun get(url: String, headers: Map<String, String>) = answer()
        override suspend fun getAuthenticated(url: String) = answer()
        override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>,
            headers: Map<String, String>) = AO3Result.Failure(AO3Error.NotFound)
    }

    private fun shows(text: String, ignoreCase: Boolean = false) =
        compose.onAllNodesWithText(text, ignoreCase = ignoreCase, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    @Test fun theThreadShotShowsTheFirstConversationWithRepliesOnTheThreadPage() {
        DemoNetwork.activate(ApplicationProvider.getApplicationContext<Context>().assets, signedIn = true)
        try {
            val shot = debugShot("thread", "queue", "collection", "work", "reader")!!
            DebugShotRequests.open("thread", shot)
            val page = Page()
            compose.setContent {
                KudosTheme(KudosThemeMode.Dark) {
                    CommentsScreen(AO3CommentTarget.Work(999_000_005L), AO3CommentRepository(page, page), onLogin = {})
                }
            }
            // The comments load off the main thread; once they have, the shot pushes the Thread page.
            compose.waitUntil(15_000) { shows("Thread", ignoreCase = true) }
            compose.waitForIdle()
            assertTrue("the first conversation's root author", shows("AO3_Reader"))
            assertTrue("its reply", shows("A nested reply."))
            // The list's other conversations are on the Comments page, which the Thread page replaces.
            assertFalse("not the Comments list", shows("Curious Guest"))
        } finally { DebugShotRequests.clear(); DemoNetwork.resetForTests() }
    }
}
