package io.github.cidy02.kudos.network.ao3.author

import io.github.cidy02.kudos.network.ao3.AO3Constants
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

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
    fun userWorksUrl(
        username: String,
        page: Int = 1,
        pseud: String? = null,
        scope: AO3AuthorWorksScope = AO3AuthorWorksScope.Works,
        sort: AO3AuthorWorksSort = AO3AuthorWorksSort()
    ): String? {
        val name = username.trim()
        if (name.isEmpty()) return null
        val builder = AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("users")
            .addPathSegment(name)
        if (!pseud.isNullOrBlank()) {
            builder.addPathSegment("pseuds").addPathSegment(pseud.trim())
        }
        scope.pathSegments.forEach(builder::addPathSegment)
        if (page > 1) {
            builder.addQueryParameter("page", page.toString())
        }
        if (scope.acceptsWorkSearch) {
            if (sort.column != AO3AuthorWorksSortColumn.DateUpdated) {
                builder.addQueryParameter("work_search[sort_column]", sort.column.ao3Value)
            }
            if (sort.direction != sort.column.defaultDirection) {
                builder.addQueryParameter("work_search[sort_direction]", sort.direction.ao3Value)
            }
            sort.completion.ao3Value?.let {
                builder.addQueryParameter("work_search[complete]", it)
            }
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

    fun fandomWorksUrl(
        url: String,
        page: Int = 1,
        sort: AO3AuthorWorksSort = AO3AuthorWorksSort()
    ): String? {
        val parsed = url.toHttpUrlOrNull() ?: return null
        val host = parsed.host.lowercase()
        if (host != AO3Constants.WORKS_HOST && !host.endsWith(".${AO3Constants.WORKS_HOST}")) return null
        val builder = parsed.newBuilder()
            .removeAllQueryParameters("page")
            .removeAllQueryParameters("work_search[sort_column]")
            .removeAllQueryParameters("work_search[sort_direction]")
            .removeAllQueryParameters("work_search[complete]")
        if (page > 1) builder.addQueryParameter("page", page.toString())
        if (sort.column != AO3AuthorWorksSortColumn.DateUpdated) {
            builder.addQueryParameter("work_search[sort_column]", sort.column.ao3Value)
        }
        if (sort.direction != sort.column.defaultDirection) {
            builder.addQueryParameter("work_search[sort_direction]", sort.direction.ao3Value)
        }
        sort.completion.ao3Value?.let {
            builder.addQueryParameter("work_search[complete]", it)
        }
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

    /**
     * Drafts index on AO3 (`/users/<username>/works/drafts`).
     * Writing's native drafts list reads this index. "More on AO3" can still open
     * the same address in the in-app browser.
     */
    fun userDraftsUrl(username: String): String? {
        val name = username.trim()
        if (name.isEmpty()) return null
        return AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("users")
            .addPathSegment(name)
            .addPathSegment("works")
            .addPathSegment("drafts")
            .build()
            .toString()
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
