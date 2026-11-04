import SwiftUI

/// The Library's filter panel — parity with the Search filters, but the options
/// are drawn from the user's own saved works and filtering is applied live to the
/// local collection. Presented as a sheet on iPhone and as an inspector sidebar
/// on iPad/macOS through `filterPanelPresentation`.
struct LibraryFilterPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Binding var filters: LibraryFilters
    /// All saved works, used to populate the tag/language facet lists.
    let works: [SavedWork]
    /// The user's own tag names, for the "Your Tags" facet.
    let userTagNames: [String]
    #if DEBUG
    @State private var debugFandomPicker = false
    #endif

    private var isDark: Bool {
        theme.appTheme == .dark || theme.appTheme == .oled
    }

    private var matchingCount: Int {
        works.filter(filters.matches).count
    }

    var body: some View {
        NavigationStack {
            form
                .navigationTitle("Filters")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar { actionButtons }
                .safeAreaInset(edge: .bottom) {
                    FilterResultsBar(
                        buttonTitle: "Show \(matchingCount.formatted()) \(matchingCount == 1 ? "Work" : "Works")",
                        onConfirm: { dismiss() }
                    )
                }
        }
        #if DEBUG
        // From the panel: the Fandoms row sits below the fold, and a row a Form has not drawn
        // never runs its task.
        .task {
            guard DebugLaunchRoute.takeSheet("libpicker") else { return }
            try? await Task.sleep(for: .seconds(1))
            debugFandomPicker = true
        }
        .sheet(isPresented: $debugFandomPicker) {
            LibraryOptionPicker(title: "Fandoms", options: distinct(\.workFandoms), selection: $filters.fandoms)
        }
        #endif
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
        // No ✓ (board 03): the "Show N Works" bar below is the sheet's one confirm.
    }

    private func groupLabel(_ text: String) -> some View {
        SubjectFieldLabel(text: text, style: .formGroup)
    }

    private var form: some View {
        Form {
            if !activeFilterItems.isEmpty {
                Section {
                    ActiveFiltersBlock(items: activeFilterItems) {
                        filters = LibraryFilters()
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Group {
                // MARK: Sort & Rating
                Section {
                    HStack(spacing: 12) {
                        SettingsIconTile(
                            color: Color(red: 0x1E / 255.0, green: 0x63 / 255.0, blue: 0xC8 / 255.0),
                            systemImage: "arrow.up.arrow.down"
                        )
                        Picker("Sort By", selection: $filters.sort) {
                            ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    HStack(spacing: 12) {
                        SettingsIconTile(
                            color: Color(red: 0xE0 / 255.0, green: 0xA1 / 255.0, blue: 0x00 / 255.0),
                            systemImage: "shield.fill"
                        )
                        Picker("Rating", selection: $filters.rating) {
                            ForEach(AO3SearchFilters.Rating.allCases) { Text($0.title).tag($0) }
                        }
                    }
                }

                // MARK: Categories
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

                // MARK: Warnings
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

                // MARK: Tags and Creators
                Section {
                    if !userTagNames.isEmpty {
                        LibraryMultiSelectField(
                            title: "Your Tags",
                            options: userTagNames,
                            selection: $filters.userTags
                        )
                    }
                    LibraryMultiSelectField(
                        title: "Fandoms",
                        options: distinct(\.workFandoms),
                        selection: $filters.fandoms
                    )
                    LibraryMultiSelectField(
                        title: "Characters",
                        options: distinct(\.workCharacters),
                        selection: $filters.characters
                    )
                    LibraryMultiSelectField(
                        title: "Relationships",
                        options: distinct(\.workRelationships),
                        selection: $filters.relationships
                    )
                    LibraryMultiSelectField(
                        title: "Additional Tags",
                        options: distinct(\.workFreeforms),
                        selection: $filters.additionalTags
                    )
                    LibraryMultiSelectField(
                        title: "Exclude Tags",
                        options: distinct(\.workTags),
                        selection: $filters.excludeTags
                    )
                } header: {
                    groupLabel("Tags and Creators")
                }

                // MARK: Length and Status
                Section {
                    HStack(spacing: 12) {
                        SettingsIconTile(
                            color: Color(red: 0x2F / 255.0, green: 0x8F / 255.0, blue: 0x3A / 255.0),
                            systemImage: "checkmark.circle"
                        )
                        Picker("Completion", selection: $filters.completion) {
                            ForEach(AO3SearchFilters.Completion.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    if !languageOptions.isEmpty {
                        HStack(spacing: 12) {
                            SettingsIconTile(
                                color: Color(red: 0x1E / 255.0, green: 0x63 / 255.0, blue: 0xC8 / 255.0),
                                systemImage: "globe"
                            )
                            Picker("Language", selection: $filters.language) {
                                Text("Any Language").tag("")
                                ForEach(languageOptions, id: \.self) { Text($0).tag($0) }
                            }
                        }
                    }

                    FilterLengthSection(wordsFrom: $filters.wordsFrom, wordsTo: $filters.wordsTo)
                } header: {
                    groupLabel("Length and Status")
                }

                // MARK: Reset row
                Section {
                    Button(role: .destructive) {
                        filters = LibraryFilters()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Reset All Filters")
                                .foregroundStyle(
                                    filters.hasActiveFilters
                                        ? theme.appTheme.errorColor
                                        : Color.secondary
                                )
                            Spacer()
                        }
                    }
                    .disabled(!filters.hasActiveFilters)
                }
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
    }

    // MARK: - Symbol card helper

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

    // MARK: - Facet option lists

    /// Distinct, sorted values of a string-array field across all saved works.
    private func distinct(_ keyPath: KeyPath<SavedWork, [String]>) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for work in works {
            for value in work[keyPath: keyPath] where seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result.sorted()
    }

    private var languageOptions: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for work in works where !work.language.isEmpty && seen.insert(work.language).inserted {
            result.append(work.language)
        }
        return result.sorted()
    }

    // MARK: - Selection helpers

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

    // MARK: - Active Filter Items

    private var activeFilterItems: [ActiveFilterItem] {
        var items: [ActiveFilterItem] = []

        if filters.sort != .natural {
            items.append(ActiveFilterItem(
                id: "sort",
                label: "Sort: \(filters.sort.title)",
                kind: .facetValue,
                onRemove: { filters.sort = .natural }
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

        for tag in filters.userTags.sorted() {
            items.append(ActiveFilterItem(
                id: "user-\(tag)",
                label: tag,
                kind: .included,
                onRemove: { filters.userTags.remove(tag) }
            ))
        }
        for tag in filters.fandoms.sorted() {
            items.append(ActiveFilterItem(
                id: "fandom-\(tag)",
                label: tag,
                kind: .included,
                onRemove: { filters.fandoms.remove(tag) }
            ))
        }
        for tag in filters.characters.sorted() {
            items.append(ActiveFilterItem(
                id: "char-\(tag)",
                label: tag,
                kind: .included,
                onRemove: { filters.characters.remove(tag) }
            ))
        }
        for tag in filters.relationships.sorted() {
            items.append(ActiveFilterItem(
                id: "rel-\(tag)",
                label: tag,
                kind: .included,
                onRemove: { filters.relationships.remove(tag) }
            ))
        }
        for tag in filters.additionalTags.sorted() {
            items.append(ActiveFilterItem(
                id: "add-\(tag)",
                label: tag,
                kind: .included,
                onRemove: { filters.additionalTags.remove(tag) }
            ))
        }
        for tag in filters.excludeTags.sorted() {
            items.append(ActiveFilterItem(
                id: "ex-\(tag)",
                label: tag,
                kind: .excluded,
                onRemove: { filters.excludeTags.remove(tag) }
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

        if !filters.language.isEmpty {
            items.append(ActiveFilterItem(
                id: "language",
                label: filters.language,
                kind: .facetValue,
                onRemove: { filters.language = "" }
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

        return items
    }
}

// MARK: - Multi-select facet field

/// A filter row that opens a searchable, multi-select list of the given options
/// (drawn from the library, not AO3). Cross-platform: the picker is a sheet on
/// every platform. Shows "Any" or the selection count on the row.
private struct LibraryMultiSelectField: View {
    let title: String
    let options: [String]
    @Binding var selection: Set<String>
    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(selection.isEmpty ? "Any" : "\(selection.count) selected")
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPicker) {
            LibraryOptionPicker(title: title, options: options, selection: $selection)
        }
    }
}

private struct LibraryOptionPicker: View {
    let title: String
    let options: [String]
    @Binding var selection: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var normalizedOptions: [(value: String, normalized: String)] = []

    private var filtered: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return options }
        let normalizedQuery = WorkSearchIndex.normalize(trimmed)
        return normalizedOptions.filter { $0.normalized.contains(normalizedQuery) }.map(\.value)
    }

    var body: some View {
        NavigationStack {
            List {
                let matches = filtered
                if options.isEmpty {
                    Text("Your Library has no \(title.lowercased()) yet.")
                        .foregroundStyle(.secondary)
                } else if matches.isEmpty {
                    Text("None of your options match “\(query)”.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(matches, id: \.self) { value in
                        Button {
                            if selection.contains(value) {
                                selection.remove(value)
                            } else {
                                selection.insert(value)
                            }
                        } label: {
                            HStack {
                                Text(value).foregroundStyle(.primary)
                                Spacer()
                                if selection.contains(value) {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .appThemedRows()
                }
            }
            .appThemedScroll()
            .navigationTitle(title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .searchable(text: $query, prompt: "Filter \(title)")
                .task {
                    normalizedOptions = options.map { ($0, WorkSearchIndex.normalize($0)) }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "checkmark")
                        }
                        .sheetConfirmStyle()
                        .accessibilityLabel("Done")
                    }
                }
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }
}
