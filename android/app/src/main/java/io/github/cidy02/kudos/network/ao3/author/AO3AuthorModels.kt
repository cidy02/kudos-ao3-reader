package io.github.cidy02.kudos.network.ao3.author

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary

data class AO3AuthorRoute(
    val username: String,
    val pseud: String? = null
) {
    val displayName: String get() = pseud ?: username

    val id: String
        get() = if (pseud.isNullOrBlank()) username.lowercase()
        else "${username.lowercase()}|${pseud.lowercase()}"

    val dashboardUrl: String
        get() = AO3AuthorUrls.userDashboardUrl(username, pseud)!!

    val profileUrl: String
        get() = AO3AuthorUrls.userProfileUrl(username)!!

    val worksUrl: String
        get() = AO3AuthorUrls.userWorksUrl(username, page = 1, pseud = pseud)!!

    val seriesUrl: String
        get() = AO3AuthorUrls.userSeriesUrl(username, page = 1, pseud = pseud)!!

    val bookmarksUrl: String
        get() = AO3AuthorUrls.userBookmarksUrl(username, page = 1, pseud = pseud)!!
}

data class AO3AuthorPseud(
    val name: String,
    val route: AO3AuthorRoute,
    val avatarUrl: String? = null
)

data class AO3AuthorFandom(
    val name: String,
    val workCount: Int?,
    val url: String
)

data class AO3AuthorWebAction(
    val label: String,
    val url: String,
    val kind: Kind
) {
    enum class Kind { Block, Mute, Profile, Pseuds, Works, Preferences, Dashboard, Other }
}

data class AO3AuthorSubscriptionForm(
    val label: String,
    val actionUrl: String,
    val fields: List<Pair<String, String>>,
    val csrfToken: String,
    val referer: String
) {
    val isSubscribed: Boolean
        get() = label.contains("unsubscribe", ignoreCase = true) ||
            fields.any { it.first == "_method" && it.second.equals("delete", ignoreCase = true) }
}

data class AO3AuthorHeader(
    val username: String,
    val displayName: String,
    val avatarUrl: String?,
    val userId: Long?,
    val pseuds: List<AO3AuthorPseud>,
    val fandoms: List<AO3AuthorFandom>,
    val subscriptionForm: AO3AuthorSubscriptionForm?,
    val actions: List<AO3AuthorWebAction>,
    /** Null means the dashboard group was absent or unreadable; empty means AO3 showed an empty group. */
    val recentWorks: List<AO3WorkSummary>? = null,
    val recentSeries: List<AO3AuthorSeriesSummary>? = null,
    val recentBookmarks: List<AO3AuthorBookmark>? = null
)

enum class AO3AuthorWorksScope(val label: String, val pathSegments: List<String>) {
    Works("Works", listOf("works")),
    Collected("In collections", listOf("works", "collected")),
    Gifts("Gifts", listOf("gifts"));

    val acceptsWorkSearch: Boolean
        get() = this != Gifts
}

enum class AO3AuthorWorksSortColumn(val label: String, val ao3Value: String) {
    Creator("Creator", "authors_to_sort_on"),
    Title("Title", "title_to_sort_on"),
    DatePosted("Date Posted", "created_at"),
    DateUpdated("Date Updated", "revised_at"),
    WordCount("Word Count", "word_count"),
    Hits("Hits", "hits"),
    Kudos("Kudos", "kudos_count"),
    Comments("Comments", "comments_count"),
    Bookmarks("Bookmarks", "bookmarks_count");

    val defaultDirection: AO3AuthorWorksSortDirection
        get() = if (this == Creator || this == Title) {
            AO3AuthorWorksSortDirection.Ascending
        } else {
            AO3AuthorWorksSortDirection.Descending
        }
}

enum class AO3AuthorWorksSortDirection(val label: String, val ao3Value: String) {
    Ascending("Ascending", "asc"),
    Descending("Descending", "desc")
}

enum class AO3AuthorWorksCompletion(val label: String, val ao3Value: String?) {
    Any("Any", null),
    Complete("Complete", "T"),
    InProgress("In progress", "F")
}

data class AO3AuthorWorksSort(
    val column: AO3AuthorWorksSortColumn = AO3AuthorWorksSortColumn.DateUpdated,
    val direction: AO3AuthorWorksSortDirection = AO3AuthorWorksSortDirection.Descending,
    val completion: AO3AuthorWorksCompletion = AO3AuthorWorksCompletion.Any
) {
    fun select(column: AO3AuthorWorksSortColumn): AO3AuthorWorksSort =
        if (column == this.column) this else copy(column = column, direction = column.defaultDirection)

    val activeCount: Int
        get() = listOf(
            column != AO3AuthorWorksSortColumn.DateUpdated,
            direction != column.defaultDirection,
            completion != AO3AuthorWorksCompletion.Any
        ).count { it }
}

data class AO3AuthorAbout(
    val profileTitle: String,
    val bioText: String,
    val pseuds: List<AO3AuthorPseud>,
    val joinedDate: String,
    val userId: Long?,
    val actions: List<AO3AuthorWebAction>
)

data class AO3AuthorSeriesSummary(
    val id: Long,
    val title: String,
    val creators: List<String>,
    val fandoms: List<String>,
    val summary: String,
    val words: Int?,
    val workCount: Int?,
    val dateUpdated: String,
    val isComplete: Boolean?,
    val url: String,
    val creatorUsernames: List<String> = emptyList()
)

data class AO3AuthorSeriesPage(
    val series: List<AO3AuthorSeriesSummary>,
    val currentPage: Int,
    val totalPages: Int
)

data class AO3AuthorBookmark(
    val id: Long,
    val work: AO3WorkSummary?,
    val notes: String,
    val tags: List<String>,
    val isRecommendation: Boolean,
    val isPrivate: Boolean,
    val date: String
)

data class AO3AuthorBookmarksPage(
    val bookmarks: List<AO3AuthorBookmark>,
    val currentPage: Int,
    val totalPages: Int
)

/** Registered identities, never displayed pseuds; shared by series blurbs and show pages. */
internal fun ao3CreatorUsernames(addresses: Iterable<String>): List<String> = addresses.mapNotNull { address ->
    if (!io.github.cidy02.kudos.network.ao3.AO3RedirectCookieRelay.isTrustedUrl(address)) null
    else address.toHttpUrlOrNull()?.pathSegments?.takeIf { it.firstOrNull() == "users" }?.getOrNull(1)
}.distinct()
