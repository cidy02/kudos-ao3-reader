package io.github.cidy02.kudos.comments

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.network.ao3.comments.AO3Comment
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.subjectScreenWash

/**
 * AO3's Thread / Parent Thread page natively (iOS `CommentThreadScreen.swift`).
 * Shows one comment and everything under it, fully expanded.
 */
@Composable
fun CommentThreadScreen(
    root: AO3Comment?,
    workTitle: String,
    workAuthors: List<String>,
    workAuthorUsernames: List<String>,
    palette: SubjectPalette,
    handlers: CommentThreadHandlers,
    onBack: () -> Unit
) {
    BackHandler(onBack = onBack)

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        hideTabBar = true,
        onBack = onBack
    )

    val configuration = LocalConfiguration.current
    val screenWidth = configuration.screenWidthDp.dp
    val swipeTracker = remember { CommentSwipeTracker() }

    val threadSubtitle = remember(root) {
        if (root == null) null
        else listOfNotNull(root.chapterLabel?.takeIf { it.isNotBlank() }, root.author.name)
            .joinToString(" · ")
    }

    val rows = remember(root) {
        if (root == null) emptyList()
        else {
            val rootId = root.numericId ?: 0L
            CommentConversationBuilder.rows(
                roots = listOf(root),
                repliesByRoot = mapOf(rootId to CommentThreadGeometry.flattenedReplies(root)),
                expandedRootIds = setOf(rootId),
                visibleReplyCounts = mapOf(rootId to Int.MAX_VALUE),
                maxDepth = Int.MAX_VALUE
            )
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .subjectScreenWash(palette, 480.dp)
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxSize()
        ) {
            item {
                SubjectHeaderBlock(
                    kicker = workTitle,
                    title = "Thread",
                    subtitle = threadSubtitle,
                    palette = palette,
                    modifier = Modifier.padding(top = 18.dp)
                )
            }

            if (root == null) {
                item {
                    ContentUnavailableView(
                        title = "Thread Unavailable",
                        description = "This comment is no longer on this page. Go back to Comments to continue.",
                        palette = palette,
                        modifier = Modifier.padding(top = 32.dp)
                    )
                }
            } else {
                items(
                    items = rows,
                    key = { it.id }
                ) { row ->
                    CommentConversationRow(
                        row = row,
                        workAuthors = workAuthors,
                        workAuthorUsernames = workAuthorUsernames,
                        palette = palette,
                        handlers = handlers,
                        swipeTracker = swipeTracker,
                        onExpand = {},
                        onContinueThread = {},
                        onToggleCollapse = {},
                        containerWidth = screenWidth
                    )
                }
            }

            item {
                Box(Modifier.padding(bottom = 64.dp))
            }
        }
    }
}
