// swiftlint:disable file_length
import SwiftUI

/// The shared AO3 work-filter form: sort, rating, warnings, categories, crossovers,
/// completion, word count, language, popularity, and include/exclude tag pickers.
/// Used by the Search tab's inspector, by Browse → Category → Fandom → Works, and —
/// with `worksSort` set — by the author works list's one sort-and-filter sheet.
///
/// Regrouped per redesign board 12 (T-493):
/// Top Active filters block, Sort, Content, Tags and text, Length and status, Popularity,
/// two-column cycling symbol chip cards, Settings-style tiles, and pinned Results bar.
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
    enum Mode { case search, refine }

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) var theme
    @ScaledMetric(relativeTo: .footnote) private var refineMatchSize: CGFloat = 12.5
    @ScaledMetric(relativeTo: .caption) var sortHintSize: CGFloat = 12

    @Binding var filters: AO3SearchFilters
    var mode: Mode = .search
    var allowsRelevanceSort: Bool = true
    var showFandomPicker: Bool = true
    var canReset: Bool
    var onApply: () -> Void
    var onSave: (() -> Void)?
    var onReset: () -> Void
    var refineSource: [AO3WorkSummary] = []
    var refineMatchCount: Int?
    var refinePendingCount = 0
    var worksSort: AO3WorksSort?
    var onApplyWorksSort: ((AO3WorksSort) -> Void)?
    var ranking: Binding<LoadedWorksRanking>?
    var totalWorks: Int?

    @State var sortPresentation: WorksSortPresentation
    #if DEBUG
    @State private var debugLanguage = false
    @State private var debugTagPicker = false
    #endif

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
        onApplyWorksSort: ((AO3WorksSort) -> Void)? = nil,
        ranking: Binding<LoadedWorksRanking>? = nil,
        totalWorks: Int? = nil
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
        self.ranking = ranking
        self.totalWorks = totalWorks
        _sortPresentation = State(initialValue: WorksSortPresentation(applied: worksSort))
    }

    // From colorScheme (ContentView sets it from the app theme), not ThemeManager: the form reads this
    // while `body` is built, and reading ThemeManager there crashes when none is in the environment.
    @Environment(\.colorScheme) private var colorScheme
    var isDark: Bool { colorScheme == .dark }

    private var resultsButtonTitle: String {
        if mode == .refine {
            let matching = refineMatchCount ?? filters.apply(to: refineSource).count
            return "Show \(matching.formatted()) \(matching == 1 ? "Work" : "Works")"
        }
        if let total = totalWorks {
            return "Show \(total.formatted()) \(total == 1 ? "Work" : "Works")"
        }
        return "Show Works"
    }

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
                .modifier(WorksFilterSheetGround())
                .toolbar { actionButtons }
                .safeAreaInset(edge: .bottom) {
                    FilterResultsBar(
                        buttonTitle: resultsButtonTitle,
                        isConfirmDisabled: mode == .search && !filters.isSearchable,
                        onSave: onSave,
                        isSaveDisabled: !filters.isSearchable,
                        onConfirm: confirm
                    )
                }
        }
        #if os(iOS)
            .modifier(ScopeSurfaceAccent())
        #endif
        .onAppear { sortPresentation.appear(applied: worksSort) }
    }

    @ViewBuilder
    private var refineMatchLine: some View {
        if mode == .refine, !refineSource.isEmpty {
            Text(refineMatchText)
                .font(.system(size: refineMatchSize))
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

    @ToolbarContentBuilder
    private var actionButtons: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Close")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(action: confirm) {
                Image(systemName: mode == .refine ? "checkmark" : "magnifyingglass")
            }
            .buttonStyle(.kudosPrimary)
            .disabled(mode == .search && !filters.isSearchable)
            .accessibilityLabel(confirmLabel)
        }
    }

    private func confirm() {
        if worksSort != nil, let sort = sortPresentation.sortToCommit {
            onApplyWorksSort?(sort)
        }
        onApply()
        dismiss()
    }

    static func showsPageCompletionFacet(worksSort: AO3WorksSort?) -> Bool {
        worksSort == nil
    }

    private var confirmLabel: String {
        if worksSort != nil { return "Apply" }
        return mode == .refine ? "Done" : "Apply filters"
    }

    func groupLabel(_ text: String) -> some View {
        SubjectFieldLabel(text: text, style: .formGroup)
    }

    private var form: some View {
        Form {
            if !activeFilterItems.isEmpty {
                Section {
                    ActiveFiltersBlock(items: activeFilterItems) {
                        onReset()
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Group {
                // MARK: 1. Sort
                worksSortSections

                if mode == .search {
                    sortSection
                }

                // MARK: 2. Content
                contentSection
                categoriesSection
                warningsSection

                // MARK: 3. Tags and text
                tagAndTextSection

                // MARK: 4. Length and status
                lengthAndStatusSection

                // MARK: 5. Popularity
                if mode == .search {
                    popularitySection
                }

                // MARK: Reset form row
                resetSection
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
        #if DEBUG
        .task {
            if DebugLaunchRoute.takePush("languagepicker") { debugLanguage = true }
            if DebugLaunchRoute.takeSheet("tagpicker") {
                try? await Task.sleep(for: .seconds(1))
                debugTagPicker = true
            }
        }
        .navigationDestination(isPresented: $debugLanguage) {
            FilterLanguagePicker(selection: $filters.language)
        }
        .sheet(isPresented: $debugTagPicker) {
            TagPickerView(
                title: "Fandoms", kind: .fandom,
                included: debugTagSet($filters.fandom), excluded: debugTagSet($filters.excludedFandoms)
            )
        }
        #endif
    }
}

// MARK: - Form Sections

extension AO3FilterPanel {
    private var sortSection: some View {
        Section {
            NavigationLink {
                SearchSortByView(
                    filters: $filters,
                    ranking: ranking,
                    allowsRelevanceSort: allowsRelevanceSort
                )
            } label: {
                HStack(spacing: 12) {
                    SettingsIconTile(
                        color: Color(red: 0x1E / 255.0, green: 0x63 / 255.0, blue: 0xC8 / 255.0),
                        systemImage: "arrow.up.arrow.down"
                    )
                    Text("Sort by")
                    Spacer()
                    Text(SearchSortBySummary.value(filters: filters, ranking: ranking?.wrappedValue))
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: filters.sort) { _, newValue in
                filters.sortDirection = newValue.naturalDirection
            }
        }
    }

    private var contentSection: some View {
        Section {
            HStack(spacing: 12) {
                SettingsIconTile(
                    color: Color(red: 0xE0 / 255.0, green: 0xA1 / 255.0, blue: 0x00 / 255.0),
                    systemImage: "shield.fill"
                )
                Picker("Rating", selection: $filters.rating) {
                    ForEach(AO3SearchFilters.Rating.searchCases) { Text($0.title).tag($0) }
                }
            }
            .onChange(of: filters.rating) { oldValue, newValue in
                if oldValue == .any, newValue != .any {
                    filters.ratingMatch = .exact
                    filters.includeNotRated = false
                } else if newValue == .any {
                    filters.ratingMatch = .exact
                }
            }

            HStack(spacing: 12) {
                SettingsIconTile(
                    color: Color(red: 0x8E / 255.0, green: 0x8E / 255.0, blue: 0x93 / 255.0),
                    systemImage: "questionmark.circle"
                )
                Toggle("Include Not Rated", isOn: $filters.includeNotRated).accentFill()
            }

            if filters.rating != .any {
                HStack(spacing: 12) {
                    SettingsIconTile(
                        color: Color(red: 0xE0 / 255.0, green: 0xA1 / 255.0, blue: 0x00 / 255.0),
                        systemImage: "slider.horizontal.2"
                    )
                    Picker("Match", selection: $filters.ratingMatch) {
                        ForEach(AO3SearchFilters.RatingMatch.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                }
            }
        } header: {
            groupLabel("Content")
        }
    }

    private var categoriesSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(AO3SearchFilters.Category.allCases) { category in
                    FilterSymbolChipCard(
                        title: category.title,
                        symbol: WorkSymbolTile.category([category.title], dark: isDark),
                        state: categoryState(category)
                    ) {
                        cycle(category)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            groupLabel("Categories")
        }
    }

    private var warningsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Overall")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        warningCard(.noWarnings, title: "No Warnings Apply")
                        warningCard(.chooseNotTo, title: "Creator Chose Not To Use")
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Content")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        warningCard(.violence, title: "Graphic Violence")
                        warningCard(.death, title: "Major Character Death")
                        warningCard(.nonCon, title: "Rape/Non-Con")
                        warningCard(.underage, title: "Underage Sex")
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            groupLabel("Warnings")
        }
    }

    private var tagAndTextSection: some View {
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

            if mode == .search {
                HStack(spacing: 12) {
                    SettingsIconTile(
                        color: Color(red: 0x2C / 255.0, green: 0x6D / 255.0, blue: 0xB0 / 255.0),
                        systemImage: "person.2"
                    )
                    Picker("Crossovers", selection: $filters.crossover) {
                        ForEach(AO3SearchFilters.Crossover.allCases) { Text($0.title).tag($0) }
                    }
                }

                DisclosureGroup {
                    TextField("Title", text: $filters.title)
                    TextField("Creator", text: $filters.creators)
                    #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    #endif
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconTile(
                            color: Color(red: 0x6C / 255.0, green: 0x6C / 255.0, blue: 0x70 / 255.0),
                            systemImage: "text.quote"
                        )
                        Text("Title & creator")
                        Spacer()
                        Text(titleAndCreatorSummary)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            groupLabel("Tags and text")
        }
    }

    private var lengthAndStatusSection: some View {
        Section {
            if Self.showsPageCompletionFacet(worksSort: worksSort) {
                HStack(spacing: 12) {
                    SettingsIconTile(
                        color: Color(red: 0x2F / 255.0, green: 0x8F / 255.0, blue: 0x3A / 255.0),
                        systemImage: "checkmark.circle"
                    )
                    Picker("Completion", selection: $filters.completion) {
                        ForEach(AO3SearchFilters.Completion.allCases) { Text($0.title).tag($0) }
                    }
                }
            }

            HStack(spacing: 12) {
                SettingsIconTile(
                    color: Color(red: 0x7B / 255.0, green: 0x3F / 255.0, blue: 0xA0 / 255.0),
                    systemImage: "list.number"
                )
                Picker("Chapters", selection: $filters.chapterCount) {
                    ForEach(AO3SearchFilters.ChapterCount.allCases) { Text($0.title).tag($0) }
                }
            }

            if mode == .search {
                HStack(spacing: 12) {
                    SettingsIconTile(
                        color: Color(red: 0xE0 / 255.0, green: 0x70 / 255.0, blue: 0x00 / 255.0),
                        systemImage: "calendar"
                    )
                    Picker("Updated", selection: $filters.updated) {
                        ForEach(AO3SearchFilters.Updated.allCases) { Text($0.title).tag($0) }
                    }
                }
                dateBound("After", date: $filters.dateFrom)
                dateBound("Before", date: $filters.dateTo)
            }

            NavigationLink {
                FilterLanguagePicker(selection: $filters.language)
            } label: {
                HStack(spacing: 12) {
                    SettingsIconTile(
                        color: Color(red: 0x1E / 255.0, green: 0x63 / 255.0, blue: 0xC8 / 255.0),
                        systemImage: "globe"
                    )
                    Text("Language")
                    Spacer()
                    Text(filters.language.title)
                        .foregroundStyle(.secondary)
                }
            }

            FilterLengthSection(wordsFrom: $filters.wordsFrom, wordsTo: $filters.wordsTo)
        } header: {
            groupLabel("Length and status")
        }
    }

    private var popularitySection: some View {
        Section {
            DisclosureGroup {
                FilterRangeSlider(
                    from: $filters.kudosFrom,
                    to: $filters.kudosTo,
                    defaultMaximum: FilterRangeSlider.kudosMaximum
                )
            } label: {
                HStack(spacing: 12) {
                    SettingsIconTile(
                        color: Color(red: 0x82 / 255.0, green: 0x10 / 255.0, blue: 0x19 / 255.0),
                        systemImage: "heart.fill"
                    )
                    Text("Kudos")
                    Spacer()
                    Text(rangeSummary(from: filters.kudosFrom, to: filters.kudosTo))
                        .foregroundStyle(.secondary)
                }
            }

            DisclosureGroup {
                FilterRangeSlider(
                    from: $filters.hitsFrom,
                    to: $filters.hitsTo,
                    defaultMaximum: FilterRangeSlider.hitsMaximum
                )
            } label: {
                HStack(spacing: 12) {
                    SettingsIconTile(
                        color: Color(red: 0x58 / 255.0, green: 0x56 / 255.0, blue: 0xD6 / 255.0),
                        systemImage: "eye.fill"
                    )
                    Text("Hits")
                    Spacer()
                    Text(rangeSummary(from: filters.hitsFrom, to: filters.hitsTo))
                        .foregroundStyle(.secondary)
                }
            }

            DisclosureGroup {
                FilterRangeSlider(
                    from: $filters.commentsFrom,
                    to: $filters.commentsTo,
                    defaultMaximum: FilterRangeSlider.commentsMaximum
                )
            } label: {
                HStack(spacing: 12) {
                    SettingsIconTile(
                        color: Color(red: 0x2F / 255.0, green: 0x8F / 255.0, blue: 0x3A / 255.0),
                        systemImage: "bubble.left.and.bubble.right.fill"
                    )
                    Text("Comments")
                    Spacer()
                    Text(rangeSummary(from: filters.commentsFrom, to: filters.commentsTo))
                        .foregroundStyle(.secondary)
                }
            }

            DisclosureGroup {
                FilterRangeSlider(
                    from: $filters.bookmarksFrom,
                    to: $filters.bookmarksTo,
                    defaultMaximum: FilterRangeSlider.bookmarksMaximum
                )
            } label: {
                HStack(spacing: 12) {
                    SettingsIconTile(
                        color: Color(red: 0xC2 / 255.0, green: 0x5E / 255.0, blue: 0x00 / 255.0),
                        systemImage: "bookmark.fill"
                    )
                    Text("Bookmarks")
                    Spacer()
                    Text(rangeSummary(from: filters.bookmarksFrom, to: filters.bookmarksTo))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            groupLabel("Popularity")
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive, action: onReset) {
                HStack {
                    Spacer()
                    Text("Reset all filters")
                        .foregroundStyle(
                            canReset
                                ? theme.appTheme.errorColor
                                : Color.secondary
                        )
                    Spacer()
                }
            }
            .disabled(!canReset)
        }
    }
}

// MARK: - Facet Selection & Helpers

extension AO3FilterPanel {
    private var titleAndCreatorSummary: String {
        let titleText = filters.title.trimmingCharacters(in: .whitespaces)
        let creatorText = filters.creators.trimmingCharacters(in: .whitespaces)
        switch (!titleText.isEmpty, !creatorText.isEmpty) {
        case (false, false): return "Any"
        case (true, false): return titleText
        case (false, true): return creatorText
        case (true, true): return "\(titleText) · \(creatorText)"
        }
    }

    private func rangeSummary(from: String, to: String) -> String {
        let fromVal = from.trimmingCharacters(in: .whitespaces)
        let toVal = to.trimmingCharacters(in: .whitespaces)
        switch (!fromVal.isEmpty, !toVal.isEmpty) {
        case (false, false): return "Any"
        case (true, false): return "\(fromVal) or more"
        case (false, true): return "Up to \(toVal)"
        case (true, true): return "\(fromVal)–\(toVal)"
        }
    }

    private static func commaSeparatedValues(_ field: String) -> [String] {
        field.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var selectedFandoms: [String] {
        Self.commaSeparatedValues(filters.fandom)
    }

    private func warningCard(_ warning: AO3SearchFilters.Warning, title: String) -> some View {
        let symbol: WorkSymbolTile = switch warning {
        case .noWarnings:
            WorkSymbolTile.warnings(.none, dark: isDark)
        case .chooseNotTo:
            WorkSymbolTile.warnings(.undisclosed, dark: isDark)
        case .violence, .death, .nonCon, .underage:
            WorkSymbolTile.warnings(.present(count: 1), dark: isDark)
        }
        return FilterSymbolChipCard(
            title: title,
            fullTitle: warning.title,
            symbol: symbol,
            state: warningState(warning)
        ) {
            cycle(warning)
        }
    }

    @ViewBuilder
    private func dateBound(_ title: String, date: Binding<Date?>) -> some View {
        Toggle(title, isOn: Binding(
            get: { date.wrappedValue != nil },
            set: { date.wrappedValue = $0 ? (date.wrappedValue ?? Date()) : nil }
        )).accentFill()
        if let value = date.wrappedValue {
            DatePicker(
                title,
                selection: Binding(get: { value }, set: { date.wrappedValue = $0 }),
                displayedComponents: .date
            )
            .labelsHidden().accentFill()
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

// MARK: - Active Filter Items Generation

extension AO3FilterPanel {
    private var activeFilterItems: [ActiveFilterItem] {
        var items: [ActiveFilterItem] = []

        if mode == .search && filters.sort != .relevance {
            items.append(ActiveFilterItem(
                id: "sort",
                label: "Sort: \(filters.sort.title)",
                kind: .facetValue,
                onRemove: { filters.sort = .relevance }
            ))
        }

        if filters.rating != .any {
            items.append(ActiveFilterItem(
                id: "rating",
                label: filters.rating.title,
                kind: .facetValue,
                onRemove: { filters.rating = .any }
            ))
        }

        if !filters.includeNotRated {
            items.append(ActiveFilterItem(
                id: "noNotRated",
                label: "No Not Rated",
                kind: .facetValue,
                onRemove: { filters.includeNotRated = true }
            ))
        }

        for cat in AO3SearchFilters.Category.allCases {
            if filters.categories.contains(cat) {
                items.append(ActiveFilterItem(
                    id: "cat-\(cat.rawValue)",
                    label: cat.title,
                    kind: .included,
                    onRemove: { filters.categories.remove(cat) }
                ))
            } else if filters.excludedCategories.contains(cat) {
                items.append(ActiveFilterItem(
                    id: "cat-ex-\(cat.rawValue)",
                    label: cat.title,
                    kind: .excluded,
                    onRemove: { filters.excludedCategories.remove(cat) }
                ))
            }
        }

        for warning in AO3SearchFilters.Warning.allCases {
            if filters.warnings.contains(warning) {
                items.append(ActiveFilterItem(
                    id: "warn-\(warning.rawValue)",
                    label: warning.title,
                    kind: .included,
                    onRemove: { filters.warnings.remove(warning) }
                ))
            } else if filters.excludedWarnings.contains(warning) {
                items.append(ActiveFilterItem(
                    id: "warn-ex-\(warning.rawValue)",
                    label: warning.title,
                    kind: .excluded,
                    onRemove: { filters.excludedWarnings.remove(warning) }
                ))
            }
        }

        for fandom in Self.commaSeparatedValues(filters.fandom) {
            items.append(ActiveFilterItem(
                id: "fandom-\(fandom)",
                label: fandom,
                kind: .included,
                onRemove: { removeTag(fandom, from: &filters.fandom) }
            ))
        }
        for fandom in Self.commaSeparatedValues(filters.excludedFandoms) {
            items.append(ActiveFilterItem(
                id: "fandom-ex-\(fandom)",
                label: fandom,
                kind: .excluded,
                onRemove: { removeTag(fandom, from: &filters.excludedFandoms) }
            ))
        }

        for character in Self.commaSeparatedValues(filters.characters) {
            items.append(ActiveFilterItem(
                id: "char-\(character)",
                label: character,
                kind: .included,
                onRemove: { removeTag(character, from: &filters.characters) }
            ))
        }
        for character in Self.commaSeparatedValues(filters.excludedCharacters) {
            items.append(ActiveFilterItem(
                id: "char-ex-\(character)",
                label: character,
                kind: .excluded,
                onRemove: { removeTag(character, from: &filters.excludedCharacters) }
            ))
        }

        for relationship in Self.commaSeparatedValues(filters.relationships) {
            items.append(ActiveFilterItem(
                id: "rel-\(relationship)",
                label: relationship,
                kind: .included,
                onRemove: { removeTag(relationship, from: &filters.relationships) }
            ))
        }
        for relationship in Self.commaSeparatedValues(filters.excludedRelationships) {
            items.append(ActiveFilterItem(
                id: "rel-ex-\(relationship)",
                label: relationship,
                kind: .excluded,
                onRemove: { removeTag(relationship, from: &filters.excludedRelationships) }
            ))
        }

        for tag in Self.commaSeparatedValues(filters.additionalTags) {
            items.append(ActiveFilterItem(
                id: "tag-\(tag)",
                label: tag,
                kind: .included,
                onRemove: { removeTag(tag, from: &filters.additionalTags) }
            ))
        }
        for tag in Self.commaSeparatedValues(filters.excludedAdditionalTags) {
            items.append(ActiveFilterItem(
                id: "tag-ex-\(tag)",
                label: tag,
                kind: .excluded,
                onRemove: { removeTag(tag, from: &filters.excludedAdditionalTags) }
            ))
        }

        if !filters.title.trimmingCharacters(in: .whitespaces).isEmpty {
            items.append(ActiveFilterItem(
                id: "title",
                label: "Title: \(filters.title)",
                kind: .facetValue,
                onRemove: { filters.title = "" }
            ))
        }
        if !filters.creators.trimmingCharacters(in: .whitespaces).isEmpty {
            items.append(ActiveFilterItem(
                id: "creator",
                label: "Creator: \(filters.creators)",
                kind: .facetValue,
                onRemove: { filters.creators = "" }
            ))
        }

        if filters.crossover != .any {
            items.append(ActiveFilterItem(
                id: "crossover",
                label: filters.crossover.title,
                kind: .facetValue,
                onRemove: { filters.crossover = .any }
            ))
        }

        if filters.completion != .any {
            items.append(ActiveFilterItem(
                id: "completion",
                label: filters.completion.title,
                kind: .facetValue,
                onRemove: { filters.completion = .any }
            ))
        }

        if filters.chapterCount != .any {
            items.append(ActiveFilterItem(
                id: "chapters",
                label: filters.chapterCount.title,
                kind: .facetValue,
                onRemove: { filters.chapterCount = .any }
            ))
        }

        let wf = filters.wordsFrom.trimmingCharacters(in: .whitespaces)
        let wt = filters.wordsTo.trimmingCharacters(in: .whitespaces)
        if !wf.isEmpty || !wt.isEmpty {
            let label: String
            if !wf.isEmpty && !wt.isEmpty {
                label = "\(wf)–\(wt) words"
            } else if !wf.isEmpty {
                label = "≥ \(wf) words"
            } else {
                label = "≤ \(wt) words"
            }
            items.append(ActiveFilterItem(
                id: "words",
                label: label,
                kind: .facetValue,
                onRemove: {
                    filters.wordsFrom = ""
                    filters.wordsTo = ""
                }
            ))
        }

        if filters.updated != .any {
            items.append(ActiveFilterItem(
                id: "updated",
                label: filters.updated.title,
                kind: .facetValue,
                onRemove: { filters.updated = .any }
            ))
        }
        if let df = filters.dateFrom {
            items.append(ActiveFilterItem(
                id: "dateFrom",
                label: "After \(AO3SearchFilters.dateBoundFormatter.string(from: df))",
                kind: .facetValue,
                onRemove: { filters.dateFrom = nil }
            ))
        }
        if let dt = filters.dateTo {
            items.append(ActiveFilterItem(
                id: "dateTo",
                label: "Before \(AO3SearchFilters.dateBoundFormatter.string(from: dt))",
                kind: .facetValue,
                onRemove: { filters.dateTo = nil }
            ))
        }

        if filters.language != .any {
            items.append(ActiveFilterItem(
                id: "language",
                label: filters.language.title,
                kind: .facetValue,
                onRemove: { filters.language = .any }
            ))
        }

        appendPopularityActiveItems(to: &items)

        return items
    }

    private func appendPopularityActiveItems(to items: inout [ActiveFilterItem]) {
        for (name, key, from, to) in [
            ("kudos", "kudos", filters.kudosFrom, filters.kudosTo),
            ("hits", "hits", filters.hitsFrom, filters.hitsTo),
            ("comments", "comments", filters.commentsFrom, filters.commentsTo),
            ("bookmarks", "bookmarks", filters.bookmarksFrom, filters.bookmarksTo)
        ] {
            let fromVal = from.trimmingCharacters(in: .whitespaces)
            let toVal = to.trimmingCharacters(in: .whitespaces)
            if !fromVal.isEmpty || !toVal.isEmpty {
                let label: String
                if !fromVal.isEmpty && !toVal.isEmpty {
                    label = "\(fromVal)–\(toVal) \(name)"
                } else if !fromVal.isEmpty {
                    label = "\(fromVal)+ \(name)"
                } else {
                    label = "≤ \(toVal) \(name)"
                }
                items.append(ActiveFilterItem(
                    id: key,
                    label: label,
                    kind: .facetValue,
                    onRemove: {
                        switch key {
                        case "kudos": filters.kudosFrom = ""; filters.kudosTo = ""
                        case "hits": filters.hitsFrom = ""; filters.hitsTo = ""
                        case "comments": filters.commentsFrom = ""; filters.commentsTo = ""
                        case "bookmarks": filters.bookmarksFrom = ""; filters.bookmarksTo = ""
                        default: break
                        }
                    }
                ))
            }
        }
    }

    private func removeTag(_ tag: String, from commaSeparated: inout String) {
        var tags = Self.commaSeparatedValues(commaSeparated)
        tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
        commaSeparated = tags.joined(separator: ", ")
    }
}

// MARK: - 1v works sort

extension AO3FilterPanel {
    @ViewBuilder
    var worksSortSections: some View {
        if worksSort != nil {
            Section {
                Menu {
                    Picker("Sort by", selection: worksColumnBinding) {
                        ForEach(AO3WorksSort.allColumns) { column in
                            Text(column.title).tag(column)
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconTile(
                            color: Color(red: 0x1E / 255.0, green: 0x63 / 255.0, blue: 0xC8 / 255.0),
                            systemImage: "arrow.up.arrow.down"
                        )
                        Text("Sort by")
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(sortPresentation.draft.column.title)
                            Text(AO3WorksSort.fieldsHint)
                                .font(.system(size: sortHintSize))
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
                .accentFill()
            }
            Section {
                worksCompletionChips
            } header: {
                groupLabel("Completion")
            }
        }
    }

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

#if DEBUG
extension AO3FilterPanel {
    func debugTagSet(_ value: Binding<String>) -> Binding<Set<String>> {
        Binding(
            get: {
                Set(value.wrappedValue.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            },
            set: { value.wrappedValue = $0.sorted().joined(separator: ", ") }
        )
    }
}
#endif

/// The count and navigation bar sit outside the Form's themed scroll background.
struct WorksFilterSheetGround: ViewModifier {
    @Environment(ThemeManager.self) private var theme

    func body(content: Content) -> some View {
        if theme.appTheme == .sepia {
            content
                .background(theme.appTheme.cardBackdrop.ignoresSafeArea())
                #if os(iOS)
                    .toolbarBackground(theme.appTheme.cardBackdrop, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                #endif
        } else {
            content
        }
    }
}
