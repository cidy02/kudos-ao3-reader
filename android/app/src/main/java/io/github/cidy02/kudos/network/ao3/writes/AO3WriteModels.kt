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
