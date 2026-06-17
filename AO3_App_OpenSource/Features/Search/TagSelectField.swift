#if os(iOS)
import SwiftUI

/// A filter-panel row that replaces free-text tag entry with tap-to-select tags.
/// Shows the current selections as removable chips and opens a searchable picker
/// (live AO3 tag search) on tap. Selections are stored back into the existing
/// comma-separated filter field, so the search request is unchanged.
struct TagSelectField: View {
    let title: String
    let kind: AO3TagKind
    @Binding var value: String
    /// Fandoms currently selected in the filters; lets the picker show that fandom's
    /// most popular tags by default (empty for the Fandoms field itself).
    var fandomContext: [String] = []

    @State private var showPicker = false

    private var selected: [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
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
                    Text(selected.isEmpty ? "Any" : "\(selected.count) selected")
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !selected.isEmpty {
                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(selected, id: \.self) { tag in
                        SelectedTagChip(tag: tag) { remove(tag) }
                    }
                }
                .padding(.top, 2)
            }
        }
        .sheet(isPresented: $showPicker) {
            TagPickerView(title: title, kind: kind, selected: selectionBinding, fandomContext: fandomContext)
        }
    }

    private func remove(_ tag: String) {
        value = selected.filter { $0 != tag }.joined(separator: ", ")
    }

    /// Bridges the comma-separated storage to the picker's `Set<String>`.
    private var selectionBinding: Binding<Set<String>> {
        Binding(
            get: { Set(selected) },
            set: { value = $0.sorted().joined(separator: ", ") }
        )
    }
}

/// A searchable, multi-select tag picker backed by AO3's autocomplete. Any AO3 tag
/// of the given kind can be found by typing; tapping toggles selection.
struct TagPickerView: View {
    let title: String
    let kind: AO3TagKind
    @Binding var selected: Set<String>
    /// Selected fandoms, used to seed the default list with their popular tags.
    var fandomContext: [String] = []
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [String] = []
    @State private var isSearching = false
    @State private var popular: [String] = []
    @State private var loadingPopular = false

    private var hasFandomContext: Bool { kind != .fandom && !fandomContext.isEmpty }
    private var isSearchEmpty: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            List {
                if !selected.isEmpty {
                    Section("Selected") {
                        FlowLayout(spacing: 6, rowSpacing: 6) {
                            ForEach(selected.sorted(), id: \.self) { tag in
                                SelectedTagChip(tag: tag, tinted: true) { selected.remove(tag) }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if isSearchEmpty && hasFandomContext {
                    // Default state: the selected fandom's most-used tags of this kind.
                    Section("Popular in \(fandomContext[0])") {
                        if loadingPopular {
                            HStack(spacing: 8) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
                        } else if popular.isEmpty {
                            Text("Type above to search AO3 \(title.lowercased()).")
                                .foregroundStyle(.secondary)
                        } else {
                            tagRows(popular)
                        }
                    }
                } else {
                    Section("Results") {
                        if isSearching {
                            HStack(spacing: 8) { ProgressView(); Text("Searching…").foregroundStyle(.secondary) }
                        } else if isSearchEmpty {
                            Text("Type above to search AO3 \(title.lowercased()).")
                                .foregroundStyle(.secondary)
                        } else if results.isEmpty {
                            Text("No tags found for “\(query)”.")
                                .foregroundStyle(.secondary)
                        } else {
                            tagRows(results)
                        }
                    }
                }
            }
            .appThemedScroll()
            .appThemedRows()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search \(title)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadPopular() }
            .task(id: query) { await runSearch() }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func tagRows(_ tags: [String]) -> some View {
        ForEach(tags, id: \.self) { tag in
            Button {
                toggle(tag)
            } label: {
                HStack {
                    Text(tag).foregroundStyle(.primary)
                    Spacer()
                    if selected.contains(tag) {
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

    private func toggle(_ tag: String) {
        if selected.contains(tag) { selected.remove(tag) } else { selected.insert(tag) }
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

/// A capsule chip with a remove (×) affordance, used for selected filter tags.
private struct SelectedTagChip: View {
    let tag: String
    var tinted: Bool = false
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 4) {
                Text(tag).lineLimit(1)
                Image(systemName: "xmark.circle.fill").font(.caption2)
            }
            .font(.caption)
            .padding(.leading, 10)
            .padding(.trailing, 7)
            .padding(.vertical, 5)
            .foregroundStyle(tinted ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
            .background(
                tinted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.accentColor.opacity(0.15)),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }
}
#endif
