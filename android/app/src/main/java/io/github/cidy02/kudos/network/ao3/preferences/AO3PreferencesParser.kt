package io.github.cidy02.kudos.network.ao3.preferences

import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.writes.normalizedText
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

class AO3PreferencesParseException(message: String) : Exception(message)

/**
 * Parses AO3 `/users/:login/preferences` form HTML.
 * Port of iOS `AO3Client.parsePreferencesForm`.
 */
class AO3PreferencesParser {
    fun parse(html: String): AO3PreferencesSnapshot {
        val doc = Jsoup.parse(html, AO3Constants.BASE_URL)
        val form = doc.selectFirst("form[action*=preference]")
            ?: doc.selectFirst("#main form")
            ?: throw AO3PreferencesParseException("Preferences form not found.")
        val actionRaw = form.attr("action").trim()
        val actionUrl = absoluteUrl(actionRaw)
            ?: throw AO3PreferencesParseException("Preferences form action missing.")
        val csrf = form.selectFirst("input[name=authenticity_token]")?.attr("value")?.trim()
            ?: doc.selectFirst("meta[name=csrf-token]")?.attr("content")?.trim()
            ?: throw AO3PreferencesParseException("CSRF token missing.")
        val methodOverride = form.selectFirst("input[name=_method]")?.attr("value")?.trim()

        val sections = mutableListOf<AO3PreferenceSection>()
        for (fieldset in form.select("fieldset")) {
            // The heading's own words: AO3 puts the "?" link inside it, and its glyph was read
            // into the title ("Privacy ?").
            val headingElement = fieldset.selectFirst("h4.heading")
            val legend = fieldset.selectFirst("legend")
            val heading = titleWithoutHelp(headingElement) ?: titleWithoutHelp(legend) ?: "Preferences"
            // iOS falls back to any help link in the fieldset; that would put one field's help
            // on the whole section, so only the heading and the legend are asked here.
            val sectionHelp = headingElement?.let { parseHelpRef(it, heading) } ?: legend?.let { parseHelpRef(it, heading) }
            val toggles = parseToggles(fieldset)
            if (toggles.isNotEmpty()) {
                val existing = sections.indexOfFirst { it.title.equals(heading, true) }
                if (existing >= 0) {
                    sections[existing] = sections[existing].copy(
                        toggles = sections[existing].toggles + toggles
                    )
                } else {
                    sections += AO3PreferenceSection(title = heading, toggles = toggles, help = sectionHelp)
                }
            }
        }
        if (sections.isEmpty()) {
            val all = parseToggles(form)
            if (all.isNotEmpty()) {
                sections += AO3PreferenceSection(title = "Preferences", toggles = all)
            }
        }

        val selects = form.select("select[name]").mapNotNull { select ->
            val name = select.attr("name")
            if (name.isBlank() || name == "authenticity_token") return@mapNotNull null
            val label = findLabel(form, select) ?: name
            val options = select.select("option").map {
                it.attr("value") to it.normalizedText()
            }
            val selected = select.selectFirst("option[selected]")?.attr("value")
                ?: options.firstOrNull()?.first.orEmpty()
            AO3PreferenceSelect(name, label, options, selected, fieldHelp(form, select, label))
        }

        val textFields = form.select("input[type=text][name], input[type=number][name], textarea[name]")
            .mapNotNull { input ->
                val name = input.attr("name")
                if (name.isBlank()) return@mapNotNull null
                val label = findLabel(form, input) ?: name
                val value = if (input.tagName() == "textarea") {
                    input.text()
                } else {
                    input.attr("value")
                }
                AO3PreferenceTextField(name, label, value, fieldHelp(form, input, label))
            }

        val hidden = form.select("input[type=hidden][name]").map {
            it.attr("name") to it.attr("value")
        }.filter { it.first != "authenticity_token" && it.first != "_method" }

        if (sections.isEmpty() && selects.isEmpty() && textFields.isEmpty()) {
            throw AO3PreferencesParseException("No preference fields found.")
        }

        return AO3PreferencesSnapshot(
            actionUrl = actionUrl,
            httpMethodOverride = methodOverride,
            csrfToken = csrf,
            sections = sections,
            selects = selects,
            textFields = textFields,
            hiddenFields = hidden
        )
    }

    private fun parseToggles(root: Element): List<AO3PreferenceToggle> {
        return root.select("input[type=checkbox][name]").mapNotNull { input ->
            val name = input.attr("name")
            if (name.isBlank()) return@mapNotNull null
            val label = findLabel(root, input)
                ?: input.parent()?.normalizedText()?.takeIf { it.isNotBlank() }
                ?: name
            // Help `?` links live near the control (same <li>/<dd>/<dt>), not on
            // the checkbox itself — match iOS `parseHelpRef(in:container)`.
            val container = nearestFieldContainer(input) ?: root
            AO3PreferenceToggle(
                name = name,
                label = label,
                checked = input.hasAttr("checked"),
                help = parseHelpRef(container, label)
            )
        }
    }

    /**
     * The words AO3 puts on a control. Its labels point at the control's **id**
     * ("preference_skin_id"), not its name ("preference[skin_id]"): asked by name, a select
     * and a text field got no label and were shown under their raw field names.
     */
    private fun findLabel(root: Element, control: Element): String? {
        val targets = listOf(control.id(), control.attr("name")).filter { it.isNotEmpty() }
        root.select("label[for]").firstOrNull { it.attr("for") in targets }
            ?.let(::titleWithoutHelp)?.let { return it }
        return control.parents().firstOrNull { it.tagName() == "label" }?.let(::titleWithoutHelp)
    }

    /**
     * AO3 renders help as
     * `<a href="/help/…" class="help symbol question modal" …>`.
     * Prefer anchors scoped to the field container so section-heading help is
     * not incorrectly attributed to every toggle in the fieldset.
     */
    private fun parseHelpRef(root: Element, fallbackTitle: String): AO3PreferenceHelpRef? {
        for (anchor in root.select(HELP_LINKS)) {
            val href = anchor.attr("href").trim()
            if (href.isEmpty()) continue
            val absolute = absoluteUrl(href) ?: continue
            if (!absolute.contains("/help/", ignoreCase = true)) continue
            // iOS: the link's own name for the page, else the row it sits on.
            val title = anchor.attr("aria-label").trim().ifEmpty { anchor.attr("title").trim() }.ifEmpty { fallbackTitle }
            return AO3PreferenceHelpRef(title = title, url = absolute)
        }
        return null
    }

    /** A select's or a text field's help: by its control, or by its label (AO3 puts it in the `dt`). */
    private fun fieldHelp(form: Element, control: Element, label: String): AO3PreferenceHelpRef? {
        nearestFieldContainer(control)?.let { parseHelpRef(it, label) }?.let { return it }
        // Compared in code: a name like "preference[skin_id]" is not a selector.
        val targets = listOf(control.id(), control.attr("name")).filter { it.isNotEmpty() }
        val labelElement = form.select("label[for]").firstOrNull { it.attr("for") in targets }
        return labelElement?.let(::nearestFieldContainer)?.let { parseHelpRef(it, label) }
    }

    private fun titleWithoutHelp(element: Element?): String? {
        element ?: return null
        val own = element.clone()
        own.select(HELP_LINKS).remove()
        return own.normalizedText().takeIf { it.isNotBlank() }
    }

    /**
     * iOS `parseHelpPage`: an AO3 `/help/…` page as topics (`dl#help`: each `dt` a heading, its
     * `dd`s the text), with what follows the list as a footer. A page without the list is one
     * topic.
     */
    fun parseHelpPage(html: String, sourceUrl: String): AO3PreferenceHelpContent {
        val doc = Jsoup.parse(html, AO3Constants.BASE_URL)
        val main = doc.selectFirst("#main") ?: doc.body()
        val heading = main.selectFirst("h2.heading, h3.heading, h4")?.normalizedText().orEmpty()
        val title = heading.ifEmpty { doc.title().replace(" | Archive of Our Own", "").trim() }.ifEmpty { "Help" }

        val entries = mutableListOf<AO3PreferenceHelpEntry>()
        val footerParts = mutableListOf<String>()
        val list = main.selectFirst("dl#help")
        if (list != null) {
            var header: String? = null
            var body = mutableListOf<String>()
            fun flush() {
                header?.takeIf { it.isNotEmpty() }?.let { entries += AO3PreferenceHelpEntry(it, body.joinToString("\n\n")) }
                header = null
                body = mutableListOf()
            }
            for (child in list.children()) {
                when (child.tagName().lowercase()) {
                    "dt" -> { flush(); header = child.normalizedText() }
                    "dd" -> plainHelpText(child).takeIf { it.isNotEmpty() }?.let { body += it }
                }
            }
            flush()
            var sibling = list.nextElementSibling()
            while (sibling != null) {
                if (sibling.tagName() == "p" || sibling.tagName() == "div") {
                    plainHelpText(sibling).takeIf { it.isNotEmpty() }?.let { footerParts += it }
                }
                sibling = sibling.nextElementSibling()
            }
        } else {
            plainHelpText(main).takeIf { it.isNotEmpty() }?.let { entries += AO3PreferenceHelpEntry(title, it) }
        }

        val footer = footerParts.joinToString("\n\n").takeIf { it.isNotEmpty() }
        if (entries.isEmpty() && footer == null) throw AO3PreferencesParseException("AO3's help page could not be read.")
        if (entries.isEmpty()) {
            return AO3PreferenceHelpContent(title, listOf(AO3PreferenceHelpEntry(title, footer.orEmpty())), null, sourceUrl)
        }
        return AO3PreferenceHelpContent(title, entries, footer, sourceUrl)
    }

    private fun plainHelpText(element: Element): String {
        val paragraphs = element.select("p")
        if (paragraphs.isNotEmpty()) {
            return paragraphs.map { it.normalizedText() }.filter { it.isNotEmpty() }.joinToString("\n\n")
        }
        return element.normalizedText()
    }

    private fun nearestFieldContainer(element: Element): Element? {
        var node: Element? = element
        repeat(6) {
            val parent = node?.parent() ?: return null
            when (parent.tagName().lowercase()) {
                "li", "dd", "dt", "div" -> return parent
            }
            node = parent
        }
        return null
    }

    private companion object {
        const val HELP_LINKS =
            "a.help[href], a.modal[href*=/help/], a[href*=/help/][class*=help], a[href*=/help/][class*=question]"
    }

    private fun absoluteUrl(href: String): String? {
        val raw = href.trim()
        if (raw.isEmpty()) return null
        if (raw.startsWith("http")) return raw
        return AO3Constants.baseHttpUrl.resolve(raw)?.toString()
    }
}
