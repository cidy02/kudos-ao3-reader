package io.github.cidy02.kudos.network.ao3.comments

import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteUrls
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

sealed interface AO3CommentTarget {
    val workId: Long

    fun pageUrl(): String
    fun defaultSubmitUrl(): String

    data class Work(override val workId: Long) : AO3CommentTarget {
        override fun pageUrl(): String {
            return AO3Constants.baseHttpUrl.newBuilder()
                .addPathSegment("works")
                .addPathSegment(workId.toString())
                .addQueryParameter("view_adult", "true")
                .addQueryParameter("show_comments", "true")
                .build()
                .toString()
        }

        override fun defaultSubmitUrl(): String = AO3WriteUrls.commentsEndpoint(workId)
    }

    data class Chapter(
        override val workId: Long,
        val chapterId: Long
    ) : AO3CommentTarget {
        override fun pageUrl(): String {
            return AO3Constants.baseHttpUrl.newBuilder()
                .addPathSegment("works")
                .addPathSegment(workId.toString())
                .addPathSegment("chapters")
                .addPathSegment(chapterId.toString())
                .addQueryParameter("show_comments", "true")
                .build()
                .toString()
        }

        override fun defaultSubmitUrl(): String =
            AO3WriteUrls.chapterCommentsEndpoint(workId, chapterId)
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
    val workAuthors: List<AO3CommentWorkAuthor> = emptyList()
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
    val avatarUrl: String? = null
)

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
