package io.github.cidy02.kudos.network.ao3.author

import io.github.cidy02.kudos.network.ao3.AO3Constants

/**
 * Builds AO3 author work-list URLs.
 *
 * Prefer the structured work search (`work_search[creators]`) so we can open works
 * from a display name scraped from a blurb without needing a separate user-profile
 * parse. Optional [userWorksUrl] covers the `/users/<name>/works` pattern when a
 * true username is available.
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

    /**
     * Direct user works index (`/users/<username>/works`).
     * Returns null when [username] is blank after trim.
     */
    fun userWorksUrl(username: String, page: Int = 1): String? {
        val name = username.trim()
        if (name.isEmpty()) return null
        val builder = AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("users")
            .addPathSegment(name)
            .addPathSegment("works")
        if (page > 1) {
            builder.addQueryParameter("page", page.toString())
        }
        return builder.build().toString()
    }
}
