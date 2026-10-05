package io.github.cidy02.kudos.network.ao3.account

/** The named scopes of the subscriptions index; Works keeps its existing parser. */
enum class AO3NamedSubscriptionsScope(val parameter: String, val title: String) {
    Series("series", "Series"),
    Users("users", "Authors");

    val emptyTitle: String
        get() = if (this == Series) "No series subscriptions" else "No author subscriptions"
    val emptyMessage: String
        get() = "$title you subscribe to on AO3 show up here."

    fun subtitle(count: Int, page: Int, totalPages: Int): String {
        val countText = if (this == Series) "$count series" else if (count == 1) "1 author" else "$count authors"
        return countText + if (totalPages > 1) " · page $page of $totalPages" else ""
    }
}

data class AO3NamedSubscription(
    val path: String,
    val name: String,
    val creators: List<AO3AuthorIdentity> = emptyList()
)

data class AO3NamedSubscriptionsPage(
    val rows: List<AO3NamedSubscription>,
    val currentPage: Int,
    val totalPages: Int
)
