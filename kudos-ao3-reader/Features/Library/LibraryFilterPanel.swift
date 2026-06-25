import SwiftUI

/// The Library's filter panel — parity with the Search filters, but the options
/// are drawn from the user's own saved works and filtering is applied live to the
/// local collection. Presented as a bottom sheet on iPhone and as an inspector
/// sidebar on iPad/macOS (the same `.inspector` the Search filters use).
struct LibraryFilterPanel: View {
    @Binding var filters: LibraryFilters
    /// All saved works, used to populate the tag/language facet lists.
    let works: [SavedWork]
    /// The user's own tag names, for the "Your Tags" facet.
    let userTagNames: [String]

    var body: some View {
        Form {
          // Group so .appThemedRows() reaches every section's rows (it doesn't
          // propagate from the Form container, only from a Group/Section/ForEach).
          Group {
            Section {
                Picker("Sort by", selection: $filters.sort) {
                    ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                }
                Picker("Rating", selection: $filters.rating) {
                    ForEach(AO3SearchFilters.Rating.allCases) { Text($0.title).tag($0) }
                }
            }

            Section("Warnings") {
                ForEach(AO3SearchFilters.Warning.allCases) { warning in
                    selectableRow(warning.title, isSelected: filters.warnings.contains(warning)) {
                        toggle(warning, in: \.warnings)
                    }
                }
            }

            Section("Categories") {
                ForEach(AO3SearchFilters.Category.allCases) { category in
                    selectableRow(category.title, isSelected: filters.categories.contains(category)) {
                        toggle(category, in: \.categories)
                    }
                }
            }

            Section {
                Picker("Completion", selection: $filters.completion) {
                    ForEach(AO3SearchFilters.Completion.allCases) { Text($0.title).tag($0) }
                }
                if !languageOptions.isEmpty {
                    Picker("Language", selection: $filters.language) {
                        Text("Any language").tag("")
                        ForEach(languageOptions, id: \.self) { Text($0).tag($0) }
                    }
                }
            }

            Section {
                TextField("From", text: $filters.wordsFrom)
                    #if !os(macOS)
                    .keyboardType(.numberPad)
                    #endif
                TextField("To", text: $filters.wordsTo)
                    #if !os(macOS)
                    .keyboardType(.numberPad)
                    #endif
            } header: {
                Text("Word count")
            } footer: {
                Text("Word counts come from AO3 and fill in once a work has been opened.")
            }

            Section {
                if !userTagNames.isEmpty {
                    LibraryMultiSelectField(title: "Your Tags", options: userTagNames,
                                            selection: $filters.userTags)
                }
                LibraryMultiSelectField(title: "Fandoms", options: distinct(\.workFandoms),
                                        selection: $filters.fandoms)
                LibraryMultiSelectField(title: "Characters", options: distinct(\.workCharacters),
                                        selection: $filters.characters)
                LibraryMultiSelectField(title: "Relationships", options: distinct(\.workRelationships),
                                        selection: $filters.relationships)
                LibraryMultiSelectField(title: "Additional Tags", options: distinct(\.workFreeforms),
                                        selection: $filters.additionalTags)
                LibraryMultiSelectField(title: "Exclude Tags", options: distinct(\.workTags),
                                        selection: $filters.excludeTags)
            } header: {
                Text("Tags")
            } footer: {
                Text("Filter by the work's own AO3 tags. Exclude Tags hides matching works.")
            }

            if filters.hasActiveFilters {
                Section {
                    Button(role: .destructive) {
                        filters = LibraryFilters()
                    } label: {
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

    // MARK: Facet option lists

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

    // MARK: Selection helpers

    private func toggle<T: Hashable>(_ value: T, in keyPath: WritableKeyPath<LibraryFilters, Set<T>>) {
        if filters[keyPath: keyPath].contains(value) {
            filters[keyPath: keyPath].remove(value)
        } else {
            filters[keyPath: keyPath].insert(value)
        }
    }

    /// A tappable row with a trailing checkmark when selected — matching the tag
    /// pickers and the Search filters' Warnings/Categories rows.
    private func selectableRow(_ title: String, isSelected: Bool,
                               toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private var filtered: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return options }
        return options.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            List {
                if options.isEmpty {
                    Text("No \(title.lowercased()) in your library yet.")
                        .foregroundStyle(.secondary)
                } else if filtered.isEmpty {
                    Text("No matches for “\(query)”.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered, id: \.self) { value in
                        Button {
                            if selection.contains(value) { selection.remove(value) }
                            else { selection.insert(value) }
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }
}
