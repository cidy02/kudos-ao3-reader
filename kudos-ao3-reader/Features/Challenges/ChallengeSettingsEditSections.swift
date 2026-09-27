import SwiftUI

/// 1cf's collection-backed rows (Basics, Anonymity and moderation) and its
/// matcher settings, kept apart from the challenge form's own sections.
///
/// Name, Tagline, Introduction and FAQ are collection fields
/// (`AO3CollectionForm`), read from the collection's edit page and edited on
/// 1cg. The four moderation switches are collection preferences too; they save
/// through the collection form after the challenge form, in the same Save.
extension ChallengeSettingsEditView {

    // MARK: - Basics

    /// One `List` row per link, so each pushes on its own.
    @ViewBuilder
    var basicsRows: some View {
        let rows = basicsFacts
        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
            SubjectFormRow(label: row.label, value: row.value, showsDisclosure: true)
                .subjectRowNavigation(accessibilityLabel: row.label) {
                    AO3CollectionFormView(slug: collectionSlug)
                }
                .panelSegment(index, of: rows.count, gutter: gutter)
        }
    }

    /// The spec's "Name / Tagline / Introduction · 142 words / FAQ". The host
    /// byline is left out: the edit page carries owner pseud ids, not names.
    private var basicsFacts: [(label: String, value: String)] {
        guard let collection = collectionForm else {
            return [("Collection settings", collectionLoadFailed ? "Couldn't load" : "Loading…")]
        }
        return [
            ("Name", collection.title),
            ("Tagline", collection.description.isEmpty ? "None" : collection.description),
            ("Introduction", Self.wordCountText(collection.introduction)),
            ("FAQ", collection.faq.isEmpty ? "None" : "Set")
        ]
    }

    /// "142 words" for AO3's HTML prose; tags, and punctuation a tag split off,
    /// are not words.
    static func wordCountText(_ html: String) -> String {
        let text = html.replacing(/<[^>]+>/, with: " ")
        let count = text.split(whereSeparator: \.isWhitespace)
            .filter { $0.contains { $0.isLetter || $0.isNumber } }.count
        return count == 0 ? "None" : AO3ChallengeCountText.plural(count, "word")
    }

    // MARK: - Matching

    /// fieldset#match_settings (Q9), with AO3's own options: "All" or a count
    /// for each type, and whether optional tags count toward it.
    @ViewBuilder
    var matchSettingsPanels: some View {
        if let match = settings.matchSettings {
            VStack(spacing: 0) {
                SubjectFormRow(
                    label: "Match on",
                    value: match.matchOn.isEmpty
                        ? "Nothing required"
                        : match.matchOn.map { AO3PotentialMatchSettings.label($0) }.joined(separator: ", ")
                )
                SubjectRowSeparator()
                optionRow(
                    "Requests that must match", value: match.numRequiredPrompts,
                    options: AO3PotentialMatchSettings.requestOptions
                ) { form?.settings.matchSettings?.numRequiredPrompts = $0 }
                ForEach(AO3PotentialMatchSettings.tagTypes, id: \.self) { type in
                    SubjectRowSeparator()
                    optionRow(
                        AO3PotentialMatchSettings.label(type), value: match.numRequired[type] ?? 0,
                        options: AO3PotentialMatchSettings.tagOptions
                    ) { form?.settings.matchSettings?.numRequired[type] = $0 }
                }
            }
            .subjectPanel()
            .pageBodyRow(top: 8, gutter: gutter)

            SubjectFieldLabel(text: "Count optional tags for", style: .formGroup)
                .pageBodyRow(top: 12, gutter: gutter)
            VStack(spacing: 0) {
                ForEach(Array(AO3PotentialMatchSettings.tagTypes.enumerated()), id: \.offset) { index, type in
                    if index > 0 { SubjectRowSeparator() }
                    SubjectFormRow(label: AO3PotentialMatchSettings.label(type), arrangement: .control) {
                        Toggle("", isOn: Binding(
                            get: { form?.settings.matchSettings?.includeOptional[type] ?? false },
                            set: { form?.settings.matchSettings?.includeOptional[type] = $0 }
                        ))
                        .labelsHidden()
                        .tint(palette.accent)
                    }
                }
            }
            .subjectPanel()
            .pageBodyRow(top: 8, gutter: gutter)
        }
    }

    private func optionRow(
        _ label: String, value: Int, options: [Int], set: @escaping (Int) -> Void
    ) -> some View {
        SubjectFormRow(label: label, arrangement: .control) {
            optionMenu(label, value: value, options: options, display: AO3PotentialMatchSettings.optionTitle, set: set)
        }
    }

    /// A `Menu`, as `WritingChoiceRow` uses: it answers only its own label.
    func optionMenu(
        _ title: String, value: Int, options: [Int],
        display optionTitle: @escaping (Int) -> String = { String($0) },
        set: @escaping (Int) -> Void
    ) -> some View {
        Menu {
            Picker(title, selection: Binding(get: { value }, set: set)) {
                ForEach(options, id: \.self) { Text(optionTitle($0)).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 4) {
                Text(optionTitle(value))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(palette.accent)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(optionTitle(value))
    }

    // MARK: - Anonymity and moderation

    /// The spec's four switches are collection preferences. A prompt meme also
    /// has its own "anonymous prompts" setting on the challenge form.
    var moderationPanel: some View {
        VStack(spacing: 0) {
            collectionToggle("Anonymous until reveal", \.isAnonymous)
            SubjectRowSeparator()
            collectionToggle("Unrevealed until reveal", \.isUnrevealed)
            SubjectRowSeparator()
            collectionToggle("Moderated sign-ups", \.isModerated)
            SubjectRowSeparator()
            collectionToggle("Closed to new sign-ups", \.isClosed)
            if settings.kind == .promptMeme {
                SubjectRowSeparator()
                SubjectFormRow(label: "Prompts posted anonymously", arrangement: .control) {
                    Toggle("", isOn: Binding(
                        get: { form?.settings.isAnonymous ?? false },
                        set: { form?.settings.isAnonymous = $0 }
                    ))
                    .labelsHidden()
                    .tint(palette.accent)
                }
            }
        }
        .subjectPanel()
    }

    private func collectionToggle(_ label: String, _ keyPath: WritableKeyPath<AO3CollectionForm, Bool>) -> some View {
        SubjectFormRow(label: label, arrangement: .control, isDisabled: collectionForm == nil) {
            Toggle("", isOn: Binding(
                get: { collectionForm?[keyPath: keyPath] ?? false },
                set: { collectionForm?[keyPath: keyPath] = $0 }
            ))
            .labelsHidden()
            .tint(palette.accent)
        }
    }

    /// Turning off Unrevealed or Anonymous shows works or creators at once, and
    /// the app cannot turn it back: it is confirmed before Save posts it.
    var saveRevealsSomething: Bool {
        guard let before = loadedCollectionForm, let after = collectionForm else { return false }
        return (before.isUnrevealed && !after.isUnrevealed) || (before.isAnonymous && !after.isAnonymous)
    }

    var collectionFormChanged: Bool {
        guard let before = loadedCollectionForm, let after = collectionForm else { return false }
        return [before.isAnonymous, before.isUnrevealed, before.isModerated, before.isClosed]
            != [after.isAnonymous, after.isUnrevealed, after.isModerated, after.isClosed]
    }
}
