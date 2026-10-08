package io.github.cidy02.kudos.network.ao3.account

import io.github.cidy02.kudos.network.ao3.AO3RedirectCookieRelay
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteFormParser
import io.github.cidy02.kudos.network.ao3.writing.AO3ServedControl
import io.github.cidy02.kudos.network.ao3.writing.AO3WorkFormParser
import org.jsoup.Jsoup

enum class SignUpPromptKind(val wire: String, val label: String) {
    Request("requests", "Request"), Offer("offers", "Offer")
}

enum class SignUpTagType(val wire: String, val plural: String, val label: String, val placeholder: String) {
    Fandom("fandom", "fandoms", "Fandoms", "Good Omens, Supernatural"),
    Character("character", "characters", "Characters", "Aziraphale, Crowley"),
    Relationship("relationship", "relationships", "Relationships", "Aziraphale/Crowley"),
    Freeform("freeform", "additional tags", "Additional tags", "slow burn, domestic")
}

data class SignUpLimits(val requests: IntRange, val offers: IntRange)
data class SignUpPrompt(
    val id: Int, val kind: SignUpPromptKind,
    val title: String = "", val description: String = "", val url: String = "",
    val anonymous: Boolean = false, val destroy: Boolean = false,
    val tags: Map<SignUpTagType, List<String>> = emptyMap(),
    val any: Set<SignUpTagType> = emptySet(),
    /** Served index for remapping unmodeled nested controls when iOS enumerates the array. */
    val servedIndex: Int? = null
) {
    val errorKey get() = "${if (kind == SignUpPromptKind.Request) "request" else "offer"}:$id"
}

/** One opening's remote form. No Room or backup serialization. */
data class AO3ChallengeSignUpForm(
    val slug: String, val actionUrl: String, val token: String, val method: String?,
    val signUpID: Int?, val pseudID: String,
    val requests: List<SignUpPrompt>, val offers: List<SignUpPrompt>,
    val limits: SignUpLimits?,
    val requestTagLimits: Map<SignUpTagType, IntRange>?,
    val offerTagLimits: Map<SignUpTagType, IntRange>?,
    val servedControls: List<AO3ServedControl>,
    val fieldErrors: Map<String, String> = emptyMap(), val generalErrors: List<String> = emptyList()
) {
    val takesOffers get() = (limits?.offers?.last ?: 1) > 0
    val isValid get() = fieldErrors.isEmpty() && generalErrors.isEmpty()
    val nextDraftID get() = minOf(0, (requests + offers).minOfOrNull { it.id } ?: 0) - 1
    fun live(kind: SignUpPromptKind) = (if (kind == SignUpPromptKind.Request) requests else offers).filterNot { it.destroy }
    fun update(prompt: SignUpPrompt): AO3ChallengeSignUpForm = if (prompt.kind == SignUpPromptKind.Request)
        copy(requests = requests.map { if (it.id == prompt.id) prompt else it })
    else copy(offers = offers.map { if (it.id == prompt.id) prompt else it })

    fun withMinimumPrompts(): AO3ChallengeSignUpForm {
        var form = this
        if (form.requests.isEmpty()) form = form.copy(requests = listOf(SignUpPrompt(form.nextDraftID, SignUpPromptKind.Request)))
        if (form.offers.isEmpty() && form.takesOffers) form = form.copy(offers = listOf(SignUpPrompt(form.nextDraftID, SignUpPromptKind.Offer)))
        return form
    }

    /** Exact iOS validated() words, order, nil-vs-absent limits and Any semantics. */
    fun validated(): AO3ChallengeSignUpForm {
        val errors = linkedMapOf<String, String>()
        for (kind in SignUpPromptKind.entries) {
            val live = live(kind)
            val range = if (kind == SignUpPromptKind.Request) limits?.requests else limits?.offers
            if (range != null) {
                if (live.size < range.first) errors[kind.wire] = "This challenge requires at least ${range.first} ${kind.label.lowercase()}(s)."
                if (live.size > range.last) errors[kind.wire] = "This challenge allows at most ${range.last} ${kind.label.lowercase()}(s)."
            }
            val tags = if (kind == SignUpPromptKind.Request) requestTagLimits else offerTagLimits
            if (tags != null) live.forEachIndexed { index, prompt ->
                val problems = SignUpTagType.entries.mapNotNull { type ->
                    val count = prompt.tags[type].orEmpty().size
                    val allowed = tags[type] ?: 0..0
                    when {
                        type in prompt.any -> if (count > 0) "Choose ${type.plural} or “Any”, not both." else null
                        count in allowed -> null
                        allowed.last == 0 -> "This challenge takes no ${type.plural}."
                        else -> {
                            val wanted = if (allowed.first == allowed.last) "exactly ${allowed.first}" else "${allowed.first} to ${allowed.last}"
                            "Choose $wanted ${type.plural} (you have $count)."
                        }
                    }
                }
                if (problems.isNotEmpty()) errors[prompt.errorKey] = "${kind.label} ${index + 1}: ${problems.joinToString(" ")}"
            }
        }
        return copy(fieldErrors = errors, generalErrors = emptyList())
    }

    /** iOS challengeSignUpParameters + nestedPromptParameters, without hidden-field replay. */
    fun iosParameters(): List<Pair<String, String>> = buildList {
        add("authenticity_token" to token)
        method?.takeIf(String::isNotEmpty)?.let { add("_method" to it) }
        if (pseudID.isNotEmpty()) add("challenge_signup[pseud_id]" to pseudID)
        for ((kind, prompts) in listOf(SignUpPromptKind.Request to requests, SignUpPromptKind.Offer to offers)) {
            prompts.forEachIndexed { index, prompt ->
                val base = signUpPromptPrefix(kind, index)
                if (prompt.id > 0) add("$base[id]" to prompt.id.toString())
                add("$base[title]" to prompt.title)
                add("$base[description]" to prompt.description)
                add("$base[url]" to prompt.url)
                add("$base[anonymous]" to if (prompt.anonymous) "1" else "0")
                SignUpTagType.entries.forEach { add("$base[any_${it.wire}]" to if (it in prompt.any) "1" else "0") }
                add("$base[_destroy]" to if (prompt.destroy) "1" else "0")
                SignUpTagType.entries.forEach { add("$base[tag_set_attributes][${it.wire}_tagnames]" to prompt.tags[it].orEmpty().joinToString(",")) }
            }
        }
    }

    fun carriedParameters(): List<Pair<String, String>> {
        val explicit = iosParameters().map { it.first }.toSet()
        val remap = (requests + offers).filter { it.servedIndex != null }.associate { prompt ->
            signUpPromptPrefix(prompt.kind, prompt.servedIndex ?: -1) to signUpPromptPrefix(prompt.kind,
                (if (prompt.kind == SignUpPromptKind.Request) requests else offers).indexOf(prompt))
        }
        // Native Submit is the first enabled submitter, as a browser's implicit form submit.
        // Keep its served value; other submitters, including a same-name Cancel, are not successful.
        val submitter = servedControls.indexOfFirst { !it.disabled &&
            (it.tag == "button" && it.type == "submit" || it.tag == "input" && it.type == "submit") }
        return servedControls.flatMapIndexed { index, control ->
            val prefix = remap.keys.firstOrNull { control.name.startsWith("$it[") }
            val name = if (prefix == null) control.name else remap.getValue(prefix) + control.name.removePrefix(prefix)
            val isSubmit = control.tag == "button" || control.tag == "input" && control.type == "submit"
            if (name in explicit || isSubmit && index != submitter) emptyList()
            else control.successfulValues(if (index == submitter) control.name else null).map { name to it }
        }
    }
    fun parameters() = iosParameters() + carriedParameters()
}

internal fun signUpPromptPrefix(kind: SignUpPromptKind, index: Int) = "challenge_signup[${kind.wire}_attributes][$index]"
internal fun splitSignUpTags(text: String) = text.split(',').map(String::trim).filter(String::isNotEmpty)

object AO3ChallengeSignUpUrls {
    fun form(slug: String, id: Int? = null) = if (id == null) "${AO3CollectionFormUrls.show(slug)}/signups/new"
        else "${AO3CollectionFormUrls.show(slug)}/signups/$id/edit"
}

class AO3ChallengeSignUpParser {
    fun parse(html: String, slug: String): AO3ChallengeSignUpForm {
        val doc = Jsoup.parse(html, AO3ChallengeSignUpUrls.form(slug))
        val form = doc.selectFirst("form[action*='/signups']") ?: doc.selectFirst("#main form")
            ?: error("Couldn't read AO3's sign-up form.")
        val action = if (form.attr("action").isEmpty()) "${AO3CollectionFormUrls.show(slug)}/signups" else form.attr("abs:action")
        require(AO3RedirectCookieRelay.isTrustedUrl(action) && form.attr("method").equals("post", true) &&
            Regex("/collections/[^/]+/signups(?:/[0-9]+)?/?$").containsMatchIn(java.net.URI(action).path)) {
            "Couldn't read AO3's sign-up form."
        }
        fun input(name: String) = form.select("input").firstOrNull { it.attr("name") == name }?.attr("value").orEmpty().trim()
        fun checked(name: String) = form.select("input[type=checkbox]").firstOrNull { it.attr("name") == name }?.hasAttr("checked") == true
        fun prompts(kind: SignUpPromptKind): List<SignUpPrompt> {
            val prefix = "challenge_signup[${kind.wire}_attributes]"
            val indices = form.select("input, textarea, select").mapNotNull {
                Regex("^${Regex.escape(prefix)}\\[([0-9]+)]").find(it.attr("name"))?.groupValues?.get(1)?.toIntOrNull()
            }.distinct().sorted()
            return indices.map { index ->
                val base = signUpPromptPrefix(kind, index)
                SignUpPrompt(input("$base[id]").toIntOrNull() ?: -(index + 1), kind,
                    input("$base[title]"), form.select("textarea").firstOrNull { it.attr("name") == "$base[description]" }?.text().orEmpty().trim(),
                    input("$base[url]"), checked("$base[anonymous]"), checked("$base[_destroy]"),
                    SignUpTagType.entries.associateWith { splitSignUpTags(input("$base[tag_set_attributes][${it.wire}_tagnames]")) },
                    SignUpTagType.entries.filter { checked("$base[any_${it.wire}]") }.toSet(), index)
            }
        }
        fun tagLimits(kind: SignUpPromptKind): Map<SignUpTagType, IntRange>? {
            val labels = form.select("label[for^=challenge_signup_${kind.wire}_attributes_]")
            if (labels.isEmpty()) return null
            return SignUpTagType.entries.mapNotNull { type -> labels.firstOrNull {
                it.attr("for").endsWith("_tag_set_attributes_${type.wire}_tagnames")
            }?.let { countRange(it.text())?.let { range -> type to range } } }.toMap()
        }
        val ranges = linkedMapOf<SignUpPromptKind, IntRange>()
        for (heading in form.select("fieldset > h3.heading")) {
            val kind = SignUpPromptKind.entries.firstOrNull {
                heading.text().startsWith(it.wire.replaceFirstChar(Char::uppercase))
            } ?: continue
            val range = countRange(heading.text())
            if (range == null) ranges.remove(kind) else ranges[kind] = range
        }
        val token = AO3WriteFormParser().parseAuthenticityToken(html, metaOnly = true)
            ?: input("authenticity_token").takeIf(String::isNotEmpty) ?: error("Couldn't read AO3's sign-up form.")
        val pseud = input("challenge_signup[pseud_id]").ifEmpty {
            form.select("select").firstOrNull { it.attr("name") == "challenge_signup[pseud_id]" }
                ?.let { it.selectFirst("option[selected]") ?: it.selectFirst("option") }?.attr("value").orEmpty()
        }
        return AO3ChallengeSignUpForm(slug, action, token, input("_method").takeIf(String::isNotEmpty),
            Regex("/signups/([0-9]+)(?:/|$)").find(java.net.URI(action).path)?.groupValues?.get(1)?.toIntOrNull(), pseud,
            prompts(SignUpPromptKind.Request), prompts(SignUpPromptKind.Offer), ranges[SignUpPromptKind.Request]?.let {
                SignUpLimits(it, ranges[SignUpPromptKind.Offer] ?: 0..0)
            }, tagLimits(SignUpPromptKind.Request), tagLimits(SignUpPromptKind.Offer),
            AO3WorkFormParser().servedControls(doc, form),
            generalErrors = doc.select("#error ul li, .error ul li, #errorExplanation li").map { it.text().trim() }.filter(String::isNotEmpty))
    }

    private fun countRange(text: String): IntRange? {
        val match = Regex("\\((\\d+)(?:\\s*-\\s*(\\d+))?\\)").find(text) ?: return null
        val low = match.groupValues[1].toInt()
        return low..maxOf(low, match.groupValues[2].toIntOrNull() ?: low)
    }
}

sealed interface AO3SignUpSaveOutcome {
    data class Saved(val form: AO3ChallengeSignUpForm) : AO3SignUpSaveOutcome
    data class Invalid(val form: AO3ChallengeSignUpForm) : AO3SignUpSaveOutcome
}
