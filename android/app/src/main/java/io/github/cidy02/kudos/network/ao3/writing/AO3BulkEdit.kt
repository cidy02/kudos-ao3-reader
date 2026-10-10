package io.github.cidy02.kudos.network.ao3.writing

import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3RedirectCookieRelay
import org.jsoup.Jsoup

object AO3BulkWorkUrls {
    fun page(username: String, action: String): String = AO3Constants.baseHttpUrl.newBuilder()
        .addPathSegment("users").addPathSegment(username).addPathSegment("works").addPathSegment(action).build().toString()
}

data class AO3BulkEditForm(
    val workIDs: List<Long>, val titles: List<String>,
    val options: Map<String, List<AO3FormOption>>
)

/** Lists are per-work diffs; only uniform values belong in update_multiple. */
data class AO3BulkEditChanges(
    val workIDs: List<Long>,
    val added: Map<String, List<String>> = emptyMap(),
    val removed: Map<String, List<String>> = emptyMap(),
    val scalars: Map<String, String> = emptyMap(),
    val collectionsToAdd: List<String> = emptyList(),
    val collectionsToRemove: List<String> = emptyList(),
    val pseudsToAdd: String = "", val removesSelf: Boolean = false
) {
    val hasTags get() = added.values.any { it.isNotEmpty() } || removed.values.any { it.isNotEmpty() }
    val hasUniform get() = scalars.values.any { it.isNotEmpty() } || collectionsToAdd.isNotEmpty() ||
        collectionsToRemove.isNotEmpty() || pseudsToAdd.isNotEmpty() || removesSelf

    fun parameters(token: String): List<Pair<String, String>> = buildList {
        add("authenticity_token" to token); add("_method" to "patch")
        workIDs.forEach { add("work_ids[]" to it.toString()) }
        fun scalar(name: String) { scalars[name]?.takeIf(String::isNotEmpty)?.let { add(name to it) } }
        scalar(AO3WorkFormField.rating); scalar(AO3WorkFormField.languageID)
        joinWorkList(collectionsToAdd).takeIf(String::isNotEmpty)?.let { add("work[collections_to_add]" to it) }
        collectionsToRemove.forEach { add("work[collections_to_remove][]" to it) }
        scalar(AO3WorkFormField.restricted); scalar(AO3WorkFormField.moderatedCommenting)
        scalar(AO3WorkFormField.commentPermissions); scalar(AO3WorkFormField.workSkinID)
        if (pseudsToAdd.isNotEmpty()) add("work[pseuds_to_add]" to pseudsToAdd)
        if (removesSelf) add("remove_me" to "1")
    }

    fun applying(form: AO3WorkForm): AO3WorkForm {
        fun merge(name: String, current: List<String>): List<String> {
            val result = mutableListOf<String>()
            for (nameToAdd in current + added[name].orEmpty()) {
                val clean = trimWritingTag(nameToAdd)
                if (clean.isNotEmpty() && removed[name].orEmpty().none { trimWritingTag(it).equals(clean, true) } &&
                    result.none { it.equals(clean, true) }) result.add(clean)
            }
            return result
        }
        return form.copy(rating = scalars[AO3WorkFormField.rating]?.takeIf(String::isNotEmpty) ?: form.rating,
            warnings = merge(AO3WorkFormField.warnings, form.warnings), categories = merge(AO3WorkFormField.categories, form.categories),
            fandoms = merge(AO3WorkFormField.fandoms, form.fandoms), relationships = merge(AO3WorkFormField.relationships, form.relationships),
            characters = merge(AO3WorkFormField.characters, form.characters), additionalTags = merge(AO3WorkFormField.additionalTags, form.additionalTags))
    }
}

internal object AO3BulkEditParser {
    fun parse(html: String, url: String, expectedIDs: List<Long>): AO3BulkEditForm {
        val doc = Jsoup.parse(html, url)
        val form = doc.selectFirst("form.verbose.post, form[action*=update_multiple], form[action*=edit_multiple]")
            ?: error("Couldn't read AO3's work form.")
        require(AO3RedirectCookieRelay.isTrustedUrl(form.attr("abs:action")))
        require(doc.selectFirst("meta[name=csrf-token]")?.attr("content")?.let(::trimWritingTag)?.isNotEmpty() == true ||
            form.select("input[name]").any { it.attr("name") == "authenticity_token" && it.attr("value").isNotEmpty() })
        val controls = form.select("[name]")
        fun named(name: String) = controls.filter { it.attr("name") == name }
        val ids = named("work_ids[]").mapNotNull { it.attr("value").toLongOrNull() }
        require(ids.size == expectedIDs.size && ids.toSet() == expectedIDs.toSet()) { "Couldn't read AO3's work form." }
        val fields = listOf(AO3WorkFormField.rating, AO3WorkFormField.warnings, AO3WorkFormField.categories,
            AO3WorkFormField.languageID, "work[collections_to_remove][]", AO3WorkFormField.commentPermissions,
            AO3WorkFormField.restricted, AO3WorkFormField.moderatedCommenting)
        val options = fields.associateWith { name ->
            named(name).flatMap { control ->
                if (control.tagName() == "select") control.select("option").map { AO3FormOption(it.attr("value"), it.text()) }
                else if (control.attr("type") in setOf("checkbox", "radio")) {
                    val label = doc.select("label").firstOrNull { it.attr("for") == control.id() && control.id().isNotEmpty() }
                        ?: control.parents().firstOrNull { it.tagName() == "label" }
                    listOf(AO3FormOption(control.attr("value"), label?.text()?.takeIf(String::isNotBlank) ?: control.attr("value")))
                } else emptyList()
            }
        }
        return AO3BulkEditForm(ids, doc.select("dl.work.index > dt > a:first-of-type").map { trimWritingTag(it.text()) }
            .filter(String::isNotEmpty), options)
    }
}
