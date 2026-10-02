import SwiftData
import SwiftUI

/// Search's on-device matches, shown live as the user types: works, fandoms,
/// tags and collections from the library, plus an explicit "Search AO3" action
/// (no AO3 request fires until the user taps it or submits). Split out of
/// `SearchView` for its file length; the selection state stays there because
/// the toolbar acts on it.
struct SearchLocalResultsList: View {
    let query: String
    let matches: SearchView.LocalMatches
    /// The matched works, already stripped of invalidated models.
    let works: [SavedWork]
    @Binding var isSelecting: Bool
    @Binding var selection: Set<UUID>
    let onSearchAO3: () -> Void
    let onSearchFandom: (String) -> Void

    @Environment(AppRouter.self) private var router
    @State private var pendingDelete: SavedWork?
    @State private var pendingRemoval: PendingLibraryRemoval?

    var body: some View {
        // A deletion re-keys the compute task via the record counts, but a render
        // can land in the gap before the debounce fires — drop invalidated models
        // rather than touching them (SwiftData asserts on invalidated access).
        let tags = matches.tags.filter { $0.modelContext != nil }
        let matchedCollections = matches.collections.filter { $0.modelContext != nil }
        List {
            Section {
                Button(action: onSearchAO3) {
                    Label("Search AO3 for “\(query)”", systemImage: "magnifyingglass")
                }
            } header: {
                Text("Archive of Our Own")
            }

            if !works.isEmpty {
                Section("In Your Library") {
                    // `SensitiveWorkRow`, as Library's lists: the privacy gate, the
                    // shared long-press menu, and selection (T-339).
                    ForEach(works) { work in
                        let isSelected = selection.contains(work.id)
                        SensitiveWorkRow(
                            work: work,
                            onSelect: { isSelecting = true; selection = [work.id] },
                            isSelecting: isSelecting,
                            isSelected: isSelected,
                            onToggleSelection: { toggle(work) }
                        )
                        .cardRow(isSelected: isSelecting && isSelected)
                        // Any kind but History takes the swipes' default branch.
                        .libraryWorkSwipeActions(
                            work,
                            kind: .readingNow,
                            isFavoritesList: false,
                            pendingDelete: $pendingDelete,
                            pendingRemoval: $pendingRemoval
                        )
                    }
                }
            }
            if !matches.libraryFandoms.isEmpty {
                Section("Fandoms in Your Library") {
                    ForEach(matches.libraryFandoms, id: \.self) { fandom in
                        Button { router.filterLibrary(.fandom, fandom) } label: {
                            Label(fandom, systemImage: "books.vertical")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !matches.ao3Fandoms.isEmpty {
                Section("Fandoms on AO3") {
                    ForEach(matches.ao3Fandoms, id: \.id) { fandom in
                        Button {
                            onSearchFandom(fandom.name)
                        } label: {
                            HStack {
                                Label(fandom.name, systemImage: "books.vertical")
                                Spacer()
                                if let count = fandom.workCount {
                                    Text(count.formatted(.number.notation(.compactName)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !tags.isEmpty {
                Section("Your Tags") {
                    ForEach(tags) { tag in
                        Button { router.filterLibrary(.userTag, tag.name) } label: {
                            Label(tag.name, systemImage: "tag")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !matchedCollections.isEmpty {
                Section("Collections") {
                    ForEach(matchedCollections) { collection in
                        NavigationLink(value: collection) {
                            Label(collection.name, systemImage: "square.stack")
                        }
                        // Library's collection cards have this menu (T-339).
                        .collectionCardMenu(collection)
                    }
                }
            }
        }
        .cardList()
        .libraryWorkRemovalConfirmations(pendingDelete: $pendingDelete, pendingRemoval: $pendingRemoval)
    }

    private func toggle(_ work: SavedWork) {
        if selection.contains(work.id) {
            selection.remove(work.id)
        } else {
            selection.insert(work.id)
        }
    }
}
