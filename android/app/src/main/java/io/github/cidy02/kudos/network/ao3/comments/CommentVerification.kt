package io.github.cidy02.kudos.network.ao3.comments

import io.github.cidy02.kudos.comments.AO3CommentTimestamp

/** iOS's three-state matcher: a hidden/transformed post cannot be proved absent. */
internal fun commentVerification(
    page: AO3CommentThread, key: CommentSubmissionKey, entry: CommentSubmissionStore.Entry
): CommentVerification {
    fun flattened(comments: List<AO3Comment>): List<AO3Comment> =
        comments.flatMap { listOf(it) + flattened(it.replies) }
    val candidates = if (key.parentId != null) {
        val parent = flattened(page.comments).firstOrNull { it.numericId == key.parentId }
            ?: return CommentVerification.Unknown
        // A cutoff is not the complete set of direct replies.
        if (parent.replies.any { it.isThreadCutoff }) return CommentVerification.Unknown
        parent.replies
    } else page.comments
    var uncertain = entry.mayBeHidden || Regex("<\\s*/?\\s*[A-Za-z][^>]*>|&(?:#\\d+|#[xX][0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]+);")
        .containsMatchIn(key.body)
    for (comment in candidates) {
        if (comment.isDeletedOrHidden || comment.isThreadCutoff) { uncertain = true; continue }
        if (CommentSubmissionKey.normalize(comment.body) != key.body) continue
        if (comment.isAnonymousCreator) { uncertain = true; continue }
        if (comment.isGuest) continue
        val username = comment.author.username
        if (username == null) { uncertain = true; continue }
        if (!username.equals(key.identity, ignoreCase = true)) continue
        val postedAt = AO3CommentTimestamp.parse(comment.date)?.time
        if (postedAt != null && postedAt < entry.submittedAt - 600_000) { uncertain = true; continue }
        return CommentVerification.Found
    }
    return if (uncertain) CommentVerification.Unknown else CommentVerification.Absent
}
