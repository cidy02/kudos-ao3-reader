import SwiftData
import SwiftUI

/// Selection state + bulk actions shared by every remote-work list surface —
/// Browse's `FandomWorksView`/`TagWorksView`, `AuthorProfileView`'s works tab,
/// and Search results. Each host view owns one controller in `@State`, shows
/// `RemoteWorkSelectionToolbar` while selecting, and applies
/// `.remoteWorkSelectionChrome(_:)` once for the sheets/alert/cancel plumbing.
///
/// The chrome (and the batch task itself) deliberately belongs to the host, not
/// the selecting toolbar: an in-flight batch, its failure alert, and a presented
/// Add-to sheet all survive leaving selection mode, exactly as they did when
/// each view carried this state itself. Rows, pagination, and the non-selecting
/// toolbar stay per-surface — they genuinely differ.
@MainActor
@Observable
final class RemoteWorkSelectionController {
    var isSelecting = false
    var selection: Set<Int> = []
    private(set) var isProcessingBatch = false
    fileprivate var batchTask: Task<Void, Never>?
    fileprivate var resolvedQueueWorks: [SavedWork] = []
    fileprivate var showingAddToQueue = false
    fileprivate var resolvedCollectionWorks: [SavedWork] = []
    fileprivate var showingAddToCollection = false
    fileprivate var batchActionError: String?

    /// The selected summaries, in the host's current display order.
    func selected(in results: [AO3WorkSummary]) -> [AO3WorkSummary] {
        results.filter { selection.contains($0.id) }
    }

    func toggle(_ work: AO3WorkSummary) {
        if selection.contains(work.id) {
            selection.remove(work.id)
        } else {
            selection.insert(work.id)
        }
    }

    func exitSelectMode() {
        isSelecting = false
        selection = []
    }

    // MARK: Bulk actions

    // Each resolves the selected remote summaries to local works one at a time —
    // never bursting concurrent AO3 requests (see RemoteWorkBulkActions.swift).

    fileprivate func bulkSave(_ selected: [AO3WorkSummary], in context: ModelContext) async {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        defer { isProcessingBatch = false }
        batchActionError = await resolveSelectedRemoteWorks(selected, in: context) { works in
            for work in works {
                WorkLifecycle.setSaved(work, true, in: context)
            }
        }
    }

    fileprivate func bulkSaveForLater(_ selected: [AO3WorkSummary], in context: ModelContext) async {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        defer { isProcessingBatch = false }
        batchActionError = await bulkSaveForLaterRemote(selected, in: context)
    }

    fileprivate func bulkAddToCollection(_ selected: [AO3WorkSummary], in context: ModelContext) async {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        defer { isProcessingBatch = false }
        batchActionError = await resolveSelectedRemoteWorks(selected, in: context) { works in
            resolvedCollectionWorks = works
            showingAddToCollection = true
        }
    }

    fileprivate func bulkAddToQueue(_ selected: [AO3WorkSummary], in context: ModelContext) async {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        defer { isProcessingBatch = false }
        batchActionError = await resolveSelectedRemoteWorks(selected, in: context) { works in
            resolvedQueueWorks = works
            showingAddToQueue = true
        }
    }
}

/// The selecting-mode toolbar: "Done" plus the bulk-action bar (bottom bar on
/// iOS, primary action on macOS).
struct RemoteWorkSelectionToolbar: ToolbarContent {
    let controller: RemoteWorkSelectionController
    /// Evaluated when a bulk button's task runs, so it acts on the live selection.
    let selectedSummaries: () -> [AO3WorkSummary]

    var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { controller.exitSelectMode() }
        }
        #if os(iOS)
        ToolbarItemGroup(placement: .bottomBar) {
            RemoteWorkBulkActionBar(controller: controller, selectedSummaries: selectedSummaries)
        }
        #else
        ToolbarItemGroup(placement: .primaryAction) {
            RemoteWorkBulkActionBar(controller: controller, selectedSummaries: selectedSummaries)
        }
        #endif
    }
}

/// The four shared bulk actions over the current selection, mirroring
/// `LibraryView`'s local `WorkBulkActionBar`. Buttons stay disabled while a
/// batch runs; the trailing spinner reports progress.
struct RemoteWorkBulkActionBar: View {
    let controller: RemoteWorkSelectionController
    let selectedSummaries: () -> [AO3WorkSummary]

    @Environment(\.modelContext) private var context

    var body: some View {
        Button {
            run { await controller.bulkSave(selectedSummaries(), in: context) }
        } label: {
            Label("Save", systemImage: "bookmark")
        }
        .disabled(controller.selection.isEmpty || controller.isProcessingBatch)

        Spacer()

        Button {
            run { await controller.bulkSaveForLater(selectedSummaries(), in: context) }
        } label: {
            Label("Save for Later", systemImage: "clock.arrow.circlepath")
        }
        .disabled(controller.selection.isEmpty || controller.isProcessingBatch)

        Spacer()

        Button {
            run { await controller.bulkAddToCollection(selectedSummaries(), in: context) }
        } label: {
            Label("Add to Collection", systemImage: "square.stack")
        }
        .disabled(controller.selection.isEmpty || controller.isProcessingBatch)

        Spacer()

        Button {
            run { await controller.bulkAddToQueue(selectedSummaries(), in: context) }
        } label: {
            Label("Add to Queue", systemImage: "list.bullet.rectangle")
        }
        .disabled(controller.selection.isEmpty || controller.isProcessingBatch)

        if controller.isProcessingBatch {
            ProgressView()
                .controlSize(.small)
        }
    }

    private func run(_ operation: @escaping @MainActor () async -> Void) {
        controller.batchTask = Task { await operation() }
    }
}

/// One remote work row that flips between navigation (normal) and
/// tap-to-toggle-selection (selecting), with the shared selection accessibility
/// treatment. Used by Browse's fandom/tag works and Search results;
/// `AuthorProfileView` keeps its own rows (a different row component).
struct SelectableAO3WorkRow: View {
    let work: AO3WorkSummary
    let expandAll: Bool
    let controller: RemoteWorkSelectionController

    var body: some View {
        let row = AO3WorkRow(
            work: work,
            expandAll: expandAll,
            isSelecting: controller.isSelecting,
            isSelected: controller.selection.contains(work.id)
        )
        if controller.isSelecting {
            let isSelected = controller.selection.contains(work.id)
            Button { controller.toggle(work) } label: { row }
                .buttonStyle(.plain)
                .accessibilityLabel(work.title)
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            row.cardNavigation(to: work)
        }
    }
}

extension View {
    /// Host-side plumbing for a `RemoteWorkSelectionController`: the Add to
    /// Queue/Collection sheets, the batch failure alert, and cancelling the
    /// in-flight batch when the surface goes away. Applied to the host view
    /// (not the selecting toolbar) so all three outlive selection mode.
    /// Unstructured batch tasks outlive the view unless explicitly cancelled;
    /// the bulk loops bail out cleanly on CancellationError.
    func remoteWorkSelectionChrome(_ controller: RemoteWorkSelectionController) -> some View {
        @Bindable var controller = controller
        return self
            .sheet(isPresented: $controller.showingAddToQueue) {
                AddToQueueView(works: controller.resolvedQueueWorks)
            }
            .sheet(isPresented: $controller.showingAddToCollection) {
                AddToCollectionView(works: controller.resolvedCollectionWorks)
            }
            .alert(
                "Action Failed",
                isPresented: Binding(
                    get: { controller.batchActionError != nil },
                    set: { if !$0 { controller.batchActionError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { controller.batchActionError = nil }
            } message: {
                Text(controller.batchActionError ?? "")
            }
            .onDisappear { controller.batchTask?.cancel() }
    }
}
