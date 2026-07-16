import Foundation

/// Reference to an AO3 help page (the `?` modal next to a preferences heading or field).
nonisolated struct AO3PreferenceHelpRef: Equatable, Hashable, Identifiable, Sendable {
    /// Accessibility / sheet title (from `aria-label` or heading).
    let title: String
    let url: URL

    var id: String { url.absoluteString }
}

/// One topic inside an AO3 preference help page (`dt` + `dd` pair).
nonisolated struct AO3PreferenceHelpEntry: Equatable, Identifiable, Hashable, Sendable {
    let heading: String
    let body: String

    var id: String { heading }
}

/// Fetched contents of an AO3 `/help/…` page for in-app display.
nonisolated struct AO3PreferenceHelpContent: Equatable, Identifiable, Sendable {
    let title: String
    /// Definition-list topics, each rendered as its own card.
    let entries: [AO3PreferenceHelpEntry]
    /// Trailing note under the list (e.g. Preferences FAQ blurb), if any.
    let footer: String?
    let sourceURL: URL

    var id: String { sourceURL.absoluteString }

    /// Flattened plain text (tests + accessibility).
    var body: String {
        var parts = entries.map { entry in
            entry.body.isEmpty ? entry.heading : "\(entry.heading)\n\n\(entry.body)"
        }
        if let footer, !footer.isEmpty {
            parts.append(footer)
        }
        return parts.joined(separator: "\n\n")
    }
}

/// The attribute key inside an AO3 Preferences form field name
/// (`preference[adult]` → `adult`). Fields that don't match the shape are
/// returned as-is.
nonisolated func preferenceFieldKey(_ name: String) -> String {
    guard name.hasPrefix("preference["), name.hasSuffix("]") else { return name }
    return String(name.dropFirst("preference[".count).dropLast())
}

/// One boolean preference from AO3's Preferences form (`preference[key]`).
nonisolated struct AO3PreferenceToggle: Identifiable, Equatable, Hashable, Sendable {
    /// Full form field name, e.g. `preference[adult]`.
    let name: String
    let label: String
    var isOn: Bool
    /// Optional field-level help (`?` next to the label on AO3).
    let help: AO3PreferenceHelpRef?

    var id: String { name }

    /// The attribute key inside `preference[...]`.
    var key: String { preferenceFieldKey(name) }
}

/// A `<select>` preference (site skin, time zone, optional locale).
nonisolated struct AO3PreferenceSelect: Identifiable, Equatable, Hashable, Sendable {
    let name: String
    let label: String
    var selectedValue: String
    let options: [Option]
    let help: AO3PreferenceHelpRef?

    var id: String { name }

    struct Option: Identifiable, Equatable, Hashable {
        let value: String
        let title: String
        var id: String { value }
    }

    var key: String { preferenceFieldKey(name) }
}

/// A free-text preference (currently browser page title format).
nonisolated struct AO3PreferenceTextField: Identifiable, Equatable, Hashable, Sendable {
    let name: String
    let label: String
    var value: String
    let help: AO3PreferenceHelpRef?

    var id: String { name }

    var key: String { preferenceFieldKey(name) }
}

/// One fieldset on AO3's Preferences page (Privacy, Display, Comments, …).
nonisolated struct AO3PreferenceSection: Identifiable, Equatable, Hashable, Sendable {
    let title: String
    /// Section-level help from the heading's `?` control.
    let help: AO3PreferenceHelpRef?
    var toggles: [AO3PreferenceToggle]

    var id: String { title }
}

/// Account-management links AO3 shows above the preferences form (profile, password, …).
/// These stay web-only for now — different forms/flows from the preference POST.
nonisolated struct AO3PreferenceWebLink: Identifiable, Equatable, Hashable, Sendable {
    let title: String
    let url: URL
    var id: String { url.absoluteString }
}

/// Hidden `preference[...]` input carried through from the live form.
nonisolated struct AO3PreferenceHiddenField: Equatable, Hashable, Sendable {
    let name: String
    let value: String
}

/// Parsed snapshot of `/users/:login/preferences` for native edit + save.
nonisolated struct AO3PreferencesSnapshot: Equatable, Sendable {
    /// Absolute URL of the form `action` (usually `/users/:login/preference`).
    let actionURL: URL
    /// Rails `_method` value when present (`put` / `patch`); defaults to POST body only.
    let httpMethodOverride: String?
    let csrfToken: String
    var sections: [AO3PreferenceSection]
    var selects: [AO3PreferenceSelect]
    var textFields: [AO3PreferenceTextField]
    /// Hidden `preference[...]` inputs from the live form (ids, server defaults).
    /// Included on save unless a toggle/select/text field overrides the same name.
    let hiddenFields: [AO3PreferenceHiddenField]
    let webLinks: [AO3PreferenceWebLink]

    /// Flat mutable toggles for lookups.
    var allToggles: [AO3PreferenceToggle] {
        sections.flatMap(\.toggles)
    }

    /// Form-encoded preference fields (without CSRF / `_method`).
    func preferenceParameters() -> [(String, String)] {
        var params: [(String, String)] = []
        var overridden = Set<String>()
        for section in sections {
            for toggle in section.toggles {
                // Rails checkboxes: "1" when on, "0" when off (hidden field pattern).
                params.append((toggle.name, toggle.isOn ? "1" : "0"))
                overridden.insert(toggle.name)
            }
        }
        for select in selects {
            params.append((select.name, select.selectedValue))
            overridden.insert(select.name)
        }
        for field in textFields {
            params.append((field.name, field.value))
            overridden.insert(field.name)
        }
        for hidden in hiddenFields where !overridden.contains(hidden.name) {
            params.append((hidden.name, hidden.value))
        }
        return params
    }
}
