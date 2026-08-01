package io.github.cidy02.kudos.network.ao3.account

import io.github.cidy02.kudos.account.AccountListType
import io.github.cidy02.kudos.network.ao3.AO3Constants

class AO3AccountUrls {
    fun url(type: AccountListType, username: String, page: Int = 1): String {
        return when (type) {
            is AccountListType.Collection -> collectionWorksUrl(type.name, page)
            else -> userScopedUrl(type, username, page)
        }
    }

    /** User collections index: `/users/<name>/collections`. */
    fun collectionsUrl(username: String, page: Int = 1): String {
        val builder = AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("users")
            .addPathSegment(username.trim())
            .addPathSegment("collections")
        if (page > 1) builder.addQueryParameter("page", page.toString())
        return builder.build().toString()
    }

    /** Works in a collection: `/collections/<name>/works` (standard work blurbs). */
    fun collectionWorksUrl(name: String, page: Int = 1): String {
        val builder = AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("collections")
            .addPathSegment(name.trim())
            .addPathSegment("works")
        if (page > 1) builder.addQueryParameter("page", page.toString())
        return builder.build().toString()
    }

    private fun userScopedUrl(type: AccountListType, username: String, page: Int): String {
        val builder = AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("users")
            .addPathSegment(username.trim())

        when (type) {
            AccountListType.MarkedForLater -> {
                builder.addPathSegment("readings")
                builder.addQueryParameter("show", "to-read")
            }
            AccountListType.History -> builder.addPathSegment("readings")
            AccountListType.Bookmarks -> builder.addPathSegment("bookmarks")
            AccountListType.Subscriptions -> {
                builder.addPathSegment("subscriptions")
                builder.addQueryParameter("type", "works")
            }
            AccountListType.MyWorks -> builder.addPathSegment("works")
            is AccountListType.Collection -> error("Collection URLs are not user-scoped.")
        }

        if (page > 1) builder.addQueryParameter("page", page.toString())
        return builder.build().toString()
    }
}
