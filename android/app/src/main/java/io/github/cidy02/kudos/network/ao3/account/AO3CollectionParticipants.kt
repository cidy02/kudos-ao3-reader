package io.github.cidy02.kudos.network.ao3.account

enum class AO3CollectionParticipantRole(val title: String) {
    None("None"), Owner("Owner"), Moderator("Moderator"), Member("Member"), Invited("Invited")
}

object AO3CollectionParticipantsUrls {
    fun page(slug: String) = "${AO3CollectionFormUrls.show(slug)}/participants"
    fun add(slug: String) = "${page(slug)}/add"
    fun participant(slug: String, id: Int) = "${page(slug)}/$id"
}
