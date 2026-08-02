package io.github.cidy02.kudos.network.ao3.writes

enum class AO3WriteActionKind {
    Kudos,
    Subscribe,
    Unsubscribe,
    MarkForLater,
    Bookmark,
    Comment
}

data class AO3WriteOutcome(
    val kind: AO3WriteActionKind,
    val message: String
)

data class AO3BookmarkInput(
    val notes: String = "",
    val tags: String = "",
    val isPrivate: Boolean = false,
    val isRecommendation: Boolean = false
)

data class AO3SubscriptionState(
    val isSubscribed: Boolean,
    val unsubscribePath: String?
)

/**
 * Bookmark form state scraped from a work page (or equivalent HTML).
 *
 * When [exists] is true, AO3 rendered the edit form (`_method=put` + action
 * pointing at `/bookmarks/{id}`) with [input] pre-filled from the existing
 * bookmark. When false, the create form (or no form) is present and [input]
 * is blank defaults.
 */
data class AO3BookmarkState(
    val exists: Boolean,
    val editPath: String?,
    val input: AO3BookmarkInput = AO3BookmarkInput()
)
