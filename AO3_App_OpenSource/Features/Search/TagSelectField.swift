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

    private var includedTags: [String] { Self.tags(in: included) }
    private var excludedTags: [String] { Self.tags(in: excluded) }

    private var selectionSummary: String {
        let includeCount = includedTags.count
        let excludeCount = excludedTags.count
        if includeCount == 0, excludeCount == 0 { return "Any" }
        var parts: [String] = []
        if includeCount > 0 { parts.append("\(includeCount) included") }
        if excludeCount > 0 { parts.append("\(excludeCount) excluded") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showPicker = true
            } label: {
                HStack {
                    Text(title)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(selectionSummary)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !includedTags.isEmpty || !excludedTags.isEmpty {
                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(includedTags, id: \.self) { tag in
                        FilterTagChip(tag: tag, state: .included) {
                            remove(tag, from: $included)
                        }
                    }
                    ForEach(excludedTags, id: \.self) { tag in
                        FilterTagChip(tag: tag, state: .excluded) {
                            remove(tag, from: $excluded)
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

    private func remove(_ tag: String, from value: Binding<String>) {
        value.wrappedValue = Self.tags(in: value.wrappedValue)
            .filter { $0 != tag }
            .joined(separator: ", ")
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

    @State private var query = ""
    @State private var results: [String] = []
    @State private var isSearching = false
    @State private var popular: [String] = []
    @State private var loadingPopular = false

    private var hasFandomContext: Bool { kind != .fandom && !fandomContext.isEmpty }
    private var isSearchEmpty: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var selectedTags: [String] { Array(included.union(excluded)).sorted() }

    var body: some View {
        NavigationStack {
            List {
              // Group so .appThemedRows() reaches every section's rows (it doesn't
              // propagate from the List container, only from a Group/Section/ForEach).
              Group {
                if !selectedTags.isEmpty {
                    Section("Selected") {
                        FlowLayout(spacing: 6, rowSpacing: 6) {
                            ForEach(selectedTags, id: \.self) { tag in
                                FilterTagChip(tag: tag, state: state(of: tag)) {
                                    clear(tag)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if isSearchEmpty && hasFandomContext {
                    Section("Popular in \(fandomContext[0])") {
                        if loadingPopular {
                            loadingRow("Loading…")
                        } else if popular.isEmpty {
                            searchPrompt
                        } else {
                            tagRows(popular)
                        }
                    }
                } else {
                    Section("Results") {
                        if isSearching {
                            loadingRow("Searching…")
                        } else if isSearchEmpty {
                            searchPrompt
                        } else if results.isEmpty {
                            Text("No tags found for “\(query)”.")
                                .foregroundStyle(.secondary)
                        } else {
                            tagRows(results)
                        }
                    }
                }
              }
              .appThemedRows()
            }
            .appThemedScroll()
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $query, prompt: "Search \(title)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadPopular() }
            .task(id: query) { await runSearch() }
        }
        #if os(iOS)
        .presentationDetents([.large])
        #endif
    }

    private var searchPrompt: some View {
        Text("Type above to search AO3 \(title.lowercased()).")
            .foregroundStyle(.secondary)
    }

    private func loadingRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(text).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func tagRows(_ tags: [String]) -> some View {
        ForEach(tags, id: \.self) { tag in
            Button {
                cycle(tag)
            } label: {
                HStack {
                    Text(tag).foregroundStyle(.primary)
                    Spacer()
                    selectionLabel(for: state(of: tag))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func selectionLabel(for state: TagFilterState) -> some View {
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

    private func state(of tag: String) -> TagFilterState {
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
        popular = (try? await AO3Client.shared.popularTags(forFandom: fandom, kind: kind)) ?? []
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

/// A removable capsule for an included or excluded filter tag.
private struct FilterTagChip: View {
    let tag: String
    let state: TagFilterState
    let onRemove: () -> Void

    private var color: Color { state == .excluded ? .red : .accentColor }
    private var symbol: String { state == .excluded ? "minus.circle.fill" : "plus.circle.fill" }

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.caption2)
                Text(tag).lineLimit(1)
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
            .font(.caption)
            .padding(.leading, 8)
            .padding(.trailing, 7)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(state == .excluded ? "Excluded" : "Included"): \(tag)")
        .accessibilityHint("Removes this tag filter")
    }
}
