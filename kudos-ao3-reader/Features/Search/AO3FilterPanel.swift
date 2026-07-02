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

    @Binding var filters: AO3SearchFilters
    var mode: Mode = .search
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
                        ForEach(AO3SearchFilters.Sort.allCases) { Text($0.title).tag($0) }
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
            }

            Section("Word count") {
                TextField("From", text: $filters.wordsFrom)
                    #if !os(macOS)
                    .keyboardType(.numberPad)
                    #endif
                TextField("To", text: $filters.wordsTo)
                    #if !os(macOS)
                    .keyboardType(.numberPad)
                    #endif
            }

            Section {
                // "Updated within" filters on a date AO3 computes; not derivable from a blurb.
                if mode == .search {
                    Picker("Updated", selection: $filters.updated) {
                        ForEach(AO3SearchFilters.Updated.allCases) { Text($0.title).tag($0) }
                    }
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

    @ViewBuilder
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
    private var selectedFandoms: [String] {
        filters.fandom.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Facet rows (warnings / categories)

    /// A tappable multi-select facet row matching the tag pickers' three states.
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
                        .foregroundStyle(.red)
                }
            }
            .contentShape(Rectangle())
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
