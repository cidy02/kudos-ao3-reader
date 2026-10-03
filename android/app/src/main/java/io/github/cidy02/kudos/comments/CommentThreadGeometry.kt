package io.github.cidy02.kudos.comments

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.comments.AO3Comment

/**
 * Geometry for comment threads — ported from iOS `CommentThreadGeometry` (CommentThreadRow.swift:38).
 *
 * Threads render inline down to AO3's own nesting limit (5). Replies deeper than that
 * go behind "Continue thread".
 */
object CommentThreadGeometry {
    val sideMargin: Dp = 16.dp
    val conversationGap: Dp = 18.dp
    val rowTopPadding: Dp = 12.dp
    const val maxInlineDepth: Int = 5
    val railWidth: Dp = 1.dp
    val railAvatarGap: Dp = 5.dp

    fun avatarSize(depth: Int): Dp = when (maxOf(0, depth)) {
        0 -> 30.dp
        1 -> 26.dp
        else -> 22.dp
    }

    fun avatarContentSpacing(depth: Int): Dp =
        if (depth <= 0) 11.dp else 10.dp

    fun elbowRadius(depth: Int): Dp =
        if (depth <= 1) 21.dp else 18.dp

    const val autoExpandedMaxReplies: Int = 8
    const val repliesChunkSize: Int = 20
    const val collapsedBodyLineLimit: Int = 5

    fun idealIndent(depth: Int): Dp {
        val clamped = minOf(maxOf(0, depth), maxInlineDepth)
        var sum = 0.dp
        for (i in 0 until clamped) {
            sum += avatarSize(i) + avatarContentSpacing(i)
        }
        return sum
    }

    fun minimumContentWidth(isAccessibilitySize: Boolean, isLarge: Boolean): Dp {
        if (isAccessibilitySize) return 280.dp
        return if (isLarge) 240.dp else 200.dp
    }

    fun indent(
        depth: Int,
        availableWidth: Dp,
        isAccessibilitySize: Boolean = false,
        isLarge: Boolean = false
    ): Dp {
        val budget = availableWidth - sideMargin * 2 -
            avatarSize(depth) - avatarContentSpacing(depth) -
            minimumContentWidth(isAccessibilitySize, isLarge)
        val ideal = idealIndent(depth)
        return maxOf(0.dp, minOf(ideal, budget))
    }

    /**
     * Depth-first list of every reply under a root (root itself excluded),
     * each becoming its own row.
     */
    fun flattenedReplies(root: AO3Comment): List<FlattenedReply> {
        val result = mutableListOf<FlattenedReply>()
        val stack = ArrayDeque<FlattenedReply>()
        for (child in root.replies.reversed()) {
            stack.add(
                FlattenedReply(
                    comment = child,
                    depth = 1,
                    parentAuthor = root.author.name,
                    parentIsViewer = root.editPath != null
                )
            )
        }
        while (stack.isNotEmpty()) {
            val item = stack.removeLast()
            result.add(item)
            for (child in item.comment.replies.reversed()) {
                stack.add(
                    FlattenedReply(
                        comment = child,
                        depth = item.depth + 1,
                        parentAuthor = item.comment.author.name,
                        parentIsViewer = item.comment.editPath != null
                    )
                )
            }
        }
        return result
    }
}

/** One reply in display order (DFS under a top-level comment). */
data class FlattenedReply(
    val comment: AO3Comment,
    val depth: Int,
    val parentAuthor: String,
    val parentIsViewer: Boolean = false
) {
    val id: String? get() = comment.id
}

/** One row of a rendered conversation (iOS CommentConversationItem). */
sealed interface CommentConversationItem {
    val id: String
    val connectorDepth: Int
    val actionableComment: AO3Comment?

    data class Post(
        val comment: AO3Comment,
        val parentAuthor: String?,
        val depth: Int,
        val parentIsViewer: Boolean = false
    ) : CommentConversationItem {
        override val id: String = "post-${comment.id}"
        override val connectorDepth: Int = depth
        override val actionableComment: AO3Comment = comment
    }

    data class Expander(
        val rootId: Long,
        val hiddenCount: Int,
        val showsVerb: Boolean
    ) : CommentConversationItem {
        override val id: String = "expander-$rootId"
        override val connectorDepth: Int = 0
        override val actionableComment: AO3Comment? = null
    }

    data class ContinueThread(
        val rootId: Long,
        val hiddenCount: Int
    ) : CommentConversationItem {
        override val id: String = "continue-$rootId"
        override val connectorDepth: Int = 0
        override val actionableComment: AO3Comment? = null
    }
}

/** Whether a conversation is folded, and how much folding it hides. */
data class CommentCollapseState(
    val isCollapsed: Boolean,
    val replyCount: Int
) {
    val label: String get() = if (isCollapsed) "Show $replyCount" else "Hide"
    val accessibilityLabel: String
        get() = if (isCollapsed) {
            "Show $replyCount ${if (replyCount == 1) "reply" else "replies"}"
        } else {
            "Hide replies"
        }
}

/**
 * One row of the comments list, already resolved to everything the row view needs.
 */
data class CommentConversationRowItem(
    val item: CommentConversationItem,
    val rootId: Long,
    val startsConversation: Boolean,
    val depth: Int,
    val isLastSibling: Boolean,
    val ancestorLines: List<Boolean>,
    val nextDepth: Int?,
    val showsParentAttribution: Boolean,
    val ancestorIds: List<Long> = emptyList(),
    val collapse: CommentCollapseState? = null
) {
    val id: String get() = item.id
}

/**
 * Builds the flat row list for top-level conversations (iOS CommentConversationBuilder).
 */
object CommentConversationBuilder {

    fun representedCount(replies: Sequence<FlattenedReply>): Int =
        replies.sumOf { reply ->
            if (reply.comment.isThreadCutoff) {
                maxOf(1, reply.comment.cutoffCount ?: 1)
            } else {
                1
            }
        }

    fun items(
        root: AO3Comment,
        replies: List<FlattenedReply>,
        isExpanded: Boolean,
        visibleReplyCount: Int,
        maxDepth: Int = CommentThreadGeometry.maxInlineDepth
    ): List<CommentConversationItem> {
        val rootId = root.numericId ?: 0L
        val inline = replies.filter { it.depth <= maxDepth }
        val deeper = representedCount(replies.asSequence().filter { it.depth > maxDepth })
        val showsReplies = isExpanded || inline.size <= CommentThreadGeometry.autoExpandedMaxReplies

        if (inline.isEmpty() || !showsReplies) {
            val list = mutableListOf<CommentConversationItem>(
                CommentConversationItem.Post(comment = root, parentAuthor = null, depth = 0)
            )
            if (inline.isNotEmpty()) {
                list.add(
                    CommentConversationItem.Expander(
                        rootId = rootId,
                        hiddenCount = representedCount(inline.asSequence()),
                        showsVerb = false
                    )
                )
            }
            return list
        }

        val shown = inline.take(maxOf(visibleReplyCount, CommentThreadGeometry.autoExpandedMaxReplies))
        val hidden = representedCount(inline.drop(shown.size).asSequence())
        val list = mutableListOf<CommentConversationItem>(
            CommentConversationItem.Post(comment = root, parentAuthor = null, depth = 0)
        )
        for (reply in shown) {
            list.add(
                CommentConversationItem.Post(
                    comment = reply.comment,
                    parentAuthor = reply.parentAuthor,
                    depth = reply.depth,
                    parentIsViewer = reply.parentIsViewer
                )
            )
        }
        if (hidden > 0) {
            list.add(
                CommentConversationItem.Expander(
                    rootId = rootId,
                    hiddenCount = hidden,
                    showsVerb = true
                )
            )
        } else if (deeper > 0) {
            list.add(
                CommentConversationItem.ContinueThread(
                    rootId = rootId,
                    hiddenCount = deeper
                )
            )
        }
        return list
    }

    private fun hasLaterPeer(depth: Int, afterIndex: Int, depths: List<Int>): Boolean {
        var i = afterIndex + 1
        while (i < depths.size) {
            if (depths[i] < depth) return false
            if (depths[i] == depth) return true
            i++
        }
        return false
    }

    fun rows(
        roots: List<AO3Comment>,
        repliesByRoot: Map<Long, List<FlattenedReply>>,
        expandedRootIds: Set<Long>,
        visibleReplyCounts: Map<Long, Int>,
        collapsedRootIds: Set<Long> = emptySet(),
        maxDepth: Int = CommentThreadGeometry.maxInlineDepth
    ): List<CommentConversationRowItem> {
        val rows = mutableListOf<CommentConversationRowItem>()
        for ((conversationIndex, root) in roots.withIndex()) {
            val rootId = root.numericId ?: 0L
            val replies = repliesByRoot[rootId] ?: emptyList()
            val isCollapsed = collapsedRootIds.contains(rootId)
            val items: List<CommentConversationItem> = if (isCollapsed) {
                listOf(CommentConversationItem.Post(comment = root, parentAuthor = null, depth = 0))
            } else {
                items(
                    root = root,
                    replies = replies,
                    isExpanded = expandedRootIds.contains(rootId),
                    visibleReplyCount = visibleReplyCounts[rootId] ?: CommentThreadGeometry.repliesChunkSize,
                    maxDepth = maxDepth
                )
            }

            val showsReplyPosts = items.any { it is CommentConversationItem.Post && it.depth > 0 }
            val offersCollapse = replies.isNotEmpty() && (isCollapsed || showsReplyPosts)
            val depths = items.map { it.connectorDepth }
            val path = mutableListOf<Long>()

            for ((index, item) in items.withIndex()) {
                val depth = depths[index]
                val ancestors = path.take(depth)
                if (item is CommentConversationItem.Post) {
                    val cId = item.comment.numericId ?: 0L
                    path.clear()
                    path.addAll(ancestors)
                    path.add(cId)
                }

                rows.add(
                    CommentConversationRowItem(
                        item = item,
                        rootId = rootId,
                        startsConversation = index == 0 && conversationIndex > 0,
                        depth = depth,
                        isLastSibling = !hasLaterPeer(depth, index, depths),
                        ancestorLines = (0 until maxOf(0, depth - 1)).map { level ->
                            hasLaterPeer(level + 1, index, depths)
                        },
                        nextDepth = if (index + 1 < depths.size) depths[index + 1] else null,
                        showsParentAttribution = depth > 0 &&
                            (index == 0 || depths[index - 1] != depth - 1),
                        ancestorIds = ancestors,
                        collapse = if (index == 0 && offersCollapse) {
                            CommentCollapseState(
                                isCollapsed = isCollapsed,
                                replyCount = representedCount(replies.asSequence())
                            )
                        } else {
                            null
                        }
                    )
                )
            }
        }
        return rows
    }
}

/** Every reply beneath this comment, not just its direct children. */
fun AO3Comment.totalReplyCount(): Int =
    replies.sumOf { 1 + it.totalReplyCount() }
