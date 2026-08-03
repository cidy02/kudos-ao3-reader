package io.github.cidy02.kudos.network.ao3.comments

import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteUrls
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

sealed interface AO3CommentTarget {
    val workId: Long

    /**
     * Comments page URL. [page] is included as `?page=N` only when N > 1,
     * matching iOS `AO3Client.commentsPageURL`.
     */
    fun pageUrl(page: Int = 1): String
    fun defaultSubmitUrl(): String

    data class Work(override val workId: Long) : AO3CommentTarget {
        override fun pageUrl(page: Int): String {
            val builder = AO3Constants.baseHttpUrl.newBuilder()
                .addPathSegment("works")
                .addPathSegment(workId.toString())
                .addQueryParameter("view_adult", "true")
                .addQueryParameter("show_comments", "true")
            if (page > 1) {
                builder.addQueryParameter("page", page.toString())
            }
            return builder.build().toString()
        }

        override fun defaultSubmitUrl(): String = AO3WriteUrls.commentsEndpoint(workId)
    }

    data class Chapter(
        override val workId: Long,
        val chapterId: Long
    ) : AO3CommentTarget {
        override fun pageUrl(page: Int): String {
            val builder = AO3Constants.baseHttpUrl.newBuilder()
                .addPathSegment("works")
                .addPathSegment(workId.toString())
                .addPathSegment("chapters")
                .addPathSegment(chapterId.toString())
                .addQueryParameter("show_comments", "true")
            if (page > 1) {
                builder.addQueryParameter("page", page.toString())
            }
            return builder.build().toString()
        }

        override fun defaultSubmitUrl(): String =
            AO3WriteUrls.chapterCommentsEndpoint(workId, chapterId)
    }
}

/**
 * Local URL helpers for comment replies. Kept inside the comments package so
 * we don't need to touch shared [AO3WriteUrls] (out of scope for this task).
 * Mirrors iOS `AO3AuthService.commentThreadURL` / `commentReplyEndpoint`.
 */
object AO3CommentUrls {
    /** Standalone comment-thread page used as the CSRF/pseud source for replies. */
    fun commentThreadUrl(commentId: Long, isReply: Boolean = false): String {
        require(commentId > 0) { "AO3 comment id must be positive." }
        val builder = AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("comments")
            .addPathSegment(commentId.toString())
        if (isReply) {
            builder.addQueryParameter("add_comment_reply_id", commentId.toString())
        }
        return builder.build().toString()
    }

    /** POST target for a reply to [parentCommentId]. */
    fun commentReplyEndpoint(parentCommentId: Long): String {
        require(parentCommentId > 0) { "AO3 comment id must be positive." }
        return AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("comments")
            .addPathSegment(parentCommentId.toString())
            .addPathSegment("comments")
            .build()
            .toString()
    }
}

/**
 * Role chip shown beside a commenter's name across Comments and (later) Inbox.
 * "Author" means the creator of the work being discussed; "User" is any other
 * registered AO3 account; "Guest" is an unregistered commenter.
 *
 * Port of iOS `AO3CommentParticipantRole.resolve` (AO3CommentModels.swift).
 */
enum class AO3CommentParticipantRole(val label: String) {
    Me("Me"),
    Author("Author"),
    User("User"),
    Guest("Guest");

    companion object {
        fun resolve(
            name: String,
            isGuest: Boolean,
            isAnonymousCreator: Boolean = false,
            commenterUsername: String? = null,
            currentUsername: String? = null,
            workAuthors: List<String>,
            workAuthorUsernames: List<String> = emptyList()
        ): AO3CommentParticipantRole {
            // Compare AO3 account usernames, not display pseud names: a user may
            // comment under any of their pseuds. "Me" intentionally wins over
            // "Author" when the signed-in creator is viewing their own comment.
            val commenter = normalized(commenterUsername)
            val current = normalized(currentUsername)
            if (commenter != null &&
                current != null &&
                commenter.equals(current, ignoreCase = true)
            ) {
                return Me
            }
            // AO3 only emits this state when the work creator commented
            // anonymously, so it remains an author even though no profile resolves.
            if (isAnonymousCreator) return Author
            // Guest display names and registered pseud names are not globally
            // unique. A guest can never become Author via name-only fallback.
            if (isGuest) return Guest
            // When both sides expose canonical account identities, they are
            // authoritative: two different accounts may use the same pseud name.
            if (commenter != null && workAuthorUsernames.isNotEmpty()) {
                return if (workAuthorUsernames.any {
                        it.equals(commenter, ignoreCase = true)
                    }
                ) {
                    Author
                } else {
                    User
                }
            }
            if (workAuthors.any {
                    it.trim().equals(name.trim(), ignoreCase = true)
                }
            ) {
                return Author
            }
            return User
        }

        private fun normalized(value: String?): String? {
            val trimmed = value?.trim().orEmpty()
            return trimmed.takeIf { it.isNotEmpty() }
        }
    }
}

/**
 * One work-preface author identity captured from the comments page byline.
 * Used for Author-role resolution (display name + optional account username).
 */
data class AO3CommentWorkAuthor(
    val displayName: String,
    val username: String? = null,
    val profileUrl: String? = null
)

data class AO3CommentThread(
    val target: AO3CommentTarget,
    val comments: List<AO3Comment>,
    val form: AO3CommentForm?,
    val commentsLocked: Boolean = false,
    /** Work creators from the page preface byline (for Author role chips). */
    val workAuthors: List<AO3CommentWorkAuthor> = emptyList(),
    /** One-based page that was requested / parsed (iOS `AO3CommentsPage.currentPage`). */
    val currentPage: Int = 1,
    /**
     * Highest page number found in `ol.pagination li` (never less than
     * [currentPage]). Matches iOS / Android account/inbox pagination idiom.
     */
    val totalPages: Int = 1,
    /** Opportunistic work-level comment total from `dl.stats dd.comments`. */
    val totalComments: Int? = null
)

data class AO3Comment(
    val id: String?,
    val author: AO3CommentAuthor,
    val date: String,
    val body: String,
    val depth: Int = 0,
    val isDeletedOrHidden: Boolean = false,
    /** Unregistered commenter (no profile link). */
    val isGuest: Boolean = false,
    /**
     * AO3 explicitly rendered its protected anonymous-creator identity.
     * Must not be inferred from a guest choosing the same display string.
     */
    val isAnonymousCreator: Boolean = false,
    /**
     * User icon URL already present in the comment markup, or null when AO3
     * fell back to its default logo / guest / missing icon. Never the AO3
     * skin logo under `/images/skins/`.
     */
    val avatarUrl: String? = null,
    /**
     * AO3 exposed a Reply action for this comment in this session
     * (parsed from the comment's own action list).
     */
    val canReply: Boolean = false
) {
    /**
     * Numeric AO3 comment id for reply endpoints (`comment_1252794206` → 1252794206).
     * Null when [id] is missing or not the expected `comment_<digits>` shape.
     */
    val numericId: Long?
        get() {
            val raw = id?.trim().orEmpty()
            if (raw.isEmpty()) return null
            val digits = if (raw.startsWith("comment_", ignoreCase = true)) {
                raw.substring("comment_".length)
            } else {
                raw
            }
            return digits.toLongOrNull()?.takeIf { it > 0 }
        }
}

data class AO3CommentAuthor(
    val name: String,
    val profileUrl: String? = null,
    /** Canonical AO3 account username from the profile path, when resolvable. */
    val username: String? = null
)

data class AO3CommentForm(
    val actionUrl: String,
    val authenticityToken: String,
    val pseudId: String?
)

/**
 * Avatar URL helpers ported from iOS `AO3Comment.avatarURL(forIconSource:)` /
 * `isDefaultAO3Icon(_:)` (AO3CommentModels.swift).
 *
 * AO3's bundled skin artwork under `/images/skins/` is the site logo — not a
 * user's picture. Treat those as "no avatar" so the UI shows a generic
 * placeholder instead of the AO3 trademark.
 */
object AO3CommentAvatar {
    fun isDefaultAO3Icon(url: String): Boolean {
        val httpUrl = url.toHttpUrlOrNull() ?: return false
        val host = httpUrl.host
        val isAo3Host = host == AO3Constants.WORKS_HOST ||
            host.endsWith(".${AO3Constants.WORKS_HOST}")
        if (!isAo3Host) return false
        return httpUrl.encodedPath.startsWith("/images/skins/")
    }

    /**
     * Absolute avatar URL for a comment icon `src`, or null when missing /
     * default AO3 skin logo.
     */
    fun avatarUrlForIconSource(source: String?): String? {
        val absolute = absoluteAo3Url(source) ?: return null
        return if (isDefaultAO3Icon(absolute)) null else absolute
    }

    fun absoluteAo3Url(pathOrUrl: String?): String? {
        val raw = pathOrUrl?.trim().orEmpty()
        if (raw.isEmpty()) return null
        if (raw.startsWith("http://") || raw.startsWith("https://")) {
            return raw.toHttpUrlOrNull()?.toString()
        }
        if (raw.startsWith("//")) {
            return "https:$raw".toHttpUrlOrNull()?.toString()
        }
        val base = AO3Constants.BASE_URL.toHttpUrlOrNull() ?: return null
        return base.resolve(raw)?.toString()
    }

    /** Account username from a profile path or absolute profile URL. */
    fun usernameFromProfilePath(pathOrUrl: String?): String? {
        if (pathOrUrl.isNullOrBlank()) return null
        val path = when {
            pathOrUrl.startsWith("http://") || pathOrUrl.startsWith("https://") -> {
                pathOrUrl.toHttpUrlOrNull()?.encodedPath ?: return null
            }
            else -> pathOrUrl.substringBefore('?').substringBefore('#')
        }
        val segments = path.trim('/').split('/').filter { it.isNotEmpty() }
        if (segments.size < 2 || !segments[0].equals("users", ignoreCase = true)) {
            return null
        }
        val username = runCatching {
            URLDecoder.decode(segments[1], StandardCharsets.UTF_8.name())
        }.getOrDefault(segments[1]).trim()
        if (username.isEmpty()) return null
        if (username.equals("login", ignoreCase = true) ||
            username.equals("logout", ignoreCase = true)
        ) {
            return null
        }
        return username
    }
}
