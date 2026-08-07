import SwiftUI

/// The shared AO3 work-filter form: sort, rating, warnings, categories, crossovers,
/// completion, word count, language, and include/exclude tag pickers. Used by the
/// Search tab's inspector and by Browse → Category → Fandom → Works.
///
/// Pure UI over a bound `AO3SearchFilters`: the host runs the actual search via
/// `onApply` and decides what "reset" means via `onReset` (Search clears everything;
/// Browse resets back to the page's fixed fandom).
struct AO3FilterPanel: View {
    /// How the panel applies. `.search` re-runs an AO3 query (Search tab, Browse →
    /// Fandom); `.refine` narrows the already-loaded works on the page in place, so it
    /// hides the facets that need a fresh query (Sort, Crossover, Updated) and its
    /// primary button just confirms rather than searching.
    enum Mode { case search, refine }

    @Environment(ThemeManager.self) private var theme

    @Binding var filters: AO3SearchFilters
    var mode: Mode = .search
    /// Whether "Best Match" is an option. AO3's tag listing — Browse's endpoint —
    /// has no relevance ordering at all: its sort menu runs Creator … Bookmarks and
    /// it defaults to Date Updated. Offering Best Match there would send no
    /// `sort_column`, AO3 would order by Date Updated anyway, and the panel would
    /// sit there claiming a sort that isn't happening.
    var allowsRelevanceSort: Bool = true
    /// Show the Fandoms include/exclude picker. Hidden in Browse, where the page's
    /// fandom is fixed and shouldn't be edited away.
    var showFandomPicker: Bool = true
    /// Whether the Reset button is offered (the host owns the baseline it resets to).
    var canReset: Bool
    /// Run the search with the current filters.
    var onApply: () -> Void
    /// Save the current filters as a named Saved Search. When nil (e.g. Browse), no
    /// Save action is shown.
    var onSave: (() -> Void)?
    /// Clear filters back to the host's baseline.
    var onReset: () -> Void

    var body: some View {
        Form {
            // Group so .appThemedRows() reaches every section's rows (it doesn't
            // propagate from the Form container, only from a Group/Section/ForEach).
            Group {
                Section {
                    // Sort needs AO3 to re-order results, so it only appears when the panel
                    // actually issues a query.
                    if mode == .search {
                        Picker("Sort by", selection: $filters.sort) {
                            ForEach(sortOptions) { Text($0.title).tag($0) }
                        }
                        .onChange(of: filters.sort) { _, newValue in
                            // Picking a column re-seeds the direction to the one a
                            // reader expects from it (A-Z for names, most-first for
                            // counts). Still overridable right below.
                            filters.sortDirection = newValue.naturalDirection
                        }
                        // Relevance has no meaningful direction — AO3 orders by score.
                        if filters.sort != .relevance {
                            Picker("Order", selection: $filters.sortDirection) {
                                ForEach(AO3SearchFilters.SortDirection.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    Picker("Rating", selection: $filters.rating) {
                        ForEach(AO3SearchFilters.Rating.searchCases) { Text($0.title).tag($0) }
                    }
                    .onChange(of: filters.rating) { oldValue, newValue in
                        if oldValue == .any, newValue != .any {
                            // A specific rating starts exact and excludes unrated works;
                            // the separate toggle lets the reader opt them back in.
                            filters.ratingMatch = .exact
                            filters.includeNotRated = false
                        } else if newValue == .any {
                            filters.ratingMatch = .exact
                        }
                    }
                    if filters.rating != .any {
                        Picker("Match", selection: $filters.ratingMatch) {
                            ForEach(AO3SearchFilters.RatingMatch.allCases) {
                                Text($0.title).tag($0)
                            }
                        }
                    }
                    Toggle("Include Not Rated", isOn: $filters.includeNotRated)
                }

                Section("Warnings") {
                    ForEach(AO3SearchFilters.Warning.allCases) { warning in
                        cyclingFacetRow(warning.title, state: warningState(warning)) {
                            cycle(warning)
                        }
                    }
                }

                Section("Categories") {
                    ForEach(AO3SearchFilters.Category.allCases) { category in
                        cyclingFacetRow(category.title, state: categoryState(category)) {
                            cycle(category)
                        }
                    }
                }

                Section {
                    // Crossover status isn't carried on a blurb, so it's query-only.
                    if mode == .search {
                        Picker("Crossovers", selection: $filters.crossover) {
                            ForEach(AO3SearchFilters.Crossover.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    Picker("Completion", selection: $filters.completion) {
                        ForEach(AO3SearchFilters.Completion.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Chapters", selection: $filters.chapterCount) {
                        ForEach(AO3SearchFilters.ChapterCount.allCases) { Text($0.title).tag($0) }
                    }
                }

                // Title/creator are AO3's own fields, distinct from the free-text
                // query — which also matches summaries and tags, so an author
                // searched through it comes back far noisier.
                if mode == .search {
                    Section("Title & creator") {
                        // AO3 pseuds are case-sensitive-looking and rarely start
                        // capitalized, so autocapitalization gets in the way —
                        // but the modifier is iOS-only, like the keyboard types
                        // used elsewhere in this panel.
                        TextField("Title", text: $filters.title)
                        TextField("Creator", text: $filters.creators)
                        #if !os(macOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        #endif
                    }
                }

                Section("Word count") {
                    numberRange(from: $filters.wordsFrom, to: $filters.wordsTo)
                }

                // AO3 accepts the same range grammar on each of these.
                if mode == .search {
                    Section("Hits") {
                        numberRange(from: $filters.hitsFrom, to: $filters.hitsTo)
                    }
                    Section("Kudos") {
                        numberRange(from: $filters.kudosFrom, to: $filters.kudosTo)
                    }
                    Section("Comments") {
                        numberRange(from: $filters.commentsFrom, to: $filters.commentsTo)
                    }
                    Section("Bookmarks") {
                        numberRange(from: $filters.bookmarksFrom, to: $filters.bookmarksTo)
                    }
                }

                Section {
                    // "Updated within" filters on a date AO3 computes; not derivable from a blurb.
                    if mode == .search {
                        Picker("Updated", selection: $filters.updated) {
                            ForEach(AO3SearchFilters.Updated.allCases) { Text($0.title).tag($0) }
                        }
                        // Absolute bounds on the same axis as the picker above —
                        // AO3 filters both on `revised_at` and ANDs them, so the
                        // footer says so rather than letting a reader guess why
                        // "Past week" plus a 2020 range returns nothing.
                        dateBound("After", date: $filters.dateFrom)
                        dateBound("Before", date: $filters.dateTo)
                    }
                    Picker("Language", selection: $filters.language) {
                        ForEach(AO3SearchFilters.Language.allCases) { Text($0.title).tag($0) }
                    }
                }

                tagSection

                Section {
                    Button(action: onApply) {
                        // Refine narrows live as facets change, so its button just confirms;
                        // search needs a query/filter before it can run.
                        Label(mode == .refine ? "Done" : "Apply Filters",
                              systemImage: mode == .refine ? "checkmark" : "magnifyingglass")
                    }
                    .disabled(mode == .search && !filters.isSearchable)

                    if let onSave {
                        Button(action: onSave) {
                            Label("Save Search…", systemImage: "bookmark")
                        }
                        .disabled(!filters.isSearchable)
                    }

                    if canReset {
                        Button(role: .destructive, action: onReset) {
                            Label("Reset Filters", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
    }

    private var tagSection: some View {
        Section {
            if showFandomPicker {
                TagSelectField(title: "Fandoms", kind: .fandom,
                               included: $filters.fandom, excluded: $filters.excludedFandoms)
            }
            TagSelectField(title: "Characters", kind: .character,
                           included: $filters.characters, excluded: $filters.excludedCharacters,
                           fandomContext: selectedFandoms)
            TagSelectField(title: "Relationships", kind: .relationship,
                           included: $filters.relationships, excluded: $filters.excludedRelationships,
                           fandomContext: selectedFandoms)
            TagSelectField(title: "Additional Tags", kind: .freeform,
                           included: $filters.additionalTags, excluded: $filters.excludedAdditionalTags,
                           fandomContext: selectedFandoms)
        } header: {
            Text("Tags")
        } footer: {
            Text("Tap a tag once to include it, twice to exclude it, and a third time to clear it.")
        }
    }

    /// The fandoms currently chosen in the filters, used to seed the other tag pickers
    /// with that fandom's popular tags.
    private var sortOptions: [AO3SearchFilters.Sort] {
        allowsRelevanceSort
            ? AO3SearchFilters.Sort.allCases
            : AO3SearchFilters.Sort.allCases.filter { $0 != .relevance }
    }

    private var selectedFandoms: [String] {
        filters.fandom.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Facet rows (warnings / categories)

    /// A tappable multi-select facet row matching the tag pickers' three states.
    /// A From/To pair for one of AO3's numeric range fields. Five sections need
    /// the identical shape, so they share one builder rather than repeating the
    /// platform-conditional keyboard type five times.
    /// One optional date bound. `DatePicker` can't bind to a `Date?`, so the
    /// toggle *is* the optionality: off means "no bound", and switching it on
    /// seeds today rather than a silent 2001 default.
    @ViewBuilder
    private func dateBound(_ title: String, date: Binding<Date?>) -> some View {
        Toggle(title, isOn: Binding(
            get: { date.wrappedValue != nil },
            set: { date.wrappedValue = $0 ? (date.wrappedValue ?? Date()) : nil }
        ))
        if let value = date.wrappedValue {
            DatePicker(
                title,
                selection: Binding(get: { value }, set: { date.wrappedValue = $0 }),
                displayedComponents: .date
            )
            .labelsHidden()
        }
    }

    @ViewBuilder
    private func numberRange(from: Binding<String>, to: Binding<String>) -> some View {
        TextField("From", text: from)
        #if !os(macOS)
            .keyboardType(.numberPad)
        #endif
        TextField("To", text: to)
        #if !os(macOS)
            .keyboardType(.numberPad)
        #endif
    }

    private func cyclingFacetRow(_ title: String, state: FilterSelectionState,
                                 toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                switch state {
                case .clear:
                    EmptyView()
                case .included:
                    Label("Include", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                case .excluded:
                    Label("Exclude", systemImage: "minus.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.appTheme.excludeColor)
                }
            }
            .contentShape(Rectangle())
            // Without this, VoiceOver splits the row into two stops — the title,
            // then a separate "Include"/"Exclude" Label — even though both live
            // inside the same Button (HIG audit T-115, adversarially verified).
            .combinedAccessibilityRow([title, state.accessibilityStatus].compactMap { $0 }.joined(separator: ", "))
        }
        .buttonStyle(.plain)
    }

    private func warningState(_ warning: AO3SearchFilters.Warning) -> FilterSelectionState {
        if filters.warnings.contains(warning) { return .included }
        if filters.excludedWarnings.contains(warning) { return .excluded }
        return .clear
    }

    private func cycle(_ warning: AO3SearchFilters.Warning) {
        switch warningState(warning).next {
        case .included:
            filters.warnings.insert(warning)
            filters.excludedWarnings.remove(warning)
        case .excluded:
            filters.warnings.remove(warning)
            filters.excludedWarnings.insert(warning)
        case .clear:
            filters.warnings.remove(warning)
            filters.excludedWarnings.remove(warning)
        }
    }

    private func categoryState(_ category: AO3SearchFilters.Category) -> FilterSelectionState {
        if filters.categories.contains(category) { return .included }
        if filters.excludedCategories.contains(category) { return .excluded }
        return .clear
    }

    private func cycle(_ category: AO3SearchFilters.Category) {
        switch categoryState(category).next {
        case .included:
            filters.categories.insert(category)
            filters.excludedCategories.remove(category)
        case .excluded:
            filters.categories.remove(category)
            filters.excludedCategories.insert(category)
        case .clear:
            filters.categories.remove(category)
            filters.excludedCategories.remove(category)
        }
    }
}
