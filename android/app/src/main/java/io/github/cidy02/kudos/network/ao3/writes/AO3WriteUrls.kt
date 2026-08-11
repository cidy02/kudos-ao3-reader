package io.github.cidy02.kudos.network.ao3.writes

import io.github.cidy02.kudos.network.ao3.AO3Constants
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

object AO3WriteUrls {
    fun workUrl(workId: Long): String {
        require(workId > 0) { "AO3 work id must be positive." }
        return AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("works")
            .addPathSegment(workId.toString())
            .addQueryParameter("view_adult", "true")
            .build()
            .toString()
    }

    fun kudosEndpoint(): String = AO3Constants.baseHttpUrl.newBuilder()
        .addPathSegment("kudos.js")
        .build()
        .toString()

    fun commentsEndpoint(workId: Long): String {
        require(workId > 0) { "AO3 work id must be positive." }
        return AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("works")
            .addPathSegment(workId.toString())
            .addPathSegment("comments")
            .build()
            .toString()
    }

    fun chapterCommentsEndpoint(workId: Long, chapterId: Long): String {
        require(workId > 0) { "AO3 work id must be positive." }
        require(chapterId > 0) { "AO3 chapter id must be positive." }
        return AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("works")
            .addPathSegment(workId.toString())
            .addPathSegment("chapters")
            .addPathSegment(chapterId.toString())
            .addPathSegment("comments")
            .build()
            .toString()
    }

    fun subscriptionsEndpoint(username: String): String {
        val trimmed = username.trim()
        require(trimmed.isNotEmpty()) { "AO3 username is required." }
        return AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("users")
            .addPathSegment(trimmed)
            .addPathSegment("subscriptions")
            .build()
            .toString()
    }

    fun markForLaterEndpoint(workId: Long): String {
        require(workId > 0) { "AO3 work id must be positive." }
        return AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("works")
            .addPathSegment(workId.toString())
            .addPathSegment("mark_for_later")
            .build()
            .toString()
    }

    fun bookmarksEndpoint(workId: Long): String {
        require(workId > 0) { "AO3 work id must be positive." }
        return AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("works")
            .addPathSegment(workId.toString())
            .addPathSegment("bookmarks")
            .build()
            .toString()
    }

    fun absoluteUrl(action: String): String? {
        val trimmed = action.trim()
        if (trimmed.isEmpty()) return null
        trimmed.toHttpUrlOrNull()?.let { return it.toString() }
        return AO3Constants.baseHttpUrl.resolve(trimmed)?.toString()
    }
}
