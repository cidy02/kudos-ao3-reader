package io.github.cidy02.kudos.network.ao3.author

import io.github.cidy02.kudos.network.ao3.AO3Constants

/**
 * Builds AO3 author / user profile URLs.
 */
object AO3AuthorUrls {
    /**
     * Search for works by creator/pseud display name.
     * Returns null when [creator] is blank after trim.
     */
    fun worksSearchUrl(creator: String, page: Int = 1): String? {
        val name = creator.trim()
        if (name.isEmpty()) return null
        return AO3Constants.baseHttpUrl.newBuilder()
            .encodedPath(AO3Constants.SEARCH_PATH)
            .addQueryParameter("work_search[creators]", name)
            .addQueryParameter("page", page.coerceAtLeast(1).toString())
            .build()
            .toString()
    }

    fun userDashboardUrl(username: String, pseud: String? = null): String? {
        val name = username.trim()
        if (name.isEmpty()) return null
        val builder = AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("users")
            .addPathSegment(name)
        if (!pseud.isNullOrBlank()) {
            builder.addPathSegment("pseuds").addPathSegment(pseud.trim())
        }
        return builder.build().toString()
    }

    fun userProfileUrl(username: String): String? {
        val name = username.trim()
        if (name.isEmpty()) return null
        return AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("users")
            .addPathSegment(name)
            .addPathSegment("profile")
            .build()
            .toString()
    }

    /**
     * Direct user works index (`/users/<username>/works` or pseud-scoped).
     */
    fun userWorksUrl(username: String, page: Int = 1, pseud: String? = null): String? {
        val name = username.trim()
        if (name.isEmpty()) return null
        val builder = AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("users")
            .addPathSegment(name)
        if (!pseud.isNullOrBlank()) {
            builder.addPathSegment("pseuds").addPathSegment(pseud.trim())
        }
        builder.addPathSegment("works")
        if (page > 1) {
            builder.addQueryParameter("page", page.toString())
        }
        return builder.build().toString()
    }

    fun userSeriesUrl(username: String, page: Int = 1, pseud: String? = null): String? {
        val name = username.trim()
        if (name.isEmpty()) return null
        val builder = AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("users")
            .addPathSegment(name)
        if (!pseud.isNullOrBlank()) {
            builder.addPathSegment("pseuds").addPathSegment(pseud.trim())
        }
        builder.addPathSegment("series")
        if (page > 1) builder.addQueryParameter("page", page.toString())
        return builder.build().toString()
    }

    fun userBookmarksUrl(username: String, page: Int = 1, pseud: String? = null): String? {
        val name = username.trim()
        if (name.isEmpty()) return null
        val builder = AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("users")
            .addPathSegment(name)
        if (!pseud.isNullOrBlank()) {
            builder.addPathSegment("pseuds").addPathSegment(pseud.trim())
        }
        builder.addPathSegment("bookmarks")
        if (page > 1) builder.addQueryParameter("page", page.toString())
        return builder.build().toString()
    }

    fun preferencesUrl(username: String): String? {
        val name = username.trim()
        if (name.isEmpty()) return null
        return AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("users")
            .addPathSegment(name)
            .addPathSegment("preferences")
            .build()
            .toString()
    }
}
