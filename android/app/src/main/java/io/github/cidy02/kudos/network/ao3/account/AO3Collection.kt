package io.github.cidy02.kudos.network.ao3.account

/**
 * One of the signed-in user's AO3 collections (remote, read-only).
 *
 * [name] is the URL slug (`/collections/<name>`); [title] is the display name;
 * [byline] is the maintainers line when shown.
 */
data class AO3Collection(
    val name: String,
    val title: String,
    val byline: String = ""
)
