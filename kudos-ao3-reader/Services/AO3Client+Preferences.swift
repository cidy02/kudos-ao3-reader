import Foundation
import SwiftSoup

extension AO3Client {
    /// Signed-in user's AO3 Preferences page.
    static func preferencesURL(username: String) -> URL? {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? username
        return URL(string: "https://archiveofourown.org/users/\(encoded)/preferences")
    }

    /// Parses the Preferences form from a live `/users/:login/preferences` HTML page.
    /// Field labels, groups, and help (`?`) links come from the page so they track
    /// AO3's locale/copy and help targets.
    static func parsePreferencesForm(from html: String) throws -> AO3PreferencesSnapshot {
        let doc = try SwiftSoup.parse(html)
        guard let form = try doc.select("form[action*='/preference']").first()
            ?? doc.select("#main form").first()
        else {
            throw AO3Error.parse
        }

        let action = (try? form.attr("action"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let actionURL = absoluteAO3URL(action) else {
            throw AO3Error.parse
        }

        guard let csrf = parseCSRFToken(from: html)
            ?? ((try? form.select("input[name=authenticity_token]").first()?.attr("value"))
                .flatMap { $0.isEmpty ? nil : $0 })
        else {
            throw AO3Error.parse
        }

        let methodOverride = try? form.select("input[name=_method]").first()?.attr("value")

        var sections: [AO3PreferenceSection] = []
        var looseToggles: [AO3PreferenceToggle] = []

        let fieldsets = try form.select("fieldset").array()
        for fieldset in fieldsets {
            let headingEl = try? fieldset.select("h4.heading").first()
            let legend = ((try? fieldset.select("legend").first()?.text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rawHeading = ((try? headingEl?.text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var title = cleanPreferenceTitle(rawHeading.isEmpty ? legend : rawHeading)
            if title.isEmpty { title = "Preferences" }

            let sectionHelp = headingEl.flatMap { parseHelpRef(in: $0, fallbackTitle: title) }
                ?? parseHelpRef(in: fieldset, fallbackTitle: title)

            let toggles = try parsePreferenceToggles(in: fieldset)
            if !toggles.isEmpty {
                if let idx = sections.firstIndex(where: {
                    $0.title.caseInsensitiveCompare(title) == .orderedSame
                }) {
                    sections[idx].toggles.append(contentsOf: toggles)
                } else {
                    sections.append(
                        AO3PreferenceSection(title: title, help: sectionHelp, toggles: toggles)
                    )
                }
            } else {
                looseToggles.append(contentsOf: toggles)
            }
        }

        if !looseToggles.isEmpty {
            if let idx = sections.firstIndex(where: { $0.title == "Other" }) {
                sections[idx].toggles.append(contentsOf: looseToggles)
            } else {
                sections.append(
                    AO3PreferenceSection(title: "Other", help: nil, toggles: looseToggles)
                )
            }
        }

        if sections.isEmpty {
            let all = try parsePreferenceToggles(in: form)
            if !all.isEmpty {
                sections = [AO3PreferenceSection(title: "Preferences", help: nil, toggles: all)]
            }
        }

        let selects = try parsePreferenceSelects(in: form, document: doc)
        let textFields = try parsePreferenceTextFields(in: form, document: doc)
        let webLinks = parsePreferenceWebLinks(in: doc)

        guard !sections.isEmpty || !selects.isEmpty || !textFields.isEmpty else {
            throw AO3Error.parse
        }

        return AO3PreferencesSnapshot(
            actionURL: actionURL,
            httpMethodOverride: methodOverride?.nilIfBlank,
            csrfToken: csrf,
            sections: sections,
            selects: selects,
            textFields: textFields,
            webLinks: webLinks
        )
    }

    /// Parses an AO3 `/help/…` page into structured topics matching the modal
    /// content (`#main` / `dl#help`), so the in-app sheet can use card rows.
    static func parseHelpPage(from html: String, sourceURL: URL) throws -> AO3PreferenceHelpContent {
        let doc = try SwiftSoup.parse(html)
        let main = try doc.select("#main").first() ?? doc.body()
        guard let main else { throw AO3Error.parse }

        let heading = ((try? main.select("h2.heading, h3.heading, h4").first()?.text()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let titleFromDoc = ((try? doc.title()) ?? "")
            .replacingOccurrences(of: " | Archive of Our Own", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = heading.isEmpty ? (titleFromDoc.isEmpty ? "Help" : titleFromDoc) : heading

        var entries: [AO3PreferenceHelpEntry] = []
        if let helpList = try? main.select("dl#help").first() {
            let children = helpList.getChildNodes()
            var currentHeader: String?
            var currentBody: [String] = []
            func flush() {
                guard let header = currentHeader, !header.isEmpty else {
                    currentHeader = nil
                    currentBody = []
                    return
                }
                let body = currentBody
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
                entries.append(AO3PreferenceHelpEntry(heading: header, body: body))
                currentHeader = nil
                currentBody = []
            }
            for node in children {
                guard let el = node as? Element else { continue }
                let tag = el.tagName().lowercased()
                if tag == "dt" {
                    flush()
                    currentHeader = ((try? el.text()) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else if tag == "dd" {
                    let text = plainHelpText(from: el)
                    if !text.isEmpty { currentBody.append(text) }
                }
            }
            flush()
        }

        var footerParts: [String] = []
        if let helpList = try? main.select("dl#help").first() {
            var sibling = try? helpList.nextElementSibling()
            while let el = sibling {
                if el.tagName() == "p" || el.tagName() == "div" {
                    let text = plainHelpText(from: el)
                    if !text.isEmpty { footerParts.append(text) }
                }
                sibling = try? el.nextElementSibling()
            }
        } else {
            // No dl#help — treat the main block as a single entry.
            let text = plainHelpText(from: main)
            if !text.isEmpty {
                entries = [AO3PreferenceHelpEntry(heading: title, body: text)]
            }
        }

        let footer = footerParts.isEmpty
            ? nil
            : footerParts.joined(separator: "\n\n")
        guard !entries.isEmpty || !(footer ?? "").isEmpty else { throw AO3Error.parse }
        if entries.isEmpty, let footer {
            entries = [AO3PreferenceHelpEntry(heading: title, body: footer)]
            return AO3PreferenceHelpContent(
                title: title, entries: entries, footer: nil, sourceURL: sourceURL
            )
        }

        return AO3PreferenceHelpContent(
            title: title, entries: entries, footer: footer, sourceURL: sourceURL
        )
    }

    // MARK: - Field parsers

    private static func parsePreferenceToggles(in root: Element) throws -> [AO3PreferenceToggle] {
        var results: [AO3PreferenceToggle] = []
        var seen = Set<String>()
        let checkboxes = try root.select("input[type=checkbox][name^=preference]").array()
        for input in checkboxes {
            let name = (try? input.attr("name")) ?? ""
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            let isOn = input.hasAttr("checked")
            let id = (try? input.attr("id")) ?? ""
            let container = nearestFieldContainer(of: input) ?? root
            let label = preferenceLabel(for: input, id: id, in: container)
                ?? humanizePreferenceName(name)
            let help = parseHelpRef(in: container, fallbackTitle: label)
            results.append(
                AO3PreferenceToggle(name: name, label: cleanPreferenceTitle(label), isOn: isOn, help: help)
            )
        }
        return results
    }

    private static func parsePreferenceSelects(
        in form: Element, document: Document
    ) throws -> [AO3PreferenceSelect] {
        var results: [AO3PreferenceSelect] = []
        let selects = try form.select("select[name^=preference]").array()
        for select in selects {
            let name = (try? select.attr("name")) ?? ""
            guard !name.isEmpty else { continue }
            let id = (try? select.attr("id")) ?? ""
            let container = nearestFieldContainer(of: select) ?? form
            let label = preferenceLabel(for: select, id: id, in: container)
                ?? preferenceLabel(for: select, id: id, in: form)
                ?? preferenceLabel(for: select, id: id, in: document)
                ?? humanizePreferenceName(name)
            let help = parseHelpRef(in: container, fallbackTitle: label)
                ?? parseHelpRef(in: relatedLabelContainer(for: container) ?? container, fallbackTitle: label)

            var options: [AO3PreferenceSelect.Option] = []
            var selected = ""
            for option in try select.select("option").array() {
                let value = (try? option.attr("value")) ?? ""
                let title = ((try? option.text()) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                options.append(.init(value: value, title: title))
                if option.hasAttr("selected") {
                    selected = value
                }
            }
            if selected.isEmpty, let first = options.first {
                selected = first.value
            }
            guard !options.isEmpty else { continue }
            results.append(
                AO3PreferenceSelect(
                    name: name,
                    label: cleanPreferenceTitle(label),
                    selectedValue: selected,
                    options: options,
                    help: help
                )
            )
        }
        return results
    }

    private static func parsePreferenceTextFields(
        in form: Element, document: Document
    ) throws -> [AO3PreferenceTextField] {
        var results: [AO3PreferenceTextField] = []
        let inputs = try form.select(
            "input[type=text][name^=preference], input:not([type])[name^=preference]"
        ).array()
        for input in inputs {
            let name = (try? input.attr("name")) ?? ""
            guard !name.isEmpty else { continue }
            let type = ((try? input.attr("type")) ?? "text").lowercased()
            if type == "hidden" || type == "submit" || type == "checkbox" { continue }
            let id = (try? input.attr("id")) ?? ""
            let container = nearestFieldContainer(of: input) ?? form
            let label = preferenceLabel(for: input, id: id, in: container)
                ?? preferenceLabel(for: input, id: id, in: form)
                ?? preferenceLabel(for: input, id: id, in: document)
                ?? humanizePreferenceName(name)
            // Help often lives on the preceding <dt> (label) while the control is in <dd>.
            let help = parseHelpRef(in: container, fallbackTitle: label)
                ?? parseHelpRef(in: relatedLabelContainer(for: container) ?? container, fallbackTitle: label)
            let value = (try? input.attr("value")) ?? ""
            results.append(
                AO3PreferenceTextField(
                    name: name,
                    label: cleanPreferenceTitle(label),
                    value: value,
                    help: help
                )
            )
        }
        return results
    }

    private static func parsePreferenceWebLinks(in document: Document) -> [AO3PreferenceWebLink] {
        guard let nav = try? document.select("ul.navigation.actions, ul.navigation").first(),
              let anchors = try? nav.select("a[href]").array()
        else { return [] }
        var links: [AO3PreferenceWebLink] = []
        var seen = Set<String>()
        for anchor in anchors {
            let href = ((try? anchor.attr("href")) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let title = ((try? anchor.text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty, !title.isEmpty,
                  let url = absoluteAO3URL(href),
                  seen.insert(url.absoluteString).inserted
            else { continue }
            if url.path.lowercased().contains("/preferences") { continue }
            if url.path.lowercased().hasPrefix("/help/") { continue }
            links.append(AO3PreferenceWebLink(title: title, url: url))
        }
        return links
    }

    // MARK: - Help link parsing

    /// AO3 renders help as `<a href="/help/…" class="help symbol question modal"
    /// aria-label="…">` with a `?` glyph inside.
    private static func parseHelpRef(in root: Element, fallbackTitle: String) -> AO3PreferenceHelpRef? {
        let candidates = (try? root.select(
            "a.help[href], a.modal[href*=/help/], a[href*=/help/][class*=help], a[href*=/help/][class*=question]"
        ).array()) ?? []
        for anchor in candidates {
            let href = ((try? anchor.attr("href")) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = absoluteAO3URL(href),
                  url.path.lowercased().contains("/help/")
            else { continue }
            let aria = ((try? anchor.attr("aria-label")) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let titleAttr = ((try? anchor.attr("title")) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let title = !aria.isEmpty ? aria
                : (!titleAttr.isEmpty ? titleAttr : fallbackTitle)
            return AO3PreferenceHelpRef(title: title, url: url)
        }
        return nil
    }

    private static func preferenceLabel(
        for element: Element, id: String, in root: Element
    ) -> String? {
        if !id.isEmpty,
           let label = try? root.select("label[for=\(CSS.escape(id))]").first() {
            let text = ((try? label.text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return cleanPreferenceTitle(text) }
        }
        var node: Element? = element
        for _ in 0 ..< 4 {
            guard let parent = node?.parent() else { break }
            if parent.tagName() == "li" || parent.tagName() == "dd" || parent.tagName() == "dt" {
                if let label = try? parent.select("label").first() {
                    let text = ((try? label.text()) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { return cleanPreferenceTitle(text) }
                }
            }
            node = parent
        }
        return nil
    }

    private static func nearestFieldContainer(of element: Element) -> Element? {
        var node: Element? = element
        for _ in 0 ..< 6 {
            guard let parent = node?.parent() else { return nil }
            let tag = parent.tagName().lowercased()
            if tag == "li" || tag == "dd" || tag == "dt" || tag == "div" {
                return parent
            }
            node = parent
        }
        return nil
    }

    /// For a `<dd>` control, the associated label/help usually sits on the previous `<dt>`.
    private static func relatedLabelContainer(for container: Element) -> Element? {
        guard container.tagName().lowercased() == "dd",
              let prev = try? container.previousElementSibling(),
              prev.tagName().lowercased() == "dt"
        else { return nil }
        return prev
    }

    private static func cleanPreferenceTitle(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip trailing help glyph / "Help" that AO3 appends beside headings.
        while true {
            let before = title
            if title.hasSuffix("?") {
                title = String(title.dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let range = title.range(of: "Help", options: [.backwards, .caseInsensitive]),
               range.upperBound == title.endIndex {
                title = String(title[..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if title == before { break }
        }
        return title
    }

    private static func plainHelpText(from element: Element) -> String {
        // Prefer paragraph structure inside dd/p.
        if let paragraphs = try? element.select("p").array(), !paragraphs.isEmpty {
            return paragraphs.compactMap { try? $0.text() }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }
        return ((try? element.text()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func humanizePreferenceName(_ name: String) -> String {
        let key: String
        if name.hasPrefix("preference["), name.hasSuffix("]") {
            key = String(name.dropFirst("preference[".count).dropLast())
        } else {
            key = name
        }
        return key
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private static func absoluteAO3URL(_ path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        let withSlash = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        return URL(string: "https://archiveofourown.org\(withSlash)")
    }
}

/// Minimal CSS.escape for id selectors used in label[for=…].
private enum CSS {
    static func escape(_ value: String) -> String {
        if value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "_" }) {
            return value
        }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
