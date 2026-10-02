import SwiftUI

/// The shared AO3 work-filter form: sort, rating, warnings, categories, crossovers,
/// completion, word count, language, and include/exclude tag pickers. Used by the
/// Search tab's inspector, by Browse → Category → Fandom → Works, and — with
/// `worksSort` set — by the author works list's one sort-and-filter sheet.
///
/// Pure UI over a bound `AO3SearchFilters`: the host runs the actual search via
/// `onApply` and decides what "reset" means via `onReset` (Search clears everything;
/// Browse resets back to the page's fixed fandom).
///
/// One showing of the works-index sort. Appearing reseeds from the applied
/// sort, and Apply posts the draft only when this showing changed it.
struct WorksSortPresentation: Equatable {
    var draft: AO3WorksSort
    private var seeded: AO3WorksSort

    init(applied: AO3WorksSort?) {
        draft = applied ?? .default
        seeded = draft
    }

    mutating func appear(applied: AO3WorksSort?) {
        draft = applied ?? .default
        seeded = draft
    }

    var sortToCommit: AO3WorksSort? { draft == seeded ? nil : draft }
}

struct AO3FilterPanel: View {
    /// How the panel applies. `.search` re-runs an AO3 query (Search tab, Browse →
    /// Fandom); `.refine` narrows the already-loaded works on the page in place, so it
    /// hides the facets that need a fresh query (Sort, Crossover, Updated) and its
    /// primary button just confirms rather than searching.
    ///
    /// The author works list is the exception that still refetches: it passes
    /// `worksSort`, and Apply commits that draft. Those nine columns are AO3's
    /// works-index sort, not Search's Best Match menu, which stays hidden here.
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
    /// The host's own count of `refineSource` rows it shows, when its rule is not
    /// `filters.apply` alone (Subscriptions keeps rows it knows nothing about yet —
    /// `AO3SubscriptionsRefine`). Nil counts with `filters.apply`.
    var refineMatchCount: Int?
    /// Rows the host shows but could not judge yet (Subscriptions' index-only
    /// rows). Not in `refineMatchCount`; the line names them separately.
    var refinePendingCount = 0
    /// 1v's works-index sort, when this panel is that sheet. Nil on Search and
    /// Browse, which have their own sort and must not grow a second one.
    ///
    /// Held as a draft: a live binding would refetch on every tap of the menu.
    /// Refine facets stay on `filters` and still apply as they are tapped,
    /// because those cost no request.
    var worksSort: AO3WorksSort?
    /// Commits `worksSort` when Apply finds it changed. The host refetches.
    var onApplyWorksSort: ((AO3WorksSort) -> Void)?
    @State private var sortPresentation: WorksSortPresentation

    init(
        filters: Binding<AO3SearchFilters>,
        mode: Mode = .search,
        allowsRelevanceSort: Bool = true,
        showFandomPicker: Bool = true,
        canReset: Bool,
        onApply: @escaping () -> Void,
        onSave: (() -> Void)? = nil,
        onReset: @escaping () -> Void,
        refineSource: [AO3WorkSummary] = [],
        refineMatchCount: Int? = nil,
        refinePendingCount: Int = 0,
        worksSort: AO3WorksSort? = nil,
        onApplyWorksSort: ((AO3WorksSort) -> Void)? = nil
    ) {
        _filters = filters
        self.mode = mode
        self.allowsRelevanceSort = allowsRelevanceSort
        self.showFandomPicker = showFandomPicker
        self.canReset = canReset
        self.onApply = onApply
        self.onSave = onSave
        self.onReset = onReset
        self.refineSource = refineSource
        self.refineMatchCount = refineMatchCount
        self.refinePendingCount = refinePendingCount
        self.worksSort = worksSort
        self.onApplyWorksSort = onApplyWorksSort
        _sortPresentation = State(initialValue: WorksSortPresentation(applied: worksSort))
    }

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
            .navigationTitle(worksSort == nil ? (mode == .refine ? "Refine" : "Filters") : "Sort and filter")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar { actionButtons }
        }
        .onAppear { sortPresentation.appear(applied: worksSort) }
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
        let matching = refineMatchCount ?? filters.apply(to: refineSource).count
        let works = total == 1 ? "work" : "works"
        let verb = matching == 1 ? "matches" : "match"
        let line = "\(matching) of the \(total) \(works) on this page \(verb)"
        return refinePendingCount > 0 ? "\(line) · \(refinePendingCount) not checked yet" : line
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
            // Clearing filters is not a delete: no destructive role.
            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise")
            }
            .disabled(!canReset)
            .accessibilityLabel("Reset filters")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(action: confirm) {
                // Refine narrows live as facets change, so its button just confirms;
                // search needs a query/filter before it can run. The works sheet's
                // checkmark also commits the sort draft, which is the refetch.
                Image(systemName: mode == .refine ? "checkmark" : "magnifyingglass")
            }
            // 1au draws this one ACCENT-FILLED with a dark glyph, against the
            // leading Reset's plain glass — the confirm is the only filled circle
            // on the board. Reset stays unfilled so the pair reads as one primary
            // and one secondary rather than two equal buttons.
            .buttonStyle(.borderedProminent)
            .prominentLabel()
            .disabled(mode == .search && !filters.isSearchable)
            .accessibilityLabel(confirmLabel)
        }
    }

    /// Apply posts a sort only when this showing changed it. `onAppear` already
    /// reseeded a cancelled draft. Reset still clears only the facets.
    private func confirm() {
        if worksSort != nil, let sort = sortPresentation.sortToCommit {
            onApplyWorksSort?(sort)
        }
        onApply()
    }

    /// The works sheet's chips are the completion AO3 is asked for. The page
    /// facet is the other control, and the two together can empty the list.
    static func showsPageCompletionFacet(worksSort: AO3WorksSort?) -> Bool {
        worksSort == nil
    }

    private var confirmLabel: String {
        if worksSort != nil { return "Apply" }
        return mode == .refine ? "Done" : "Apply filters"
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
                worksSortSections
                Section {
                    // Sort needs AO3 to re-order results, so it only appears when the panel
                    // actually issues a query. Search's menu, not 1v's nine columns.
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
                    // Drawn in both modes: Refine applies Search's rule under Any
                    // too (1au.4), so the switch filters wherever it shows.
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
                    if Self.showsPageCompletionFacet(worksSort: worksSort) {
                        Picker("Completion", selection: $filters.completion) {
                            ForEach(AO3SearchFilters.Completion.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    // 1au draws "Chapters — Any" too, and `chapterCountMatches` reads
                    // the blurb's own "posted/total" text, so this narrows in refine
                    // as well as in search.
                    Picker("Chapters", selection: $filters.chapterCount) {
                        ForEach(AO3SearchFilters.ChapterCount.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    // Artboard 1aq says this out loud, and the reason was only a
                    // code comment until now: Crossovers re-runs the search rather
                    // than narrowing what is already on screen, and a filter that
                    // costs a round trip should say so before it is tapped.
                    // Completion is not in the sentence: every blurb carries it, and
                    // Refine narrows by it (`AO3SummaryFilter`).
                    if mode == .search {
                        Text("When you change crossover status, Kudos runs a new AO3 search because "
                            + "each result doesn't include it.")
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
                } footer: {
                    // The footer the comment above promises (1aq). otwarchive's
                    // `WorkQuery` turns both into `revised_at` ranges and ANDs them.
                    if mode == .search {
                        Text("The Updated, After, and Before choices all use the work's update date. "
                            + "A work appears only if it matches every date choice.")
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
            "Leave either end of the slider at its starting position if you don't want a minimum "
                + "or maximum. AO3 treats one-sided ranges as “more than” or “fewer than”."
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

// MARK: - 1v works sort

extension AO3FilterPanel {
    /// 1v's sort, direction and completion, above the refine facets. The "N
    /// fields" caption sits under the chosen column, not under the row label.
    @ViewBuilder
    private var worksSortSections: some View {
        if worksSort != nil {
            Section {
                Menu {
                    Picker("Sort by", selection: worksColumnBinding) {
                        ForEach(AO3WorksSort.allColumns) { column in
                            Text(column.title).tag(column)
                        }
                    }
                } label: {
                    LabeledContent("Sort by") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(sortPresentation.draft.column.title)
                            Text(AO3WorksSort.fieldsHint)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sort by")
                .accessibilityValue(
                    "\(sortPresentation.draft.column.title), \(AO3WorksSort.fieldsHint)"
                )
                Picker("Direction", selection: $sortPresentation.draft.direction) {
                    ForEach(AO3WorksSortDirection.allCases) { direction in
                        Text(direction.title).tag(direction)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section {
                worksCompletionChips
            } header: {
                groupLabel("Completion")
            } footer: {
                Text("AO3 applies this choice to all matching works, not only the page you can see.")
            }
        }
    }

    /// Choosing a column adopts that column's own default direction, the way
    /// AO3 does when no direction is sent.
    private var worksColumnBinding: Binding<AO3WorksSortColumn> {
        Binding(
            get: { sortPresentation.draft.column },
            set: { sortPresentation.draft.select($0) }
        )
    }

    private var worksCompletionChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(AO3WorksCompletion.allCases) { option in
                Button {
                    sortPresentation.draft.completion = option
                } label: {
                    SubjectChip(
                        text: option.title,
                        style: .pill(isSelected: sortPresentation.draft.completion == option),
                        palette: theme.scopePalette
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(sortPresentation.draft.completion == option ? [.isSelected] : [])
            }
        }
        .padding(12)
    }
}
