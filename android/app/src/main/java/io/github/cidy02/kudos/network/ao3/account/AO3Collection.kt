package io.github.cidy02.kudos.network.ao3.account

enum class AO3ChallengeKind(val displayName: String) {
    GiftExchange("Gift Exchange"),
    PromptMeme("Prompt Meme")
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
    val worksCount: Int = 0,
    val bookmarksCount: Int = 0,
    val challengeKind: AO3ChallengeKind? = null,
    val updatedAtText: String = "",
    val iconURL: String? = null
)
