package io.github.cidy02.kudos.network.ao3.author

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
    val actions: List<AO3AuthorWebAction>
)

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
    val url: String
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
