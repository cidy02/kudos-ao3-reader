package io.github.cidy02.kudos.network.ao3.account

data class AO3CollectionShow(
    val collection: AO3Collection,
    val headerImageUrl: String? = null,
    val introduction: String = "",
    val faq: String = "",
    val rules: String = "",
    val canJoin: Boolean = false,
    val canLeave: Boolean = false,
    val leaveParticipantId: Int? = null,
    val canPostWork: Boolean = false,
    val isMaintainer: Boolean = false,
    val dashboard: AO3CollectionDashboard = AO3CollectionDashboard()
) {
    val id: String get() = collection.name
}

data class AO3CollectionDashboard(
    val profileUrl: String? = null,
    val worksUrl: String? = null,
    val bookmarksUrl: String? = null,
    val peopleUrl: String? = null,
    val itemsUrl: String? = null,
    val participantsUrl: String? = null,
    val signUpsUrl: String? = null,
    val assignmentsUrl: String? = null,
    val promptsUrl: String? = null,
    val challengeSettingsUrl: String? = null,
    val postToCollectionUrl: String? = null
)

data class AO3CollectionPerson(
    val id: String,
    val identity: AO3AuthorIdentity,
    val workCount: Int? = null
)

data class AO3CollectionPeoplePage(
    val people: List<AO3CollectionPerson>,
    val currentPage: Int,
    val totalPages: Int
)
