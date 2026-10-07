package io.github.cidy02.kudos.network.ao3.account

import io.github.cidy02.kudos.network.ao3.AO3OverloadDetector
import org.jsoup.Jsoup

enum class AO3TagSetField(val wireName: String, val rowLabel: String, val nominationLabel: String, val editorLabel: String) {
    Fandom("fandom", "Fandoms", "Fandom", "Fandom tags to add"),
    Character("character", "Characters", "Character", "Character tags to add"),
    Relationship("relationship", "Relationships", "Relationship", "Relationship tags to add"),
    Freeform("freeform", "Additional tags", "Additional tag", "Additional tags to add")
}

enum class AO3TagNominationState { Unreviewed, Approved, Rejected }

data class AO3TagNomination(
    val id: Int,
    val tagName: String,
    val field: AO3TagSetField,
    val state: AO3TagNominationState,
    val parentTagName: String = ""
)

/** Remote read values only; not a persisted record or a writable form. */
data class AO3TagSetSnapshot(
    val id: Int,
    val title: String,
    val isVisible: Boolean,
    val isNominated: Boolean,
    val counts: Map<AO3TagSetField, Int>,
    val nominationLimits: Map<AO3TagSetField, Int>,
    val tagnames: Map<AO3TagSetField, String>,
    val reviewQueue: List<AO3TagNomination>
) {
    val totalTagCount get() = counts.values.sum()
}

object AO3TagSetUrls {
    fun page(id: Int) = ChallengeSettingsDestinations.tagSetView(id)
    fun edit(id: Int) = "${page(id)}/edit"
    fun nominations(id: Int) = "${page(id)}/nominations"
    fun associations(id: Int) = "${page(id)}/associations"
}

/** Mirrors iOS parseTagSet / parseTagSetNominations, including their best-effort defaults. */
class AO3TagSetParser {
    fun parse(html: String, id: Int): AO3TagSetSnapshot {
        val doc = document(html)
        val title = doc.selectFirst("h2.heading, h2")?.text().orEmpty()
            .replace(" | Archive of Our Own", "").trim()
        val form = doc.selectFirst("form[action*='/tag_sets']")
        require(title.isNotEmpty() || form != null) { "Unrecognized tag set page" }
        fun input(name: String) = form?.select("input")?.firstOrNull { it.attr("name") == name }?.attr("value").orEmpty().trim()
        fun checked(name: String) = form?.select("input[type=checkbox]")?.firstOrNull { it.attr("name") == name }?.hasAttr("checked") == true
        fun count(type: String): Int {
            val heading = doc.select("h3.heading, h4.heading").firstOrNull { it.text().contains(type, ignoreCase = true) }
            return heading?.text()?.filter(Char::isDigit)?.toIntOrNull()
                ?: doc.select("ul.$type li, div.$type li").size
        }
        return AO3TagSetSnapshot(
            id, title.ifEmpty { "Tag Set $id" },
            form == null || checked("owned_tag_set[visible]"),
            form != null && checked("owned_tag_set[nominated]"),
            AO3TagSetField.entries.associateWith {
                if (it == AO3TagSetField.Freeform) count("freeform") + count("additional") else count(it.wireName)
            },
            AO3TagSetField.entries.associateWith {
                input("owned_tag_set[${it.wireName}_nomination_limit]").filter(Char::isDigit).toIntOrNull() ?: 0
            },
            AO3TagSetField.entries.associateWith {
                val name = "owned_tag_set[tag_set_attributes][${it.wireName}_tagnames_to_add]"
                val area = form?.select("textarea")?.firstOrNull { it.attr("name") == name }?.text().orEmpty().trim()
                area.ifEmpty { input(name) }
            },
            parseNominations(html)
        )
    }

    fun parseNominations(html: String): List<AO3TagNomination> {
        val doc = document(html)
        val result = mutableListOf<AO3TagNomination>()
        doc.select("li.nomination, tr.nomination, div.nomination").forEach { row ->
            val name = (row.selectFirst(".tag, td.tag, a.tag")?.text() ?: row.text()).trim()
            if (name.isNotEmpty()) {
                val text = row.text().lowercase()
                val field = when {
                    "character" in text -> AO3TagSetField.Character
                    "relationship" in text -> AO3TagSetField.Relationship
                    "freeform" in text || "additional" in text -> AO3TagSetField.Freeform
                    else -> AO3TagSetField.Fandom
                }
                val state = when {
                    "reject" in text -> AO3TagNominationState.Rejected
                    "approv" in text -> AO3TagNominationState.Approved
                    else -> AO3TagNominationState.Unreviewed
                }
                // iOS leaves parentTagName empty for both markup forms, even with a fandom in HTML.
                result += AO3TagNomination(result.size + 1, name, field, state)
            }
        }
        doc.select("input[type=checkbox], input[type=radio]").forEach { control ->
            val parts = control.attr("name").split('_', limit = 3)
            if (parts.size != 3 || parts[1] !in setOf("approve", "reject", "synonym", "change")) return@forEach
            val field = AO3TagSetField.entries.firstOrNull { it.wireName == parts[0] } ?: return@forEach
            val name = parts[2].replace("#LBRACKET", "[").replace("#RBRACKET", "]")
            if (result.none { it.tagName == name && it.field == field }) {
                val state = when (parts[1]) {
                    "reject" -> AO3TagNominationState.Rejected
                    "approve" -> AO3TagNominationState.Approved
                    else -> AO3TagNominationState.Unreviewed
                }
                result += AO3TagNomination(name.hashCode(), name, field, state)
            }
        }
        return result
    }

    private fun document(html: String): org.jsoup.nodes.Document {
        require(!AO3OverloadDetector.isOverloadPage(html)) { "AO3 is busy. Try again shortly." }
        val doc = Jsoup.parse(html)
        require(doc.selectFirst("form#new_user, form[action='/users/login']") == null) { "Log in to AO3 first." }
        return doc
    }
}
