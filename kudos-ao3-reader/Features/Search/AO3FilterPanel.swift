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
    /// The works already on the page behind a `.refine` panel — 1au's
    /// "14 of the 20 works on this page match".
    ///
    /// Refine narrows what is loaded rather than re-querying AO3, so the answer is
    /// already in memory and the line can track the facets as they are set. Empty
    /// in `.search` mode, where there is no loaded page to count and the result
    /// depends on a request that has not been made.
    var refineSource: [AO3WorkSummary] = []

    /// The panel owns its own `NavigationStack`, because a presented panel has no
    /// navigation container of its own and a bare `.toolbar` there renders nothing.
    /// Same arrangement `CommentsView` uses for the same reason, and what gets the
    /// two actions drawn as the system's circular toolbar buttons rather than a
    /// hand-rolled row.
    ///
    /// This stack is exactly why iPhone must present the panel as a `.sheet` and not
    /// an `.inspector` — see `FilterPanelPresentation`. Change one and the other
    /// stops being safe.
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                refineMatchLine
                form
            }
            .navigationTitle(mode == .refine ? "Refine" : "Filters")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar { actionButtons }
        }
    }

    /// 1au's live count, above the form. Only in refine mode, and only with a page
    /// behind it: in search mode the number depends on a request that has not been
    /// made, and inventing one would be a count the app cannot source.
    @ViewBuilder
    private var refineMatchLine: some View {
        if mode == .refine, !refineSource.isEmpty {
            Text(refineMatchText)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var refineMatchText: String {
        let total = refineSource.count
        let matching = filters.apply(to: refineSource).count
        let works = total == 1 ? "work" : "works"
        return "\(matching) of the \(total) \(works) on this page match"
    }

    /// Reset top-left, Apply top-right — the ends of the bar, where a sheet's
    /// dismiss and confirm live everywhere else in the app. Both used to be rows at
    /// the *bottom* of the form, which meant scrolling past every facet to run the
    /// search you had just configured.
    ///
    /// Icons rather than words so they read as chrome, and because the system draws
    /// a toolbar item's own circular background on iOS 26 — matching the Comments
    /// sheet without reimplementing it.
    ///
    /// Reset is disabled rather than hidden: a control that appears and disappears
    /// as filters change makes the bar's contents move under the user's thumb.
    @ToolbarContentBuilder
    private var actionButtons: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .destructive, action: onReset) {
                Image(systemName: "arrow.counterclockwise")
            }
            .disabled(!canReset)
            .accessibilityLabel("Reset filters")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(action: onApply) {
                // Refine narrows live as facets change, so its button just confirms;
                // search needs a query/filter before it can run.
                Image(systemName: mode == .refine ? "checkmark" : "magnifyingglass")
            }
            // 1au draws this one ACCENT-FILLED with a dark glyph, against the
            // leading Reset's plain glass — the confirm is the only filled circle
            // on the board. Reset stays unfilled so the pair reads as one primary
            // and one secondary rather than two equal buttons.
            .buttonStyle(.borderedProminent)
            .disabled(mode == .search && !filters.isSearchable)
            .accessibilityLabel(mode == .refine ? "Done" : "Apply filters")
        }
    }

    /// 1au draws every group label as `600 11px`, `.07em` tracking, uppercase, at
    /// 55% — which is exactly `SubjectFieldLabel`'s `.formGroup` style, the one the
    /// form artboards use over a group of rows. A bare `Section("Warnings")` gave
    /// sentence case with no tracking, and that mismatch was the loudest remaining
    /// "this is the old app" signal on the panel.
    private func groupLabel(_ text: String) -> some View {
        SubjectFieldLabel(text: text, style: .formGroup)
    }

    private var form: some View {
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
                    // Both stay in refine: artboard 1au draws "Match — Rating+" and
                    // "Include Not Rated" on the Refine panel itself, and
                    // `AO3SummaryFilter.ratingMatches` now reads them off the blurb's
                    // rating text rather than ignoring them.
                    if filters.rating != .any {
                        Picker("Match", selection: $filters.ratingMatch) {
                            ForEach(AO3SearchFilters.RatingMatch.allCases) {
                                Text($0.title).tag($0)
                            }
                        }
                    }
                    Toggle("Include Not Rated", isOn: $filters.includeNotRated)
                }

                Section {
                    ForEach(AO3SearchFilters.Warning.allCases) { warning in
                        cyclingFacetRow(warning.title, state: warningState(warning)) {
                            cycle(warning)
                        }
                    }
                } header: {
                    groupLabel("Warnings")
                }

                Section {
                    ForEach(AO3SearchFilters.Category.allCases) { category in
                        cyclingFacetRow(category.title, state: categoryState(category)) {
                            cycle(category)
                        }
                    }
                } header: {
                    groupLabel("Categories")
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
                    // 1au draws "Chapters — Any" too, and `chapterCountMatches` reads
                    // the blurb's own "posted/total" text, so this narrows in refine
                    // as well as in search.
                    Picker("Chapters", selection: $filters.chapterCount) {
                        ForEach(AO3SearchFilters.ChapterCount.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    // Artboard 1aq says this out loud, and the reason was only a
                    // code comment until now: these two re-run the search rather
                    // than narrowing what is already on screen, and a filter that
                    // costs a round trip should say so before it is tapped.
                    if mode == .search {
                        Text("Crossover status and completion are not carried on a search result, "
                            + "so both need AO3 to answer the query.")
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
                    NavigationLink {
                        FilterLanguagePicker(selection: $filters.language)
                    } label: {
                        LabeledContent("Language", value: filters.language.title)
                    }
                }

                tagSection

                typedSections

                // Apply and Reset live in `actionHeader`; only Save is left here,
                // because it is a rarer, more deliberate action than either.
                if let onSave {
                    Section {
                        Button(action: onSave) {
                            Label("Save Search…", systemImage: "bookmark")
                        }
                        .disabled(!filters.isSearchable)
                    }
                }
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
    }

    /// Everything you have to *type*, last — after the tag pickers.
    ///
    /// The rest of the panel is tappable: pickers, toggles and facet rows you can
    /// run down with a thumb. These five ask for a keyboard, and sitting them in
    /// the middle put a keyboard between the reader and the facets below it. They
    /// are also the least-used controls here, which is the other half of the
    /// argument for the bottom.
    @ViewBuilder
    private var typedSections: some View {
        // Title/creator are AO3's own fields, distinct from the free-text query —
        // which also matches summaries and tags, so an author searched through it
        // comes back far noisier. The only *text* fields in this group.
        if mode == .search {
            Section {
                // AO3 pseuds are case-sensitive-looking and rarely start
                // capitalized, so autocapitalization gets in the way — but the
                // modifier is iOS-only, like the keyboard types below.
                TextField("Title", text: $filters.title)
                TextField("Creator", text: $filters.creators)
                #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                #endif
            } header: {
                groupLabel("Title & creator")
            }
        }

        Section {
            FilterRangeSlider(
                from: $filters.wordsFrom,
                to: $filters.wordsTo,
                defaultMaximum: FilterRangeSlider.wordCountMaximum
            )
        } header: {
            groupLabel("Word count")
        } footer: {
            if mode == .refine {
                openBoundFooter
            }
        }

        // AO3 accepts the same range grammar on each of these. Refine hides
        // them — they aren't on a loaded blurb — and keeps word count.
        if mode == .search {
            Section {
                FilterRangeSlider(
                    from: $filters.hitsFrom,
                    to: $filters.hitsTo,
                    defaultMaximum: FilterRangeSlider.hitsMaximum
                )
            } header: {
                groupLabel("Hits")
            }
            Section {
                FilterRangeSlider(
                    from: $filters.kudosFrom,
                    to: $filters.kudosTo,
                    defaultMaximum: FilterRangeSlider.kudosMaximum
                )
            } header: {
                groupLabel("Kudos")
            }
            Section {
                FilterRangeSlider(
                    from: $filters.commentsFrom,
                    to: $filters.commentsTo,
                    defaultMaximum: FilterRangeSlider.commentsMaximum
                )
            } header: {
                groupLabel("Comments")
            }
            Section {
                FilterRangeSlider(
                    from: $filters.bookmarksFrom,
                    to: $filters.bookmarksTo,
                    defaultMaximum: FilterRangeSlider.bookmarksMaximum
                )
            } header: {
                groupLabel("Bookmarks")
            } footer: {
                openBoundFooter
            }
        }
    }

    private var openBoundFooter: Text {
        Text(
            "Leave a handle where it is for an open bound. "
                + "AO3 reads one-sided ranges as “more than” and “fewer than”."
        )
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
            groupLabel("Tags")
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
    private func cyclingFacetRow(_ title: String, state: FilterSelectionState,
                                 toggle: @escaping () -> Void) -> some View {
        let row = Button(action: toggle) {
            HStack {
                Text(title)
                    .foregroundStyle(state == .excluded ? Color.secondary : Color.primary)
                    .strikethrough(state == .excluded, color: theme.appTheme.excludeColor.opacity(0.7))
                Spacer()
                switch state {
                case .clear:
                    EmptyView()
                case .included:
                    Label("Include", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.appTheme.includeColor)
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
        // Only override the themed cell when included — an EmptyView background
        // would wipe `.appThemedRows()` on the other states.
        if state == .included {
            row.listRowBackground(theme.appTheme.includeColor.opacity(0.10))
        } else {
            row
        }
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
