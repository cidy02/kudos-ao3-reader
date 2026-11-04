import SwiftData
import SwiftUI

/// A sheet, opened from inside a collection or a reading queue (1h's "+"), to pick
/// existing Library works and add them there. The complement to
/// `AddToCollectionView` / `AddToQueueView`, which start from a work and pick where
/// it goes; this starts from the destination and picks works.
///
/// One picker for both destinations: what differs is only which works the
/// destination can still take (`candidates` — `CollectionWorkPicker.candidates` /
/// `ReadingQueueService.appendCandidates`) and what adding does (`onAdd`), so the
/// search, selection and privacy rules below are written once.
struct AddLibraryWorksSheet: View {
    /// The destination's name, for the content heading — "Add to Shelf".
    let destinationName: String
    /// "collection" / "queue", for the empty state.
    let scopeName: String
    /// Real Library works the destination doesn't hold yet.
    let candidates: ([SavedWork]) -> [SavedWork]
    /// Runs once, with the chosen works in the order this list shows them.
    let onAdd: ([SavedWork]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("hideMatureContent") private var hideMature = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }, sort: \SavedWork.dateAdded, order: .reverse)
    private var allWorks: [SavedWork]

    @State private var selection: Set<UUID>
    @State private var query = ""

    init(
        destinationName: String,
        scopeName: String,
        candidates: @escaping ([SavedWork]) -> [SavedWork],
        onAdd: @escaping ([SavedWork]) -> Void,
        initialSelection: Set<UUID> = []
    ) {
        self.destinationName = destinationName
        self.scopeName = scopeName
        self.candidates = candidates
        self.onAdd = onAdd
        _selection = State(initialValue: initialSelection)
    }

    /// The destination's candidates, minus what Hide mode keeps out of the
    /// Library — the same universe LibraryView's select mode uses, so the picker
    /// never offers a work twice or leaks a hidden one. The privacy filter stays
    /// here since it needs the live gate.
    private var eligibleWorks: [SavedWork] {
        Self.nameable(candidates(allWorks), gate: gate, hideMature: hideMature)
    }

    /// The works this sheet may name. This list shows titles and authors and its search
    /// matches them, so a work Blur mode blurs stays out like one Hide mode hides (a
    /// blurred work used to be listed here by name).
    static func nameable(_ works: [SavedWork], gate: PrivacyGate, hideMature: Bool) -> [SavedWork] {
        works.filter { !gate.isConcealed($0, enabled: hideMature) }
    }

    /// Narrows the candidates through the precomputed `WorkSearchIndex` text —
    /// the same case-/diacritic-insensitive AND-across-terms matching as Global
    /// Search (title, author, series, tags, …), replacing a per-keystroke
    /// lowercase rescan of title/author/every fandom of every library work.
    private func filteredWorks(in eligible: [SavedWork]) -> [SavedWork] {
        let terms = WorkSearchIndex.terms(from: query)
        guard !terms.isEmpty else { return eligible }
        return eligible.filter { WorkSearchIndex.matches($0, terms: terms) }
    }

    var body: some View {
        // Evaluated once per render — eligibility (library scan + privacy gate)
        // and the query match are shared by every branch below instead of being
        // recomputed by each `candidates`/`filtered` mention.
        let eligible = eligibleWorks
        let matches = filteredWorks(in: eligible)
        let chosen = Self.selectedWorks(from: eligible, selection: selection)
        // Hide mode can empty the picker on its own; that is not "nothing to add".
        let hiddenOnly = eligible.isEmpty && !candidates(allWorks).isEmpty
        NavigationStack {
            List {
                Group {
                    if hiddenOnly {
                        ContentUnavailableView {
                            Label("Mature works are hidden", systemImage: "eye.slash")
                        } description: {
                            Text("Hide Mature is hiding every work you can add here.")
                        } actions: {
                            MatureRevealToggle()
                        }
                    } else if eligible.isEmpty {
                        ContentUnavailableView {
                            Label("No works to add", systemImage: "square.stack")
                        } description: {
                            Text("Your Library has no works you can add to \(destinationName).")
                        }
                    } else {
                        ForEach(matches) { work in
                            SensitiveWorkRow(
                                work: work,
                                isSelecting: true,
                                isSelected: selection.contains(work.id),
                                onToggleSelection: { toggle(work) },
                                showsSummary: false,
                                showsTags: false,
                                showsProgress: false,
                                leadingSelection: true,
                                showsSeparator: work.id != matches.last?.id
                            )
                            .cardRow(isSelected: selection.contains(work.id), chrome: .plain)
                            .listRowBackground(
                                ZStack {
                                    themeManager.appTheme.cardSurface
                                    if selection.contains(work.id) {
                                        themeManager.effectiveTint.opacity(0.08)
                                    }
                                }
                            )
                        }
                        if matches.isEmpty {
                            ContentUnavailableView {
                                Label("No matching works", systemImage: "magnifyingglass")
                            } description: {
                                Text("Your Library has no works matching “\(query)”.")
                            } actions: {
                                Button("Clear Search") { query = "" }
                            }
                        }
                    }
                }
                .appThemedRows()
            }
            .appThemedScroll()
            #if os(iOS)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search your library"
            )
            #else
            .searchable(text: $query, prompt: "Search your library")
            #endif
            .wrappingInlineTitle(
                chosen.count > 0 ? "Add Works · \(chosen.count) selected" : "Add Works",
                accessibilityHidden: false
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if !chosen.isEmpty { onAdd(chosen) }
                        dismiss()
                    }
                    .sheetConfirmStyle()
                    .disabled(chosen.isEmpty)
                }
                // Every works list offers the reveal while Hide Mature is on.
                if hideMature, !hiddenOnly {
                    ToolbarItem(placement: .primaryAction) { MatureRevealToggle() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func toggle(_ work: SavedWork) {
        if selection.contains(work.id) {
            selection.remove(work.id)
        } else {
            selection.insert(work.id)
        }
    }

    static func selectedWorks(from eligible: [SavedWork], selection: Set<UUID>) -> [SavedWork] {
        eligible.filter { selection.contains($0.id) }
    }

    static func confirmationTitle(count: Int) -> String {
        count == 0 ? "Add" : "Add \(count)"
    }
}
