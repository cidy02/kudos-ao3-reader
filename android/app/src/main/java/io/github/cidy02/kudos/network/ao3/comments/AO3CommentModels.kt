package io.github.cidy02.kudos.network.ao3.comments

import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteUrls

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

        override fun defaultSubmitUrl(): String = AO3WriteUrls.chapterCommentsEndpoint(workId, chapterId)
    }
}

data class AO3CommentThread(
    val target: AO3CommentTarget,
    val comments: List<AO3Comment>,
    val form: AO3CommentForm?,
    val commentsLocked: Boolean = false
)

data class AO3Comment(
    val id: String?,
    val author: AO3CommentAuthor,
    val date: String,
    val body: String,
    val depth: Int = 0,
    val isDeletedOrHidden: Boolean = false
)

data class AO3CommentAuthor(
    val name: String,
    val profileUrl: String? = null
)

data class AO3CommentForm(
    val actionUrl: String,
    val authenticityToken: String,
    val pseudId: String?
)
