package io.github.cidy02.kudos.comments

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.*
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.network.ao3.comments.AO3Comment
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentAuthor
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1200dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CommentPostRowTest {
    @get:Rule val compose = createComposeRule()

    @Test fun authorAvatarKeepsItsNameAndExposesTheProfileHint() {
        var opened: String? = null
        val comment = AO3Comment(id = "comment_1001", author = AO3CommentAuthor("Reader", username = "reader"),
            date = "", body = "Comment body")
        val handlers = CommentThreadHandlers({}, {}, {}, {}, {}, {}, { opened = it })
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CommentPostRow(comment, emptyList(), emptyList(), 0, null, false, false, null,
                    LocalKudosTokens.current.scopePalette, handlers, {})
            }
        }
        val avatar = compose.onNodeWithContentDescription("View Reader's profile")
        assertEquals("open author profile", avatar.fetchSemanticsNode().config[SemanticsActions.OnClick].label)
        avatar.performClick()
        assertEquals("reader", opened)
    }

    @Test fun continueThreadSpeaksSingularAndPluralCountsAsOneLabel() {
        var count by mutableStateOf(1)
        var opens = 0
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CommentConversationRow(
                    CommentConversationRowItem(CommentConversationItem.ContinueThread(1001, count), 1001, false,
                        0, true, emptyList(), null, false),
                    emptyList(), emptyList(), LocalKudosTokens.current.scopePalette,
                    CommentThreadHandlers({}, {}, {}, {}, {}, {}, {}), remember { CommentSwipeTracker() },
                    {}, { opens++ }, {}, 411.dp)
            }
        }
        compose.onNodeWithContentDescription("Continue thread, 1 deeper reply").performClick()
        compose.runOnIdle { count = 3 }
        compose.onNodeWithContentDescription("Continue thread, 3 deeper replies").performClick()
        assertEquals(2, opens)
    }

    @Test fun onlyTheTopLevelCommentShowsItsChapterBadge() {
        val comment = AO3Comment(id = "comment_1001", author = AO3CommentAuthor("Reader"),
            date = "", body = "Comment body", chapterLabel = "Chapter 3")
        val handlers = CommentThreadHandlers({}, {}, {}, {}, {}, {}, {})
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                val palette = LocalKudosTokens.current.scopePalette
                Column {
                    CommentPostRow(comment, emptyList(), emptyList(), depth = 0, replyToAuthor = null,
                        showsParentAttribution = false, parentIsViewer = false, collapse = null,
                        palette = palette, handlers = handlers, onToggleCollapse = {})
                    CommentPostRow(comment.copy(id = "comment_1002"), emptyList(), emptyList(),
                        depth = 1, replyToAuthor = "Reader", showsParentAttribution = true,
                        parentIsViewer = false, collapse = null, palette = palette,
                        handlers = handlers, onToggleCollapse = {})
                }
            }
        }
        // With the reply guard removed this becomes two badges, even though both carry a chapter.
        compose.onAllNodesWithText("Chapter 3", useUnmergedTree = true).assertCountEquals(1)
    }
}
