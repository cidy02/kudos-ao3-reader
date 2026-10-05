package io.github.cidy02.kudos.network.ao3.account

import io.github.cidy02.kudos.network.ao3.AO3OverloadDetector
import org.jsoup.Jsoup

data class AO3CollectionParticipant(val id: Int, val pseud: String, val role: String) {
    val isMembershipRequest get() = role.equals("None", true)
    val isMaintainer get() = role.equals("Owner", true) || role.equals("Moderator", true)
}

data class AO3CollectionModeration(
    val queue: AO3CollectionItemsPage,
    val requests: List<AO3CollectionParticipant>,
    val maintainerCount: Int,
    val unrevealed: Boolean,
    val anonymous: Boolean
)

object AO3CollectionModerationUrls {
    fun participants(slug: String) = "${AO3CollectionFormUrls.show(slug)}/participants"
    fun participant(slug: String, id: Int) = "${participants(slug)}/$id"
}

/** Same role/id/byline selectors as iOS parseCollectionParticipants. No roster persistence. */
class AO3CollectionParticipantsParser {
    fun parse(html: String): List<AO3CollectionParticipant> {
        require(!AO3OverloadDetector.isOverloadPage(html)) { "AO3 is busy. Try again shortly." }
        val doc = Jsoup.parse(html)
        require(doc.selectFirst("form#new_user, form[action='/users/login']") == null) { "Log in to AO3 first." }
        return doc.select("ul.participant.index li, li[id^=participant_]").mapNotNull { li ->
            val id = li.id().removePrefix("participant_").toIntOrNull()
                ?: li.selectFirst("form")?.attr("action")?.let {
                    Regex("/participants/(\\d+)(?:[/?#]|$)").find(it)?.groupValues?.get(1)?.toIntOrNull()
                } ?: return@mapNotNull null
            if (id == 0) return@mapNotNull null
            val selects = li.select("select")
            val select = selects.firstOrNull { it.attr("name") == "collection_participant[participant_role]" }
                ?: selects.firstOrNull { it.attr("name").endsWith("[participant_role]") }
            val role = (select?.selectFirst("option[selected]") ?: select?.selectFirst("option"))
                ?.attr("value")?.trim().orEmpty()
            AO3CollectionParticipant(id, li.selectFirst("span.byline a, a[href*='/users/']")?.text()?.trim().orEmpty(),
                role.takeIf { it.lowercase() in setOf("none", "owner", "moderator", "member", "invited") } ?: "Member")
        }
    }
}
