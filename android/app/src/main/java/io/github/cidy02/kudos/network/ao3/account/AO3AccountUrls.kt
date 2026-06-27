package io.github.cidy02.kudos.network.ao3.account

import io.github.cidy02.kudos.account.AccountListType
import io.github.cidy02.kudos.network.ao3.AO3Constants

class AO3AccountUrls {
    fun url(type: AccountListType, username: String, page: Int = 1): String {
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
        }

        if (page > 1) builder.addQueryParameter("page", page.toString())
        return builder.build().toString()
    }
}
