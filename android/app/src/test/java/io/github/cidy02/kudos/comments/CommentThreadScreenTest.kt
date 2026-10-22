package io.github.cidy02.kudos.comments

import android.app.Application
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.comments.AO3Comment
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentAuthor
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1200dp")
class CommentThreadScreenTest {
    @get:Rule val compose = createComposeRule()

    /** The header starts below the floating back circle, as Comments' does (A80: it sat under it). */
    @Test fun theThreadHeaderStartsBelowTheBackButton() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Dark) {
                CommentThreadScreen(
                    root = null, workTitle = "A Test Work", workAuthors = emptyList(), workAuthorUsernames = emptyList(),
                    palette = LocalKudosTokens.current.scopePalette,
                    handlers = CommentThreadHandlers({}, {}, {}, {}, {}, {}, {}), onBack = {}
                )
            }
        }
        // The kicker is the header's first line; it sat at 18dp, under the back circle.
        val top = compose.onNodeWithText("A Test Work", ignoreCase = true).fetchSemanticsNode().boundsInRoot.top
        val belowBackButton = with(compose.density) { 56.dp.toPx() }
        assertTrue("header top $top", top >= belowBackButton)
    }

    /** As iOS's thread screen: no chapter badge on each comment and no fold (A80). */
    @Test fun aThreadHasNoChapterBadgeAndNoFold() {
        val reply = AO3Comment(id = "comment_2", author = AO3CommentAuthor("Calytrix"), date = "Jul 8, 2026",
            body = "That moment was so tender to write.", depth = 1)
        val root = AO3Comment(id = "comment_1", author = AO3CommentAuthor("StarrySky"), date = "Jul 8, 2026",
            body = "That quiet thank you said everything.", chapterLabel = "Chapter 3", replies = listOf(reply))
        compose.setContent {
            KudosTheme(KudosThemeMode.Dark) {
                CommentThreadScreen(
                    root = root, workTitle = "A Test Work", workAuthors = emptyList(), workAuthorUsernames = emptyList(),
                    palette = LocalKudosTokens.current.scopePalette,
                    handlers = CommentThreadHandlers({}, {}, {}, {}, {}, {}, {}), onBack = {}
                )
            }
        }
        compose.onAllNodesWithText("That moment was so tender to write.").assertCountEquals(1)
        compose.onAllNodesWithText("Chapter 3").assertCountEquals(0)
        compose.onAllNodesWithText("Hide").assertCountEquals(0)
    }
}
