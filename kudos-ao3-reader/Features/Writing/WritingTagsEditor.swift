import SwiftUI

/// Artboard **1bu**: the editor's tag picker — header block, the field, the
/// chosen chips, then AO3's suggestions as a panel of rows.
///
/// ## What AO3 gives us, measured rather than assumed
///
/// `/autocomplete/<kind>?term=` returns `[{"id","name"}]` and nothing else —
/// probed live, both fields carry the same name. So the two facts 1bu draws
/// beside a suggestion have to be sourced separately:
///
/// - **Canonical.** Provable, and free. `otwarchive`'s `Tag#after_create` adds
///   a tag to the autocomplete set only `if tag.canonical`, `after_update`
///   removes it the moment it is decanonicalised, and `refresh_autocomplete`
///   opens with `return unless canonical`. The set is canonical-only *by
///   construction*, so the badge is AO3's own invariant and not a guess.
/// - **The work count.** Not free, and not affordable. It lives only on
///   `/tags/search?tag_search[name]=…`, which measured **36 KB in 16 seconds**
///   for one exact name. Five visible rows per settled term is ~180 KB and up
///   to a minute of AO3's time for a decorative figure, so the count is not
///   fetched, and the column is **absent** rather than drawn as 1bu's em dash:
///   a dash in every row is a column of nothing, and beside the accent `+` it
///   reads as a minus. `AO3TagAutocomplete.parseEditorAutocomplete` already
///   honours a `work_count` key if AO3 ever sends one, and this row draws the
///   figure the moment it arrives. The tag landing page (`/tags/<name>`,
///   20 KB / 4 s) was probed too — category, parents and mergers, but no count.
///
/// Nor is the *ordering* a stand-in for the count, which an earlier draft of
/// this screen claimed in its subtitle. `lib/autocomplete_source.rb`'s
/// comparator sorts on substring match, then on **how many of the typed words
/// the phrase matched**, and only then on summed `taggings_count_cache`. Live,
/// `freeform?term=fluff` returns six "fluffbruary's Fluffbruary Prompt Month"
/// tags *above* "Fluff" — so "most-used first" is false, and the copy says only
/// what AO3 guarantees: these are its canonical tags.
///
/// The list is also capped at 15 (`limit = options[:limit] || 15`), which is why
/// the typed-term row below never claims a tag is non-canonical.
struct WritingTagsEditor: View {
    @Environment(ThemeManager.self) private var theme

    let title: String
    @Binding var values: [String]
    let options: [AO3FormOption]
    let kind: AO3TagKind?

    @State private var term = ""
    @State private var suggestions: [AO3EditorTag] = []
    @State private var errorMessage: String?
    /// A term already asked about must not ask again — the brief's rule, and
    /// with a 300 ms debounce in front of every keystroke, backspacing one
    /// character would otherwise re-run the request that just answered.
    @State private var cache: [String: [AO3EditorTag]] = [:]

    private var palette: SubjectPalette { theme.scopePalette }
    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    var body: some View {
        List {
            if let kind {
                tagPicker(kind: kind)
            } else {
                // Warnings and categories: a closed list, not a search. 1bu
                // draws only the AO3-backed kinds, so this takes the spec's
                // multi-select grammar — a tappable row per option with a
                // trailing tinted checkmark — under the same header block as
                // the picker beside it. It was a bare `Toggle` list on white
                // rows under a system title.
                Section {
                    // "Choose", not 1bu's "Edit tags": this branch also serves
                    // bulk edit's "Remove from collections", and collections are
                    // not tags.
                    SubjectHeaderBlock(
                        kicker: "Choose",
                        title: title,
                        subtitle: values.isEmpty ? "None chosen" : "\(values.count) chosen",
                        palette: palette,
                        gutter: gutter
                    )
                    .pageBodyRow(top: 20, gutter: 0)
                }
                Section {
                    optionsPanel.pageBodyRow(top: 18, gutter: gutter)
                }
            }
        }
        .cardList()
        // Blank: both branches now state the field in a header block, and an
        // inner `navigationTitle` outranks the empty one `subjectScreenWash`
        // sets, so a title here would draw the name twice.
        .navigationTitle("")
        .subjectScreenWash(palette: palette)
    }

    @ViewBuilder
    private func tagPicker(kind: AO3TagKind) -> some View {
        Section {
            SubjectHeaderBlock(
                kicker: "Edit tags",
                title: title,
                subtitle: subtitle,
                palette: palette,
                gutter: gutter
            )
            .pageBodyRow(top: 20, gutter: 0)

            field.pageBodyRow(top: 18, gutter: gutter)

            if !values.isEmpty {
                chosenChips.pageBodyRow(top: 18, gutter: gutter)
            }
        }

        Section {
            // The label and the card appear together or not at all: an empty
            // panel under "SUGGESTIONS" promises a list that is not there.
            if hasSuggestionRows {
                SubjectFieldLabel(text: "Suggestions", style: .formGroup)
                    .pageBodyRow(top: 20, gutter: gutter)
                suggestionsPanel.pageBodyRow(top: 8, gutter: gutter)
            }
            footnote.pageBodyRow(top: hasSuggestionRows ? 8 : 20, gutter: gutter)
        }
        .task(id: term) { await loadSuggestions(kind: kind) }
    }

    private var hasSuggestionRows: Bool {
        freeTypedTerm != nil || !suggestions.isEmpty || errorMessage != nil
    }

    /// 1bu's subtitle: how many are chosen, and what the list below is. It does
    /// not describe the ordering — see the type comment for why.
    private var subtitle: String {
        let offer = "AO3 offers its canonical tags as you type"
        guard !values.isEmpty else { return offer }
        return "\(values.count) chosen · \(offer)"
    }

    private var field: some View {
        GlassFieldBar(text: $term, placeholder: "Add a tag", onSubmit: { add(term) }) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        } trailing: {
            if !term.isEmpty {
                Button { term = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear")
            }
        }
        .subjectPanel(cornerRadius: 12)
    }

    /// Order is what AO3 posts, and appends land at the end, so the chips read
    /// in the order they will be sent. Reordering them is not built.
    private var chosenChips: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(values, id: \.self) { value in
                Button {
                    values.removeAll { $0 == value }
                } label: {
                    SubjectChip(
                        text: value,
                        style: .pill(isSelected: false),
                        trailingImage: "xmark",
                        palette: palette
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(value)")
            }
        }
    }

    private var suggestionsPanel: some View {
        VStack(spacing: 0) {
            if let typed = freeTypedTerm {
                suggestionRow(
                    name: typed,
                    badge: .postsAsTyped,
                    isLast: suggestions.isEmpty && errorMessage == nil
                )
            }
            ForEach(Array(suggestions.enumerated()), id: \.element.name) { index, tag in
                suggestionRow(
                    name: tag.name,
                    badge: tag.isCanonical ? .canonical : .postsAsTyped,
                    workCount: tag.workCount,
                    isLast: index == suggestions.count - 1 && errorMessage == nil
                )
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
            }
        }
        .subjectPanel()
    }

    /// The typed term offered as its own row when no suggestion is it. Labelled
    /// **"Posts as typed"** and not 1bu's "Not canonical — posts as typed":
    /// AO3 caps its suggestion list at 15, so a canonical tag ranked below the
    /// cap is indistinguishable here from one that does not exist. "Posts as
    /// typed" is true either way — the half of that sentence we can stand behind.
    private var freeTypedTerm: String? {
        AO3TagAutocomplete.freeTypedTerm(
            term: term,
            suggestions: suggestions,
            chosen: values
        )
    }

    private enum SuggestionBadge {
        case canonical
        case postsAsTyped
    }

    @ViewBuilder
    private func suggestionRow(
        name: String,
        badge: SuggestionBadge,
        workCount: Int? = nil,
        isLast: Bool
    ) -> some View {
        Button {
            add(name)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    badgeLine(badge)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Drawn only when AO3 actually sent a figure — today it never
                // does. See the type comment: no dash, no zero, no column.
                if let workCount {
                    Text(workCount.formatted())
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(name)")
        .accessibilityValue(badge == .canonical ? "canonical tag" : "posts as typed")
        if !isLast {
            SubjectRowSeparator()
        }
    }

    @ViewBuilder
    private func badgeLine(_ badge: SuggestionBadge) -> some View {
        switch badge {
        case .canonical:
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                Text("Canonical")
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(10.5 * 0.03)
            }
            .foregroundStyle(.green)
        case .postsAsTyped:
            Text("Posts as typed")
                .font(.system(size: 10.5))
                .foregroundStyle(.orange)
        }
    }

    private var footnote: some View {
        Text("AO3's autocomplete offers only its canonical tags, and does not return "
            + "how many works carry each one, so no counts are shown. A tag that is "
            + "not canonical still posts as typed — that is how new tags get made.")
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private var optionsPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                if index > 0 { SubjectRowSeparator() }
                let isOn = values.contains(option.value)
                SubjectFormRow(label: option.title, action: { toggle(option, isOn: isOn) }) {
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.accent)
                    }
                }
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
        .subjectPanel()
    }

    /// Order kept as the reader chose, as the `Toggle` list it replaces did:
    /// appended on, removed off.
    private func toggle(_ option: AO3FormOption, isOn: Bool) {
        if isOn {
            values.removeAll { $0 == option.value }
        } else if !values.contains(option.value) {
            values.append(option.value)
        }
    }

    private func loadSuggestions(kind: AO3TagKind) async {
        let key = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        errorMessage = nil
        if key.isEmpty {
            suggestions = []
            return
        }
        if let cached = cache[key] {
            suggestions = cached.filter { !values.contains($0.name) }
            return
        }
        // Left standing rather than cleared: the stale list for a prefix of this
        // term is closer to the answer than an empty panel, and clearing it made
        // the card blink on every keystroke.
        do {
            let loaded = try await AO3TagAutocomplete.suggest(kind: kind, term: term)
            guard !Task.isCancelled else { return }
            cache[key] = loaded
            suggestions = loaded.filter { !values.contains($0.name) }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            suggestions = []
            errorMessage = "Suggestions unavailable. You can still add a tag by name."
        }
    }

    private func add(_ name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if !values.contains(value) { values.append(value) }
        term = ""
    }
}
