package io.github.cidy02.kudos.network.ao3.account

import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3OverloadDetector
import io.github.cidy02.kudos.network.ao3.AO3RedirectCookieRelay
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.jsoup.Jsoup

/** iOS AO3CollectionParam and collectionFormParameters; deliberately not a generic HTML serializer. */
object AO3CollectionFields {
    const val NAME = "collection[name]"
    const val TITLE = "collection[title]"
    const val EMAIL = "collection[email]"
    const val HEADER_URL = "collection[header_image_url]"
    const val HEADER_ALT = "collection[header_image_alt]"
    const val DESCRIPTION = "collection[description]"
    const val PARENT = "collection[parent_name]"
    const val ICON_ALT = "collection[icon_alt_text]"
    const val ICON_COMMENT = "collection[icon_comment_text]"
    const val CHALLENGE = "challenge_type"
    const val OWNERS = "owner_pseuds[]"
    fun preference(name: String) = "collection[collection_preference_attributes][$name]"
    fun profile(name: String) = "collection[collection_profile_attributes][$name]"
    val textParameters = listOf(NAME, TITLE, EMAIL, HEADER_URL, DESCRIPTION, PARENT, ICON_ALT,
        ICON_COMMENT, "collection[tag_string]")
    val booleanParameters = listOf("collection[multifandom]", "collection[delete_icon]") +
        listOf("moderated", "closed", "unrevealed", "anonymous", "show_random").map(::preference)
    val profileParameters = listOf("intro", "faq", "rules", "gift_notification", "assignment_notification").map(::profile)
    val multilineParameters = profileParameters + DESCRIPTION
    const val INVALID_NAME = "That URL name isn't valid on AO3. Use letters, numbers, and underscores, and don't start or end with an underscore."
    const val UNCONFIRMED = "AO3 replied but didn't confirm the change went through. Check on AO3 before trying again."
    const val DELETE_MESSAGE = "This removes the collection, its challenge settings and any gift assignments from AO3. " +
        "The works stay with their creators. Unrevealed works become visible, and anonymous works show their creators. " +
        "Type the collection name to confirm."
}

object AO3CollectionFormUrls {
    fun show(name: String): String = AO3Constants.BASE_URL.toHttpUrl().newBuilder()
        .addPathSegment("collections").addPathSegment(name).build().toString()
    fun form(slug: String?) = if (slug == null) "${AO3Constants.BASE_URL}/collections/new" else "${show(slug)}/edit"
    fun confirmDelete(slug: String) = "${show(slug)}/confirm_delete"
}

enum class AO3CollectionNameAvailability { Available, Taken, Invalid, Unknown }

fun collectionNameFormatIsValid(name: String) = Regex("^[A-Za-z0-9]\\w*[A-Za-z0-9]$").matches(name)
val reservedCollectionNames = setOf("new", "edit", "list_challenges", "list_ge_challenges", "list_pm_challenges")

data class AO3CollectionForm(
    val slug: String?,
    val actionUrl: String,
    val csrfToken: String,
    val methodOverride: String?,
    val values: Map<String, String>,
    val ownerIds: List<String>,
    val challengeOptions: List<Pair<String, String>>,
    val emailNotifyIsPresent: Boolean,
    val allowsDelete: Boolean,
    val fieldErrors: Map<String, String> = emptyMap(),
    val generalErrors: List<String> = emptyList()
) {
    operator fun get(key: String) = values[key].orEmpty()
    fun changed(key: String, value: String) = copy(values = values + (key to value))
    val deletionName: String get() = this[AO3CollectionFields.TITLE].trim().ifEmpty {
        this[AO3CollectionFields.NAME].ifEmpty { "collection" }
    }
    fun confirmsDeletion(typed: String) = typed.trim().isNotEmpty() && typed.trim() == deletionName.trim()

    fun parameters(): List<Pair<String, String>> = buildList {
        methodOverride?.takeIf { it.isNotEmpty() }?.let { add("_method" to it) }
        add("authenticity_token" to csrfToken)
        AO3CollectionFields.textParameters.forEach { key ->
            add(key to if (key == AO3CollectionFields.NAME && slug != null) slug else this@AO3CollectionForm[key])
        }
        AO3CollectionFields.booleanParameters.forEach { add(it to if (this@AO3CollectionForm[it] == "1") "1" else "0") }
        AO3CollectionFields.profileParameters.forEach { add(it to this@AO3CollectionForm[it]) }
        for (key in listOf(AO3CollectionFields.preference("id"), AO3CollectionFields.profile("id"))) {
            this@AO3CollectionForm[key].takeIf { it.isNotEmpty() }?.let { add(key to it) }
        }
        if (challengeOptions.isNotEmpty()) add(AO3CollectionFields.CHALLENGE to this@AO3CollectionForm[AO3CollectionFields.CHALLENGE])
        if (emailNotifyIsPresent) add(AO3CollectionFields.preference("email_notify") to
            if (this@AO3CollectionForm[AO3CollectionFields.preference("email_notify")] == "1") "1" else "0")
        ownerIds.forEach { add(AO3CollectionFields.OWNERS to it) }
        // iOS omits header_image_alt and arbitrary hidden fields, and still sends the locked name.
    }
}

sealed interface AO3CollectionSaveOutcome {
    data class Saved(val form: AO3CollectionForm, val message: String) : AO3CollectionSaveOutcome
    data class Invalid(val form: AO3CollectionForm) : AO3CollectionSaveOutcome
}

class AO3CollectionFormParser {
    fun parse(html: String, slug: String?): AO3CollectionForm {
        require(!AO3OverloadDetector.isOverloadPage(html)) { "AO3 is busy. Try again shortly." }
        val doc = Jsoup.parse(html, AO3CollectionFormUrls.form(slug))
        require(doc.selectFirst("form#new_user, form[action='/users/login']") == null) { "Log in to AO3 first." }
        val form = doc.selectFirst("form.collection, form[class*='collection'], form[action*='/collections']")
            ?: doc.selectFirst("#main form") ?: error("Couldn't read AO3's collection form.")
        val action = if (form.attr("action").isBlank()) "${AO3Constants.BASE_URL}/collections" else form.attr("abs:action")
        require(AO3RedirectCookieRelay.isTrustedUrl(action)) { "AO3 returned an untrusted form address." }
        val token = doc.selectFirst("meta[name=csrf-token]")?.attr("content")?.takeIf { it.isNotBlank() }
            ?: form.selectFirst("input[name=authenticity_token]")?.attr("value").orEmpty()
        require(token.isNotEmpty()) { "Couldn't prepare the request. Try again, or open the collection on AO3." }
        val controls = form.select("input, select, textarea")
        val keys = AO3CollectionFields.textParameters + AO3CollectionFields.booleanParameters +
            AO3CollectionFields.profileParameters + listOf(AO3CollectionFields.HEADER_ALT,
            AO3CollectionFields.preference("email_notify"), AO3CollectionFields.preference("id"),
            AO3CollectionFields.profile("id"), AO3CollectionFields.CHALLENGE)
        val booleans = AO3CollectionFields.booleanParameters + AO3CollectionFields.preference("email_notify")
        val values = keys.associateWith { key ->
            val matches = controls.filter { it.attr("name") == key }
            when {
                key in booleans -> if (matches.any { it.attr("type") == "checkbox" && it.hasAttr("checked") }) "1" else "0"
                key in AO3CollectionFields.multilineParameters -> matches.firstOrNull { it.tagName() == "textarea" }?.text()?.trim().orEmpty()
                key == AO3CollectionFields.CHALLENGE -> matches.firstOrNull { it.tagName() == "select" }?.let {
                    (it.selectFirst("option[selected]") ?: it.selectFirst("option"))?.attr("value")
                }.orEmpty()
                else -> matches.firstOrNull { it.tagName() == "input" }?.attr("value")?.trim().orEmpty()
            }
        }
        val owners = controls.filter { it.attr("name") == AO3CollectionFields.OWNERS }.flatMap { control ->
            if (control.tagName() == "select") control.select("option[selected]").map { it.attr("value").trim() }
            else if (control.tagName() == "input") listOf(control.attr("value").trim()) else emptyList()
        }.filter { it.isNotEmpty() }
        val options = controls.firstOrNull { it.tagName() == "select" && it.attr("name") == AO3CollectionFields.CHALLENGE }
            ?.select("option")?.map { it.attr("value") to it.text().trim().ifEmpty { it.attr("value") } }.orEmpty()
        val general = doc.select("#error ul li, .error ul li, #errorExplanation li, div.error ul li")
            .map { it.text().trim() }.filter { it.isNotEmpty() }
        val fieldErrors = doc.select(".field_with_errors input, .field_with_errors textarea, .fieldWithErrors input")
            .filter { it.attr("name").isNotEmpty() }.associate { it.attr("name") to (general.firstOrNull() ?: "Invalid") }
        return AO3CollectionForm(slug, action, token,
            form.selectFirst("input[name=_method]")?.attr("value")?.takeIf { it.isNotBlank() }, values, owners, options,
            controls.any { it.attr("name") == AO3CollectionFields.preference("email_notify") },
            doc.selectFirst("a[href*='confirm_delete'], form.simple.destroy") != null, fieldErrors, general)
    }

    fun destroyToken(html: String): String? = Jsoup.parse(html).selectFirst("form.simple.destroy")
        ?.selectFirst("input[name=authenticity_token]")?.attr("value")?.takeIf { it.isNotEmpty() }
}
