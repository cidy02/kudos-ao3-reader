package io.github.cidy02.kudos.network.ao3.writing

import io.github.cidy02.kudos.network.ao3.AO3OverloadDetector
import io.github.cidy02.kudos.network.ao3.AO3RedirectCookieRelay
import io.github.cidy02.kudos.network.ao3.account.AO3UsernameParser
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

sealed class AO3WorkFormParseException(message: String) : Exception(message) {
    class LoginRequired : AO3WorkFormParseException("Log in to AO3 first.")
    class Overloaded : AO3WorkFormParseException("AO3 is busy. Try again shortly.")
    class InvalidForm(detail: String) : AO3WorkFormParseException(detail)
}

/** Parses only served HTML. Options and raw controls are never sourced from a second read. */
class AO3WorkFormParser {
    fun parse(html: String, pageUrl: String = AO3WorkFormUrls.newWork()): AO3WorkForm {
        val doc = Jsoup.parse(html, pageUrl)
        // A writer's textarea may itself contain the overload words. Inspect page chrome,
        // with form contents removed, rather than treating their writing as an interstitial.
        val chrome = doc.clone().apply { select("form#work-form, form.work.post, form[action*=/works]").remove() }
        if (AO3OverloadDetector.isOverloadPage(chrome.text())) throw AO3WorkFormParseException.Overloaded()
        if (doc.selectFirst("form#new_user, form[action='/users/login']") != null ||
            AO3UsernameParser().isLoginRequiredPage(html, pageUrl)
        ) throw AO3WorkFormParseException.LoginRequired()
        val element = doc.selectFirst("form#work-form, form.work.post, form[id=work-form]")
            ?: doc.selectFirst("form[action*=/works]")
            ?: invalid("Couldn't read AO3's work form.")
        val actionUrl = element.attr("abs:action").takeIf { element.attr("action").isNotEmpty() }
            ?: invalid("AO3 didn't give the work form an address.")
        val action = actionUrl.toHttpUrlOrNull() ?: invalid("AO3 returned an invalid work form address.")
        if (!AO3RedirectCookieRelay.isTrustedUrl(actionUrl) ||
            !Regex("^/works(?:/[0-9]+(?:/(?:edit_tags|update_tags))?)?/?$").matches(action.encodedPath) ||
            !element.attr("method").equals("post", ignoreCase = true)
        ) invalid("AO3 returned an unexpected work form address or method.")
        // The broad iOS fallback must not accept search or deletion forms as an editor.
        if (element.selectFirst("input[name='work[title]']") == null) invalid("AO3 didn't return a work editor.")

        val rawControls = doc.select("input, select, textarea, button").filter { control ->
            if (control.hasAttr("form")) element.id().isNotEmpty() && control.attr("form") == element.id()
            else control.parents().firstOrNull { it.tagName() == "form" } == element
        }.map(::snapshot)
        // A browser resolves malformed multiple-checked radios to the last checked
        // control in the group. Keep all served checked attributes independently.
        val lastCheckedRadio = rawControls.withIndex().filter {
            it.value.tag == "input" && it.value.type == "radio" && "checked" in it.value.attributes
        }.associate { it.value.name to it.index }
        val controls = rawControls.mapIndexed { index, control ->
            if (control.tag == "input" && control.type == "radio")
                control.copy(browserChecked = lastCheckedRadio[control.name] == index)
            else control
        }
        fun inputs(name: String) = controls.filter { it.tag == "input" && it.name == name }
        fun input(name: String): String? {
            val matches = inputs(name)
            return (matches.firstOrNull { it.type != "hidden" && it.type != "submit" } ?: matches.firstOrNull())
                ?.attributes?.get("value").orEmpty().takeIf { matches.isNotEmpty() }
        }
        fun textarea(name: String) = controls.firstOrNull { it.tag == "textarea" && it.name == name }?.text.orEmpty()
        fun select(name: String): List<AO3FormOption> = controls.firstOrNull { it.tag == "select" && it.name == name }
            ?.options?.map { AO3FormOption(it.attributes["value"].orEmpty(), it.text.trim(), "selected" in it.attributes) }.orEmpty()
        fun selected(name: String) = select(name).lastOrNull { it.isSelected }?.value.orEmpty()
        fun checked(name: String) = inputs(name).any { it.type == "checkbox" && "checked" in it.attributes }
        fun optionalChecked(name: String): Boolean? = if (inputs(name).isEmpty()) null else checked(name)
        fun choices(name: String, type: String) = inputs(name).filter { it.type == type }.mapNotNull { control ->
            val value = control.attributes["value"].orEmpty()
            if (value.isEmpty() && type == "checkbox") return@mapNotNull null
            val id = control.attributes["id"].orEmpty()
            val label = element.select("label[for]").firstOrNull { it.attr("for") == id && id.isNotEmpty() }
                ?.text()?.trim()?.takeIf(String::isNotEmpty) ?: value
            AO3FormOption(value, label, "checked" in control.attributes)
        }
        fun date(name: String): String {
            input(name)?.takeIf(String::isNotEmpty)?.let { return it }
            val options = controls.firstOrNull { it.tag == "select" && it.name == name }?.options.orEmpty()
            val chosen = options.firstOrNull { "selected" in it.attributes } ?: options.firstOrNull()
            return chosen?.attributes?.get("value")?.takeIf(String::isNotEmpty) ?: chosen?.text.orEmpty()
        }
        val token = doc.selectFirst("meta[name=csrf-token]")?.attr("content")?.trim()?.takeIf(String::isNotEmpty)
            ?: input(AO3WorkFormField.authenticityToken)?.takeIf(String::isNotEmpty)
            ?: invalid("AO3 didn't give the work form a security token.")
        val workID = action.pathSegments.getOrNull(1)?.toLongOrNull()
        fun hasSubmit(name: String) = controls.any { it.name == name && (it.tag == "button" || it.type == "submit") }
        val posted = hasSubmit(AO3WorkSubmitAction.Update.fieldName) && !hasSubmit(AO3WorkSubmitAction.SaveDraft.fieldName)
        val heading = doc.selectFirst("h2.heading, h2")?.text().orEmpty().lowercase()
        val kind = when {
            action.encodedPath.contains("edit_tags") || action.encodedPath.contains("update_tags") -> AO3WorkFormKind.EditTags
            heading.contains("post new") || workID == null -> AO3WorkFormKind.New
            !posted -> AO3WorkFormKind.Draft
            else -> AO3WorkFormKind.Edit
        }
        val contentControl = controls.firstOrNull { it.tag == "textarea" && it.name == AO3WorkFormField.chapterContent }
            ?: controls.firstOrNull { it.tag == "textarea" && it.attributes["id"] == "content" }
        val chapterContent = textarea(AO3WorkFormField.chapterContent).takeIf { it.isNotBlank() }
            ?: controls.firstOrNull { it.tag == "textarea" && it.attributes["id"] == "content" }?.text.orEmpty()
        val chapterTitle = input(AO3WorkFormField.chapterTitle).orEmpty()
        val chapterSummary = textarea(AO3WorkFormField.chapterSummary)
        val chapter = if (contentControl != null || chapterTitle.isNotEmpty() || chapterSummary.isNotEmpty()) {
            AO3WorkChapterDraft(chapterTitle, chapterSummary, chapterContent,
                date(AO3WorkFormField.chapterPublishedYear), date(AO3WorkFormField.chapterPublishedMonth),
                date(AO3WorkFormField.chapterPublishedDay))
        } else null
        val pseudOptions = select(AO3WorkFormField.authorIDs)
        val ids = pseudOptions.filter { it.isSelected }.map { it.value }.ifEmpty {
            inputs(AO3WorkFormField.authorIDs).filter { it.type == "hidden" }
                .map { it.attributes["value"].orEmpty() }.filter(String::isNotEmpty)
        }
        val warnings = choices(AO3WorkFormField.warnings, "checkbox")
        val categories = choices(AO3WorkFormField.categories, "checkbox")
        val comments = choices(AO3WorkFormField.commentPermissions, "radio")
        val seriesOptions = select(AO3WorkFormField.seriesID)
        val chapterLinks = doc.select("a[href*=/chapters/][href*=/edit]")
        val total = input(AO3WorkFormField.wipLength).orEmpty()
        return AO3WorkForm(
            kind, workID, actionUrl, token, input(AO3WorkFormField.methodOverride)?.takeIf(String::isNotEmpty),
            posted, controls, attributes(element),
            title = input(AO3WorkFormField.title).orEmpty(),
            rating = selected(AO3WorkFormField.rating), ratingOptions = select(AO3WorkFormField.rating),
            warnings = warnings.filter { it.isSelected }.map { it.value }, warningOptions = warnings,
            categories = categories.filter { it.isSelected }.map { it.value }, categoryOptions = categories,
            fandoms = splitWorkList(input(AO3WorkFormField.fandoms).orEmpty()),
            relationships = splitWorkList(input(AO3WorkFormField.relationships).orEmpty()),
            characters = splitWorkList(input(AO3WorkFormField.characters).orEmpty()),
            additionalTags = splitWorkList(input(AO3WorkFormField.additionalTags).orEmpty()),
            languageID = selected(AO3WorkFormField.languageID), languageOptions = select(AO3WorkFormField.languageID),
            summary = textarea(AO3WorkFormField.summary), notes = textarea(AO3WorkFormField.notes), endnotes = textarea(AO3WorkFormField.endnotes),
            collectionNames = splitWorkList(input(AO3WorkFormField.collectionNames).orEmpty()),
            gifts = splitWorkList(input(AO3WorkFormField.recipients).orEmpty()),
            series = seriesOptions.mapNotNull { option -> option.value.toLongOrNull()?.takeIf { it > 0 }?.let {
                AO3SeriesMembership(it, option.title, option.isSelected)
            } }, seriesOptions = seriesOptions, newSeriesTitle = input(AO3WorkFormField.seriesTitle).orEmpty(),
            currentSeries = element.select("a[href*=/serial_works/]").mapNotNull { removal ->
                val link = removal.parent()?.parent()?.selectFirst("a[href*=/series/]") ?: return@mapNotNull null
                val id = pathID(link.attr("href"), "series") ?: return@mapNotNull null
                AO3CurrentSeries(id, link.text().trim(), pathID(removal.attr("href"), "serial_works"))
            },
            parentWork = AO3ParentWorkDraft(
                input(AO3WorkFormField.parentURL) ?: inputsContaining(controls, "[url]"),
                input(AO3WorkFormField.parentTitle) ?: inputsContaining(controls, "parent_work"),
                input(AO3WorkFormField.parentAuthor).orEmpty(), input(AO3WorkFormField.parentLanguageID).orEmpty(),
                checked(AO3WorkFormField.parentTranslation)),
            parentLanguageOptions = select(AO3WorkFormField.parentLanguageID),
            existingParentTitles = element.select("#parent-options a[href]").map { it.text().trim() }
                .filter { it.isNotEmpty() && !it.equals("remove", true) },
            chapter = chapter, creators = AO3CreatorDraft(ids, pseudOptions, input(AO3WorkFormField.authorByline).orEmpty()),
            chaptersPosted = if (chapterLinks.isNotEmpty()) chapterLinks.size else if (total.toIntOrNull() == 1) 1 else null,
            chapterTotal = total, isChaptered = checked("chapters-options-show") || controls.any {
                it.attributes["id"] == "chapters-options-show" && "checked" in it.attributes
            },
            backdate = checked(AO3WorkFormField.backdate), restricted = checked(AO3WorkFormField.restricted),
            moderatedCommenting = checked(AO3WorkFormField.moderatedCommenting),
            commentPermissions = comments.lastOrNull { it.isSelected }?.value.orEmpty(), commentPermissionOptions = comments,
            anonymous = optionalChecked(AO3WorkFormField.anonymous), collectionInbox = optionalChecked(AO3WorkFormField.collectionInbox),
            workSkinID = selected(AO3WorkFormField.workSkinID), workSkinOptions = select(AO3WorkFormField.workSkinID)
        )
    }

    private fun snapshot(element: Element): AO3ServedControl {
        val attrs = attributes(element)
        val options = element.select("option").map { option ->
            AO3ServedOption(option.attr("value").takeIf { option.hasAttr("value") } ?: option.text(),
                option.text(), attributes(option), option.hasAttr("disabled") ||
                    option.parents().any { it.tagName() == "optgroup" && it.hasAttr("disabled") })
        }
        val type = element.attr("type").lowercase()
        val values = when (element.tagName()) {
            "select" -> {
                val selected = if (element.hasAttr("multiple")) options.filter { "selected" in it.attributes }
                else listOfNotNull(options.lastOrNull { "selected" in it.attributes } ?:
                    options.firstOrNull { !it.disabled }?.takeIf { (attrs["size"]?.toIntOrNull() ?: 1) <= 1 })
                selected.filterNot { it.disabled }.map { it.value }
            }
            "textarea" -> listOf(element.wholeText())
            else -> listOf(attrs["value"] ?: if (type == "checkbox" || type == "radio") "on" else "")
        }
        val disabled = element.hasAttr("disabled") || element.parents().any { parent ->
            parent.tagName() == "fieldset" && parent.hasAttr("disabled") &&
                parent.children().firstOrNull { it.tagName() == "legend" }?.let { legend ->
                    element == legend || element.parents().contains(legend)
                } != true
        }
        return AO3ServedControl(element.tagName(), attrs, element.wholeText(), values, options, disabled)
    }

    private fun attributes(element: Element) = element.attributes().associate { it.key to it.value }
    private fun inputsContaining(controls: List<AO3ServedControl>, part: String) = controls
        .firstOrNull { it.tag == "input" && it.name.contains(part) }?.attributes?.get("value").orEmpty()
    private fun pathID(path: String, kind: String): Long? = Regex("(?:^|/)$kind/([0-9]+)(?:[/?#]|$)")
        .find(path)?.groupValues?.get(1)?.toLongOrNull()
    private fun invalid(message: String): Nothing = throw AO3WorkFormParseException.InvalidForm(message)
}
