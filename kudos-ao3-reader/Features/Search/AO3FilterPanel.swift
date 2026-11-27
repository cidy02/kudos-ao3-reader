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
    @Environment(\.filterPanelIsDocked) private var isDocked
    @Environment(\.duoLayout) private var duoLayout
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
    /// Applied search filters currently driving the results screen (when persistent/docked),
    /// so the confirm button only prints `totalWorks` while the draft still matches them.
    var appliedFilters: AO3SearchFilters?
    /// Incrementing this pops a docked subpage (Sort By / Language) back to the root Filters pane.
    var revealRootTrigger = 0
    /// Works currently loaded on screen, passed to Sort By for the top-ranked preview line.
    var loadedWorks: [AO3WorkSummary] = []
    /// Momentum sightings from the current search session, passed to Sort By.
    var previousKudos: [Int: Int] = [:]
    /// The filters the loaded results were fetched with; the count only describes those.
    @State private var openedFilters: AO3SearchFilters

    enum DockedSubpage: Equatable {
        case sortBy
        case language
    }

    @State private var dockedSubpage: DockedSubpage?
    @State var sortPresentation: WorksSortPresentation
    #if DEBUG
    @State private var debugLanguage = false
    @State private var debugTagPicker = false
    @State private var debugSortBy = false
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
        totalWorks: Int? = nil,
        appliedFilters: AO3SearchFilters? = nil,
        revealRootTrigger: Int = 0,
        loadedWorks: [AO3WorkSummary] = [],
        previousKudos: [Int: Int] = [:]
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
        self.appliedFilters = appliedFilters
        self.revealRootTrigger = revealRootTrigger
        self.loadedWorks = loadedWorks
        self.previousKudos = previousKudos
        _openedFilters = State(initialValue: filters.wrappedValue)
        _sortPresentation = State(initialValue: WorksSortPresentation(applied: worksSort))
    }

    // From colorScheme (ContentView sets it from the app theme), not ThemeManager: the form reads this
    // while `body` is built, and reading ThemeManager there crashes when none is in the environment.
    @Environment(\.colorScheme) private var colorScheme
    var isDark: Bool { colorScheme == .dark }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Two card columns, one at accessibility sizes so long warning titles don't truncate.
    private var cardColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
    }

    static func resultsButtonTitle(
        mode: Mode,
        filters: AO3SearchFilters,
        referenceFilters: AO3SearchFilters,
        totalWorks: Int?,
        refineCount: Int
    ) -> String {
        if mode == .refine {
            return "Show \(refineCount.formatted()) \(refineCount == 1 ? "Work" : "Works")"
        }
        if let total = totalWorks, filters == referenceFilters {
            return "Show \(total.formatted()) \(total == 1 ? "Work" : "Works")"
        }
        return "Show Works"
    }

    private var resultsButtonTitle: String {
        let refineCount = mode == .refine ? (refineMatchCount ?? filters.apply(to: refineSource).count) : 0
        return Self.resultsButtonTitle(
            mode: mode,
            filters: filters,
            referenceFilters: appliedFilters ?? openedFilters,
            totalWorks: totalWorks,
            refineCount: refineCount
        )
    }

    var body: some View {
        let bookLeadingInset: CGFloat = (isDocked && duoLayout.isVerticalFoldActive)
            ? DuoLayoutSignal.bookFoldInset
            : 0
        Group {
            if isDocked {
                dockedPaneBody(bookLeadingInset: bookLeadingInset)
            } else {
                NavigationStack {
                    rootPanelContent(bookLeadingInset: bookLeadingInset)
                    #if DEBUG
                        .navigationDestination(isPresented: $debugLanguage) {
                            FilterLanguagePicker(selection: $filters.language)
                        }
                        .navigationDestination(isPresented: $debugSortBy) {
                            SearchSortByView(
                                filters: $filters,
                                ranking: ranking,
                                allowsRelevanceSort: allowsRelevanceSort,
                                loadedWorks: loadedWorks,
                                previousKudos: previousKudos
                            )
                        }
                    #endif
                }
            }
        }
        #if os(iOS)
            .modifier(ScopeSurfaceAccent())
        #endif
        .onAppear { sortPresentation.appear(applied: worksSort) }
        .onChange(of: isDocked) { _, docked in
            if !docked { dockedSubpage = nil }
        }
        .onChange(of: revealRootTrigger) { _, _ in
            dockedSubpage = nil
        }
    }

    @ViewBuilder
    private func dockedPaneBody(bookLeadingInset: CGFloat) -> some View {
        if let subpage = dockedSubpage {
            Group {
                switch subpage {
                case .sortBy:
                    SearchSortByView(
                        filters: $filters,
                        ranking: ranking,
                        allowsRelevanceSort: allowsRelevanceSort,
                        showsNavigationTitle: false,
                        loadedWorks: loadedWorks,
                        previousKudos: previousKudos
                    )
                case .language:
                    FilterLanguagePicker(selection: $filters.language, isInlinePane: true)
                }
            }
            .padding(.leading, bookLeadingInset)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Button { dockedSubpage = nil } label: {
                        Image(systemName: "chevron.backward")
                            .font(.body.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Back to Filters")
                    Spacer(minLength: 0)
                    Text(subpage == .sortBy ? "Sort By" : "Language")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Color.clear
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .padding(.leading, bookLeadingInset)
            }
            .modifier(WorksFilterSheetGround())
        } else {
            rootPanelContent(bookLeadingInset: bookLeadingInset)
        }
    }

    private func rootPanelContent(bookLeadingInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            refineMatchLine
            form
        }
        .padding(.leading, bookLeadingInset)
        .filterPanelChrome(title: worksSort == nil ? (mode == .refine ? "Refine" : "Filters") : "Sort and Filter")
        .modifier(WorksFilterSheetGround())
        .safeAreaInset(edge: .bottom) {
            FilterResultsBar(
                buttonTitle: resultsButtonTitle,
                isConfirmDisabled: mode == .search && !filters.isSearchable,
                onSave: onSave,
                isSaveDisabled: !filters.isSearchable,
                onConfirm: confirm
            )
            .padding(.leading, bookLeadingInset)
        }
    }

    @ViewBuilder
    private var refineMatchLine: some View {
        if mode == .refine, !refineSource.isEmpty {
            Text(refineMatchText)
                .font(.system(size: refineMatchSize))
                .foregroundStyle(.secondaryInk)
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

    private func confirm() {
        if worksSort != nil, let sort = sortPresentation.sortToCommit {
            onApplyWorksSort?(sort)
        }
        onApply()
        if !isDocked { dismiss() }
    }

    static func showsPageCompletionFacet(worksSort: AO3WorksSort?) -> Bool {
        worksSort == nil
    }

    func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondaryInk)
            .textCase(nil)
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
                tagFieldsSection
                if mode == .search {
                    textAndCrossoversSection
                }

                // MARK: 4. Length and status
                lengthAndStatusSection
            }
            .appThemedRows()

            Section {
                FilterLengthSection(wordsFrom: $filters.wordsFrom, wordsTo: $filters.wordsTo)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Group {
                // MARK: 5. Popularity
                if mode == .search {
                    popularitySection
                }

                // MARK: Reset form row
                if canReset {
                    resetSection
                }
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
        #if DEBUG
        .task {
            if DebugLaunchRoute.takePush("languagepicker") {
                if isDocked { dockedSubpage = .language } else { debugLanguage = true }
            }
            if DebugLaunchRoute.takePush("sortby") {
                if isDocked { dockedSubpage = .sortBy } else { debugSortBy = true }
            }
            if DebugLaunchRoute.takeSheet("tagpicker") {
                try? await Task.sleep(for: .seconds(1))
                debugTagPicker = true
            }
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
    /// Label over the value at accessibility sizes. On one line, "Sort By" and
    /// "Best Match" each wrap and clip.
    @ViewBuilder
    private var sortByLabel: some View {
        let value = SearchSortBySummary.value(filters: filters, ranking: ranking?.wrappedValue)
        let tile = SettingsIconTile(
            color: Color(red: 0x1E / 255.0, green: 0x63 / 255.0, blue: 0xC8 / 255.0),
            systemImage: "arrow.up.arrow.down"
        )
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    tile
                    Text("Sort by")
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(value)
                    .foregroundStyle(.secondaryInk)
                    .lineLimit(value.contains(where: \.isWhitespace) ? nil : 1)
                    .minimumScaleFactor(value.contains(where: \.isWhitespace) ? 1 : 0.6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack(spacing: 12) {
                tile
                Text("Sort by")
                Spacer()
                Text(value)
                    .foregroundStyle(.secondaryInk)
            }
        }
    }

    private var sortSection: some View {
        Section {
            if isDocked {
                Button { dockedSubpage = .sortBy } label: {
                    HStack(spacing: 8) {
                        sortByLabel
                        if dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    SearchSortByView(
                        filters: $filters,
                        ranking: ranking,
                        allowsRelevanceSort: allowsRelevanceSort,
                        loadedWorks: loadedWorks,
                        previousKudos: previousKudos
                    )
                } label: {
                    sortByLabel
                }
            }
        }
        .onChange(of: filters.sort) { _, newValue in
            filters.sortDirection = newValue.naturalDirection
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
                        systemImage: "slider.horizontal.3"
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Categories")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)

                LazyVGrid(columns: cardColumns, spacing: 8) {
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
            }
            .padding(.vertical, 4)
        }
    }

    private var warningsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Warnings")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Overall")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondaryInk)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    LazyVGrid(columns: cardColumns, spacing: 8) {
                        warningCard(.noWarnings)
                        warningCard(.chooseNotTo)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Content")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondaryInk)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    LazyVGrid(columns: cardColumns, spacing: 8) {
                        warningCard(.violence)
                        warningCard(.death)
                        warningCard(.nonCon)
                        warningCard(.underage)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var tagFieldsSection: some View {
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
            groupLabel("Tags and text")
        }
    }

    private var textAndCrossoversSection: some View {
        Section {
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
                        .foregroundStyle(.secondaryInk)
                }
            }
        }
    }

    private var lengthAndStatusSection: some View {
        Section {
            if Self.showsPageCompletionFacet(worksSort: worksSort) {
                completionRow
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

            if isDocked {
                Button { dockedSubpage = .language } label: {
                    HStack(spacing: 12) {
                        languageRowLabel
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    FilterLanguagePicker(selection: $filters.language)
                } label: {
                    languageRowLabel
                }
            }
        } header: {
            groupLabel("Length and status")
        }
    }

    @ViewBuilder
    private var completionRow: some View {
        let tile = SettingsIconTile(
            color: Color(red: 0x2F / 255.0, green: 0x8F / 255.0, blue: 0x3A / 255.0),
            systemImage: "checkmark.circle"
        )
        if dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: 12) {
                tile
                Picker("Completion", selection: $filters.completion) {
                    ForEach(AO3SearchFilters.Completion.allCases) { option in
                        Text(Self.completionSegmentTitle(option)).tag(option)
                    }
                }
            }
        } else {
            HStack(spacing: 12) {
                tile
                Text("Completion")
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Picker("Completion", selection: $filters.completion) {
                    ForEach(AO3SearchFilters.Completion.allCases) { option in
                        Text(Self.completionSegmentTitle(option)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accentFill()
                .fixedSize()
            }
        }
    }

    private var languageRowLabel: some View {
        HStack(spacing: 12) {
            SettingsIconTile(
                color: Color(red: 0x1E / 255.0, green: 0x63 / 255.0, blue: 0xC8 / 255.0),
                systemImage: "globe"
            )
            Text("Language")
            Spacer()
            Text(filters.language.title)
                .foregroundStyle(.secondaryInk)
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
                        .foregroundStyle(.secondaryInk)
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
                        .foregroundStyle(.secondaryInk)
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
                        .foregroundStyle(.secondaryInk)
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
                        .foregroundStyle(.secondaryInk)
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
                    Text("Reset All Filters")
                        .foregroundStyle(
                            canReset
                                ? AnyShapeStyle(theme.appTheme.errorColor)
                                : AnyShapeStyle(.secondaryInk)
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

    static func warningChipTitle(_ warning: AO3SearchFilters.Warning) -> String {
        switch warning {
        case .noWarnings: "No Warnings Apply"
        case .chooseNotTo: "Creator Chose Not To Use"
        case .violence: "Graphic Violence"
        case .death: "Major Character Death"
        case .nonCon: "Rape/Non-Con"
        case .underage: "Underage Sex"
        }
    }

    static func completionSegmentTitle(_ completion: AO3SearchFilters.Completion) -> String {
        switch completion {
        case .any: "Any"
        case .complete: "Complete"
        case .inProgress: "WIP"
        }
    }

    static func ratingActiveLabel(
        rating: AO3SearchFilters.Rating,
        match: AO3SearchFilters.RatingMatch
    ) -> String {
        switch match {
        case .exact: rating.title
        case .orHigher: "\(rating.title)+"
        case .orLower: "\(rating.title)−"
        }
    }

    static func compactFilterNumber(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed) else { return trimmed }
        if value >= 1_000, value.isMultiple(of: 1_000) {
            return "\(value / 1_000)k"
        }
        return value.formatted()
    }

    static func wordsActiveLabel(from: String, to: String) -> String? {
        let lower = from.trimmingCharacters(in: .whitespaces)
        let upper = to.trimmingCharacters(in: .whitespaces)
        switch (!lower.isEmpty, !upper.isEmpty) {
        case (true, true):
            return "\(compactFilterNumber(lower))–\(compactFilterNumber(upper)) words"
        case (true, false):
            return "\(compactFilterNumber(lower))+ words"
        case (false, true):
            return "Under \(compactFilterNumber(upper)) words"
        case (false, false):
            return nil
        }
    }

    static func popularityActiveLabel(name: String, from: String, to: String) -> String? {
        let lower = from.trimmingCharacters(in: .whitespaces)
        let upper = to.trimmingCharacters(in: .whitespaces)
        let formattedLower = Int(lower)?.formatted() ?? lower
        let formattedUpper = Int(upper)?.formatted() ?? upper
        switch (!lower.isEmpty, !upper.isEmpty) {
        case (true, true): return "\(formattedLower)–\(formattedUpper) \(name)"
        case (true, false): return "\(formattedLower)+ \(name)"
        case (false, true): return "Up to \(formattedUpper) \(name)"
        case (false, false): return nil
        }
    }

    static func rangeRowSummary(from: String, to: String) -> String {
        let fromVal = from.trimmingCharacters(in: .whitespaces)
        let toVal = to.trimmingCharacters(in: .whitespaces)
        let formattedFrom = Int(fromVal)?.formatted() ?? fromVal
        let formattedTo = Int(toVal)?.formatted() ?? toVal
        switch (!fromVal.isEmpty, !toVal.isEmpty) {
        case (false, false): return "Any"
        case (true, false): return "\(formattedFrom) or more"
        case (false, true): return "Up to \(formattedTo)"
        case (true, true): return "\(formattedFrom)–\(formattedTo)"
        }
    }

    private func rangeSummary(from: String, to: String) -> String {
        Self.rangeRowSummary(from: from, to: to)
    }

    private static func commaSeparatedValues(_ field: String) -> [String] {
        field.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var selectedFandoms: [String] {
        Self.commaSeparatedValues(filters.fandom)
    }

    private func warningCard(_ warning: AO3SearchFilters.Warning) -> some View {
        let symbol: WorkSymbolTile = switch warning {
        case .noWarnings:
            WorkSymbolTile.warnings(.none, dark: isDark)
        case .chooseNotTo:
            WorkSymbolTile.warnings(.undisclosed, dark: isDark)
        case .violence, .death, .nonCon, .underage:
            WorkSymbolTile.warnings(.present(count: 1), dark: isDark)
        }
        return FilterSymbolChipCard(
            title: Self.warningChipTitle(warning),
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
        appendContentActiveItems(to: &items)
        appendTagActiveItems(to: &items)
        appendStatusActiveItems(to: &items)
        appendPopularityActiveItems(to: &items)
        return items
    }

    private func appendContentActiveItems(to items: inout [ActiveFilterItem]) {
        if filters.rating != .any {
            items.append(ActiveFilterItem(
                id: "rating",
                label: Self.ratingActiveLabel(rating: filters.rating, match: filters.ratingMatch),
                kind: .included,
                onRemove: {
                    filters.rating = .any
                    filters.ratingMatch = .exact
                }
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
            let label = Self.warningChipTitle(warning)
            if filters.warnings.contains(warning) {
                items.append(ActiveFilterItem(
                    id: "warn-\(warning.rawValue)",
                    label: label,
                    kind: .included,
                    onRemove: { filters.warnings.remove(warning) }
                ))
            } else if filters.excludedWarnings.contains(warning) {
                items.append(ActiveFilterItem(
                    id: "warn-ex-\(warning.rawValue)",
                    label: label,
                    kind: .excluded,
                    onRemove: { filters.excludedWarnings.remove(warning) }
                ))
            }
        }
    }

    private func appendTagActiveItems(to items: inout [ActiveFilterItem]) {
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
    }

    private func appendStatusActiveItems(to items: inout [ActiveFilterItem]) {
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
                label: Self.completionSegmentTitle(filters.completion),
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

        if let wordsLabel = Self.wordsActiveLabel(from: filters.wordsFrom, to: filters.wordsTo) {
            items.append(ActiveFilterItem(
                id: "words",
                label: wordsLabel,
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
    }

    private func appendPopularityActiveItems(to items: inout [ActiveFilterItem]) {
        for (name, key, from, to) in [
            ("kudos", "kudos", filters.kudosFrom, filters.kudosTo),
            ("hits", "hits", filters.hitsFrom, filters.hitsTo),
            ("comments", "comments", filters.commentsFrom, filters.commentsTo),
            ("bookmarks", "bookmarks", filters.bookmarksFrom, filters.bookmarksTo),
        ] {
            if let label = Self.popularityActiveLabel(name: name, from: from, to: to) {
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
                    Picker("Sort By", selection: worksColumnBinding) {
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
                                .foregroundStyle(.secondaryInk)
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
