import SwiftUI

/// A filter-panel row that searches AO3 tags and gives each selection three
/// states: clear → include → exclude → clear.
struct TagSelectField: View {
    let title: String
    let kind: AO3TagKind
    @Binding var included: String
    @Binding var excluded: String
    /// Fandoms currently included in the filters; lets the picker show that
    /// fandom's most popular tags by default.
    var fandomContext: [String] = []

    @State private var showPicker = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var includedTags: [String] {
        Self.tags(in: included)
    }

    private var excludedTags: [String] {
        Self.tags(in: excluded)
    }

    static func selectionSummary(includedCount: Int, excludedCount: Int) -> String? {
        (includedCount == 0 && excludedCount == 0) ? "Add" : nil
    }

    static func buttonAccessibilityLabel(
        title: String,
        included: [String],
        excluded: [String]
    ) -> String {
        if included.isEmpty, excluded.isEmpty {
            return "\(title), Add"
        }
        var parts: [String] = []
        if !included.isEmpty { parts.append("\(included.count) included") }
        if !excluded.isEmpty { parts.append("\(excluded.count) excluded") }
        return "\(title), \(parts.joined(separator: ", "))"
    }

    private var selectionSummary: String? {
        Self.selectionSummary(includedCount: includedTags.count, excludedCount: excludedTags.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showPicker = true
            } label: {
                HStack {
                    if dynamicTypeSize.isAccessibilitySize {
                        // What is chosen under the field's name: beside it the name broke by
                        // syllable at the accessibility sizes ("Rela- / tion- / ships").
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .foregroundStyle(.primary)
                            if let summary = selectionSummary {
                                Text(summary)
                                    .foregroundStyle(.secondaryInk)
                            }
                        }
                        Spacer(minLength: 8)
                    } else {
                        Text(title)
                            .foregroundStyle(.primary)
                        Spacer()
                        if let summary = selectionSummary {
                            Text(summary)
                                .foregroundStyle(.secondaryInk)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.buttonAccessibilityLabel(
                title: title, included: includedTags, excluded: excludedTags
            ))

            if !includedTags.isEmpty || !excludedTags.isEmpty {
                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(includedTags, id: \.self) { tag in
                        FilterTagChip(tag: tag, state: .included) {
                            cycle(tag)
                        }
                    }
                    ForEach(excludedTags, id: \.self) { tag in
                        FilterTagChip(tag: tag, state: .excluded) {
                            cycle(tag)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .sheet(isPresented: $showPicker) {
            TagPickerView(
                title: title,
                kind: kind,
                included: includedBinding,
                excluded: excludedBinding,
                fandomContext: fandomContext
            )
        }
    }

    private func cycle(_ tag: String) {
        var includedSet = Set(includedTags)
        var excludedSet = Set(excludedTags)
        let current: FilterSelectionState = includedSet.contains(tag)
            ? .included
            : excludedSet.contains(tag) ? .excluded : .clear
        switch current.next {
        case .included:
            includedSet.insert(tag)
            excludedSet.remove(tag)
        case .excluded:
            includedSet.remove(tag)
            excludedSet.insert(tag)
        case .clear:
            includedSet.remove(tag)
            excludedSet.remove(tag)
        }
        included = includedSet.sorted().joined(separator: ", ")
        excluded = excludedSet.sorted().joined(separator: ", ")
    }

    private var includedBinding: Binding<Set<String>> {
        Binding(
            get: { Set(includedTags) },
            set: { included = $0.sorted().joined(separator: ", ") }
        )
    }

    private var excludedBinding: Binding<Set<String>> {
        Binding(
            get: { Set(excludedTags) },
            set: { excluded = $0.sorted().joined(separator: ", ") }
        )
    }

    private static func tags(in value: String) -> [String] {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// Pure board copy helpers for `TagPickerView` (`Filter-Tags` board).
enum TagPickerCopy {
    static func resultsSectionHeader(query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Results" : "Matching “\(trimmed)”"
    }

    static func popularSectionHeader(fandom: String) -> String {
        "Popular in \(fandom)"
    }

    static func noResultsText(query: String) -> String {
        "No tags found for “\(query)”."
    }

    static func searchPromptText(title: String) -> String {
        "Type above to search AO3 \(title.lowercased())."
    }

    static func fandomSuggestionHint(title: String) -> String {
        "Choose a fandom to see its most-used \(title.lowercased()) here."
    }

    static func rowSymbol(for kind: AO3TagKind) -> String {
        switch kind {
        case .fandom: "books.vertical"
        case .character: "person"
        case .relationship: "heart"
        case .freeform, .tag: "tag"
        }
    }
}

/// A searchable tag picker backed by AO3 autocomplete. Repeated taps cycle a
/// result through include, exclude, and clear states.
struct TagPickerView: View {
    let title: String
    let kind: AO3TagKind
    @Binding var included: Set<String>
    @Binding var excluded: Set<String>
    /// Included fandoms used to seed the default list with popular tags.
    var fandomContext: [String] = []
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme

    @State private var query = ""
    @State private var results: [String] = []
    @State private var isSearching = false
    @State private var popular: [String] = []
    @State private var loadingPopular = false

    private var hasFandomContext: Bool {
        kind != .fandom && !fandomContext.isEmpty
    }

    private var isSearchEmpty: Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var sortedIncluded: [String] {
        included.sorted()
    }

    private var sortedExcluded: [String] {
        excluded.sorted()
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondaryInk)
            .textCase(nil)
    }

    var body: some View {
        NavigationStack {
            List {
                // Group so .appThemedRows() reaches every section's rows (it doesn't
                // propagate from the List container, only from a Group/Section/ForEach).
                Group {
                    if !sortedIncluded.isEmpty {
                        Section {
                            FlowLayout(spacing: 6, rowSpacing: 6) {
                                ForEach(sortedIncluded, id: \.self) { tag in
                                    FilterTagChip(tag: tag, state: .included) {
                                        cycle(tag)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        } header: {
                            sectionHeader("Included")
                        }
                    }

                    if !sortedExcluded.isEmpty {
                        Section {
                            FlowLayout(spacing: 6, rowSpacing: 6) {
                                ForEach(sortedExcluded, id: \.self) { tag in
                                    FilterTagChip(tag: tag, state: .excluded) {
                                        cycle(tag)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        } header: {
                            sectionHeader("Excluded")
                        }
                    }

                    if isSearchEmpty, hasFandomContext {
                        Section {
                            if loadingPopular {
                                loadingRow("Loading…")
                            } else if popular.isEmpty {
                                searchPrompt
                            } else {
                                tagRows(popular)
                            }
                        } header: {
                            sectionHeader(TagPickerCopy.popularSectionHeader(fandom: fandomContext[0]))
                        }
                    } else {
                        Section {
                            if isSearching {
                                loadingRow("Searching…")
                            } else if isSearchEmpty {
                                emptyQueryPrompt
                            } else if results.isEmpty {
                                Text(TagPickerCopy.noResultsText(query: query))
                                    .foregroundStyle(.secondaryInk)
                            } else {
                                tagRows(results)
                            }
                        } header: {
                            sectionHeader(TagPickerCopy.resultsSectionHeader(query: query))
                        }
                    }
                }
                .appThemedRows()
            }
            .appThemedScroll()
            .modifier(WorksFilterSheetGround())
            .navigationTitle(title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search \(title)"
                )
            #else
                .searchable(text: $query, prompt: "Search \(title)")
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "checkmark")
                        }
                        .sheetConfirmStyle()
                        .accessibilityLabel("Done")
                    }
                }
                .task { await loadPopular() }
                .task(id: query) { await runSearch() }
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var searchPrompt: some View {
        Text(TagPickerCopy.searchPromptText(title: title))
            .foregroundStyle(.secondaryInk)
    }

    /// 1av's opening state when nothing has been typed yet.
    ///
    /// With a fandom set the screen opens on that fandom's popular tags, which is
    /// "the difference between a picker you can browse and one you have to already
    /// know the answer to". With none there is nothing to suggest — so this says
    /// why, rather than repeating the bare prompt, which in that position reads
    /// like the suggestions failed to load. Fandom itself has no parent to draw
    /// suggestions from, so it keeps the plain prompt.
    @ViewBuilder
    private var emptyQueryPrompt: some View {
        if kind == .fandom || !fandomContext.isEmpty {
            searchPrompt
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(TagPickerCopy.searchPromptText(title: title))
                Text(TagPickerCopy.fandomSuggestionHint(title: title))
                    .font(.footnote)
            }
            .foregroundStyle(.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Placeholder tag rows shown while suggestions are being fetched — the shape of
    /// the rows that will replace them, instead of an inline spinner.
    private func loadingRow(_: String) -> some View {
        ForEach([220.0, 160.0, 190.0, 130.0], id: \.self) { width in
            SkeletonTextLine(height: 15, width: width)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .skeletonShimmer()
        }
    }

    @ViewBuilder
    private func tagRows(_ tags: [String]) -> some View {
        ForEach(tags, id: \.self) { tag in
            let state = state(of: tag)
            let row = Button {
                cycle(tag)
            } label: {
                HStack(spacing: 12) {
                    SettingsIconTile(color: .gray, systemImage: TagPickerCopy.rowSymbol(for: kind))
                    Text(tag)
                        .foregroundStyle(
                            state == .excluded ? AnyShapeStyle(.secondaryInk) : AnyShapeStyle(Color.primary)
                        )
                        .strikethrough(state == .excluded, color: theme.appTheme.excludeColor.opacity(0.7))
                    Spacer()
                    selectionLabel(for: state)
                }
                .contentShape(Rectangle())
                // Same shape as AO3FilterPanel's cyclingFacetRow (a Label nested in a
                // Button splits into two VoiceOver stops instead of combining) — the
                // fix mirrors that row's.
                .combinedAccessibilityRow([tag, state.accessibilityStatus].compactMap { $0 }.joined(separator: ", "))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Tap to \(state.nextActionLabel.lowercased()) this tag")
            if state == .included {
                row.listRowBackground(theme.appTheme.includeColor.opacity(0.10))
            } else {
                row
            }
        }
    }

    @ViewBuilder
    private func selectionLabel(for state: FilterSelectionState) -> some View {
        switch state {
        case .clear:
            EmptyView()
        case .included:
            Label("Included", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.appTheme.includeColor)
        case .excluded:
            Label("Excluded", systemImage: "minus.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.appTheme.excludeColor)
        }
    }

    private func state(of tag: String) -> FilterSelectionState {
        if included.contains(tag) { return .included }
        if excluded.contains(tag) { return .excluded }
        return .clear
    }

    private func cycle(_ tag: String) {
        switch state(of: tag).next {
        case .included:
            included.insert(tag)
            excluded.remove(tag)
        case .excluded:
            included.remove(tag)
            excluded.insert(tag)
        case .clear:
            clear(tag)
        }
    }

    private func clear(_ tag: String) {
        included.remove(tag)
        excluded.remove(tag)
    }

    private func loadPopular() async {
        guard popular.isEmpty, hasFandomContext, let fandom = fandomContext.first else { return }
        loadingPopular = true
        popular = await (try? AO3Client.shared.popularTags(forFandom: fandom, kind: kind)) ?? []
        loadingPopular = false
    }

    private func runSearch() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { results = []; isSearching = false; return }
        isSearching = true
        // Debounce: `.task(id:)` cancels the prior run when the query changes again.
        try? await Task.sleep(for: .milliseconds(300))
        if Task.isCancelled { return }
        do {
            let found = try await AO3Client.shared.autocompleteTags(kind: kind, term: term)
            if !Task.isCancelled { results = found }
        } catch {
            if !Task.isCancelled { results = [] }
        }
        if !Task.isCancelled { isSearching = false }
    }
}

/// A tappable capsule for an included or excluded filter tag. Tapping continues
/// the same Include → Exclude → Clear cycle as the result row.
private struct FilterTagChip: View {
    let tag: String
    let state: FilterSelectionState
    let onCycle: () -> Void

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var color: Color {
        state == .excluded ? theme.appTheme.excludeColor : theme.appTheme.includeColor
    }

    private var symbol: String {
        state == .excluded ? "minus" : "checkmark"
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .accessibilityHidden(true)
            Text(tag)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                .strikethrough(state == .excluded, color: color.opacity(0.7))
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minHeight: 30)
        .foregroundStyle(color)
        .background(
            color.opacity(state == .excluded ? 0.08 : 0.12),
            in: SubjectMetrics.controlShape(dynamicTypeSize)
        )
        // A nested Button inside a Form/List row is coalesced with the row's
        // primary Button on iOS, which made tag-chip taps open the picker instead
        // of cycling. A direct tap gesture keeps the chip's action independent.
        .layoutFreeHitTarget(action: onCycle)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(state == .excluded ? "Excluded" : "Included"): \(tag)")
        .accessibilityHint("Tap to \(state.nextActionLabel.lowercased()) this tag")
        .accessibilityAction(named: Text("Cycle tag"), onCycle)
    }
}
