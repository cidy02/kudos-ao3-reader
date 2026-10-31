import SwiftData
import SwiftUI

/// All Works, from the Library header, or the Imported shelf. Both are ledger
/// lists (List / Grid). Imported is every saved work that did not come from AO3.
struct LibraryCatalogueDestination: Hashable {
    enum Kind: String, Hashable {
        case allWorks
        case imported
    }

    var kind: Kind
}

struct LibraryCatalogueListView: View {
    let kind: LibraryCatalogueDestination.Kind

    @Environment(\.modelContext) private var context
    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var themeManager
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }, sort: \SavedWork.dateAdded, order: .reverse)
    private var works: [SavedWork]
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @AppStorage private var arrangement: WorkListArrangement
    @State private var pendingDelete: SavedWork?
    @State private var pendingRemoval: PendingLibraryRemoval?
    @State private var isSelecting = false
    @State private var selection = Set<UUID>()

    init(kind: LibraryCatalogueDestination.Kind) {
        self.kind = kind
        let key = kind == .allWorks
            ? WorkListKeys.allWorksArrangement
            : WorkListKeys.importedArrangement
        let resolved = WorkListLayoutMigration.resolve(
            arrangementKey: key,
            legacyDisplayModeKey: nil
        )
        _arrangement = AppStorage(wrappedValue: resolved, key)
    }

    private var title: String {
        kind == .allWorks ? "All Works" : "Imported"
    }

    private var items: [SavedWork] {
        works.filter { work in
            guard !work.isQueueOnlyWork, passesPrivacy(work) else { return false }
            if kind == .imported {
                return LibraryShelfID.isImported(origin: work.origin, isQueueOnly: false)
            }
            return true
        }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView {
                    Label(title, systemImage: kind == .imported ? "doc" : "books.vertical")
                } description: {
                    Text(kind == .imported
                        ? "Works you import, or bring in from another site, appear here."
                        : "Works you save appear here.")
                }
            } else if arrangement == .grid {
                grid
            } else {
                list
            }
        }
        .navigationTitle(isSelecting ? WorkSelectionTitle.text(selectedCount: selectedWorks.count) : title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                if isSelecting {
                    ToolbarItem(placement: .confirmationAction) {
                        SelectAllButton(allSelected: allSelected, action: toggleSelectAll)
                    }
                    #if os(iOS)
                    ToolbarItemGroup(placement: .bottomBar) {
                        WorkBulkActionBar(
                            selectedWorks: selectedWorks,
                            onDeleted: exitSelectMode,
                            onDone: exitSelectMode
                        )
                    }
                    #else
                    ToolbarItemGroup(placement: .primaryAction) {
                        WorkBulkActionBar(
                            selectedWorks: selectedWorks,
                            onDeleted: exitSelectMode,
                            onDone: exitSelectMode
                        )
                    }
                    #endif
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        WorkListMoreMenu {
                            ListGridMenuPicker(arrangement: $arrangement)
                        }
                    }
                }
            }
        #if os(iOS)
            .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
        #endif
            .libraryWorkRemovalConfirmations(
                pendingDelete: $pendingDelete,
                pendingRemoval: $pendingRemoval
            )
    }

    private var list: some View {
        List {
            Section {
                Text(LibraryPageArrangement.workCountPhrase(items.count) + " · newest first")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                ForEach(items) { work in
                    SensitiveWorkRow(
                        work: work,
                        openMode: .reader,
                        onSelect: nil,
                        presentation: .ledger,
                        showsFavoriteStar: true,
                        showsFullLedgerStats: true,
                        showsSummary: false
                    )
                    .libraryWorkSwipeActions(
                        work,
                        kind: .downloaded,
                        isFavoritesList: false,
                        pendingDelete: $pendingDelete,
                        pendingRemoval: $pendingRemoval
                    )
                    .cardRow(isSelected: false)
                }
            }
        }
        .cardList()
        .subjectScreenWash(palette: themeManager.scopePalette, role: .content)
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(LibraryPageArrangement.workCountPhrase(items.count) + " · newest first")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                CarouselCardGrid {
                    ForEach(items) { work in
                        if isSelecting {
                            SensitiveWorkCoverCard(
                                work: work,
                                isSelecting: true,
                                isSelected: selection.contains(work.id),
                                onToggleSelection: { toggleSelection(work) }
                            )
                            .localWorkContextMenu(work: work)
                        } else {
                            NavigationLink(value: LocalWorkDestination.reader(work)) {
                                SensitiveWorkCoverCard(work: work)
                            }
                            .buttonStyle(.plain)
                            .localWorkContextMenu(
                                work: work,
                                onSelect: { isSelecting = true; selection = [work.id] }
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .subjectScreenWash(palette: themeManager.scopePalette, role: .content)
    }

    private func passesPrivacy(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    private var selectedWorks: [SavedWork] {
        items.filter { selection.contains($0.id) }
    }

    private var allSelected: Bool {
        let ids = Set(items.map(\.id))
        return !ids.isEmpty && ids.isSubset(of: selection)
    }

    private func toggleSelection(_ work: SavedWork) {
        if selection.contains(work.id) {
            selection.remove(work.id)
        } else {
            selection.insert(work.id)
        }
    }

    private func toggleSelectAll() {
        selection = allSelected ? [] : Set(items.map(\.id))
    }

    private func exitSelectMode() {
        isSelecting = false
        selection = []
    }
}
