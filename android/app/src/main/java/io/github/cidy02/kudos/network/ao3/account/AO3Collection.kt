package io.github.cidy02.kudos.network.ao3.account

/** [fieldPrefix] is the kind's segment in AO3's addresses and the prefix of its form's field names. */
enum class AO3ChallengeKind(val displayName: String, val fieldPrefix: String) {
    GiftExchange("Gift Exchange", "gift_exchange"),
    PromptMeme("Prompt Meme", "prompt_meme")
}

data class AO3AuthorIdentity(
    val displayName: String,
    val href: String
)

/**
 * One of the signed-in user's AO3 collections (remote, read-only).
 *
 * [name] is the URL slug (`/collections/<name>`); [title] is the display name;
 * [byline] is the maintainers line when shown.
 * A null count is unknown, distinct from a parsed zero (iOS filter parity).
 */
data class AO3Collection(
    val name: String,
    val title: String,
    val summary: String = "",
    val byline: String = "",
    val maintainerNames: List<String> = emptyList(),
    val maintainerIdentities: List<AO3AuthorIdentity> = emptyList(),
    val viewerIsOwner: Boolean = false,
    val viewerIsMember: Boolean = false,
    val isUnrevealed: Boolean = false,
    val isAnonymous: Boolean = false,
    val isModerated: Boolean = false,
    val isClosed: Boolean = false,
    val worksCount: Int? = null,
    val bookmarksCount: Int? = null,
    val challengeKind: AO3ChallengeKind? = null,
    val updatedAtText: String = "",
    val iconURL: String? = null
)

/** The rows and pagination from one account collections-index response. */
data class AO3CollectionsIndexPage(
    val collections: List<AO3Collection>,
    val currentPage: Int = 1,
    val totalPages: Int = 1
)
