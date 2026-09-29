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
    /// The destination's name, for the title — "Add to Shelf".
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
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }, sort: \SavedWork.dateAdded, order: .reverse)
    private var allWorks: [SavedWork]

    @State private var selection = Set<UUID>()
    @State private var query = ""

    /// The destination's candidates, minus what Hide mode keeps out of the
    /// Library — the same universe LibraryView's select mode uses, so the picker
    /// never offers a work twice or leaks a hidden one. The privacy filter stays
    /// here since it needs the live gate.
    private var eligibleWorks: [SavedWork] {
        candidates(allWorks).filter { !gate.isHidden($0, enabled: hideMature, mode: matureMode) }
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
        // Hide mode can empty the picker on its own; that is not "nothing to add".
        let hiddenOnly = eligible.isEmpty && !candidates(allWorks).isEmpty
        NavigationStack {
            Group {
                if hiddenOnly {
                    ContentUnavailableView {
                        Label("Mature works are hidden", systemImage: "eye.slash")
                    } description: {
                        Text("The works you could add here are hidden by Hide Mature.")
                    } actions: {
                        MatureRevealToggle()
                    }
                } else if eligible.isEmpty {
                    ContentUnavailableView {
                        Label("No works to add", systemImage: "square.stack")
                    } description: {
                        Text("Every work in your library is already in this \(scopeName), "
                            + "or there are no works to add yet.")
                    }
                } else {
                    List {
                        ForEach(matches) { work in
                            Button { toggle(work) } label: { row(work) }
                                .buttonStyle(.plain)
                        }
                        .appThemedRows()
                        if matches.isEmpty {
                            ContentUnavailableView {
                                Label("No matching works", systemImage: "magnifyingglass")
                            } description: {
                                Text("Nothing in your library matches “\(query)”.")
                            } actions: {
                                Button("Clear Search") { query = "" }
                            }
                            .appThemedRows()
                        }
                    }
                    .appThemedScroll()
                    // Default placement — .navigationBarDrawer is iOS-only and would
                    // break the macOS build.
                    .searchable(text: $query, prompt: "Search your library")
                }
            }
            .navigationTitle("Add to \(destinationName)")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Self.confirmationTitle(count: selection.count)) { addSelected(from: eligible) }
                            .disabled(selection.isEmpty)
                    }
                    // Every works list offers the reveal while Hide Mature is on.
                    if hideMature, !hiddenOnly {
                        ToolbarItem(placement: .primaryAction) { MatureRevealToggle() }
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }

    private func row(_ work: SavedWork) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(work.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !work.author.isEmpty {
                    AO3AuthorBylineView(
                        displayText: work.author,
                        identities: work.verifiedAuthorIdentities,
                        font: .caption,
                        compact: true,
                        onOpenRoute: { route in
                            dismiss()
                            router.openAuthorProfile(route)
                        }
                    )
                }
            }
            Spacer(minLength: 8)
            Image(systemName: selection.contains(work.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selection.contains(work.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .imageScale(.large)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(selection.contains(work.id) ? "Selected" : "Not selected")
        .accessibilityHint("Double-tap to \(selection.contains(work.id) ? "deselect" : "select") this work.")
    }

    private func toggle(_ work: SavedWork) {
        if selection.contains(work.id) {
            selection.remove(work.id)
        } else {
            selection.insert(work.id)
        }
    }

    private func addSelected(from eligible: [SavedWork]) {
        let chosen = eligible.filter { selection.contains($0.id) }
        if !chosen.isEmpty { onAdd(chosen) }
        dismiss()
    }

    static func confirmationTitle(count: Int) -> String {
        count == 0 ? "Add" : "Add \(count)"
    }
}
