import SwiftData
import SwiftUI

/// The bulk-action bar for a single Reading Queue's or Collection's selection mode.
/// Shaped like `WorkBulkActionBar` (an "Actions" menu of secondary actions plus a
/// Done checkmark), but the primary action is scoped membership removal rather than
/// a library-wide delete — removing works from one queue/collection doesn't delete
/// or unsave them, so it gets its own confirmation copy and its own removal call
/// rather than reusing `WorkBulkActionBar`'s hardcoded Delete/soft-delete path.
struct ScopedRemovalBulkActionBar: View {
    let selectedWorks: [SavedWork]
    /// e.g. "Remove from Queue" / "Remove from Collection".
    let removeLabel: String
    /// e.g. "queue" / "collection" — used in the confirmation copy.
    let scopeName: String
    /// Performs the scoped removal for every selected work. Called only after the
    /// user confirms.
    var onRemove: () -> Void
    /// Called after a confirmed removal, and when the checkmark exits selection
    /// mode without removing anything.
    var onDone: () -> Void = {}
    /// 1bg: a queue's bar puts "the four things a queue can do to a selection" —
    /// Download · Move to · Tag · Remove — up front, with the rest in a "…" menu.
    /// Collections keep the Remove + Actions menu layout.
    var showsQueueActions = false

    @Environment(\.modelContext) private var context
    @Environment(DownloadQueue.self) private var downloadQueue
    @State private var confirmRemove = false
    @State private var showingAddToQueue = false
    @State private var showingAddToCollection = false
    @State private var showingTagSheet = false
    /// 1bg's Move to. Same destination picker as Add to Queue — the difference is
    /// what happens after, so it is one flag rather than a second sheet.
    @State private var showingMoveToQueue = false
    /// Queue-membership count across the selection, sampled when the move picker
    /// opens. The picker is shared with Add to Queue and cannot tell this bar
    /// whether anything was chosen, so a plain `onDismiss: onRemove` would strip
    /// the works out of this queue even when the reader pressed Cancel.
    @State private var membershipBeforeMove = 0
    @State private var isDownloading = false

    private var allFavorited: Bool {
        !selectedWorks.isEmpty && selectedWorks.allSatisfy(\.isFavorite)
    }

    private var allSavedForLater: Bool {
        !selectedWorks.isEmpty && selectedWorks.allSatisfy(\.isInSavedForLaterQueue)
    }

    private var allFinished: Bool {
        !selectedWorks.isEmpty && selectedWorks.allSatisfy(\.isFinished)
    }

    var body: some View {
        if showsQueueActions {
            queueActions
        } else {
            removeButton

            Spacer()

            Menu {
                libraryActions
                // 1bg's Move to. Its own note calls this two verbs — add AND remove —
                // which is why it reuses the destination picker and then runs the
                // scoped removal this bar already owns, rather than being a variant
                // of Add to Queue that quietly leaves the work in both places.
                Button(action: startMove) {
                    Label("Move to Queue", systemImage: "arrow.right.square")
                }
                // 1bg names Tag as one of the four things a queue can do to a
                // selection. The sheet already existed for 1af and is already wired
                // into Library's own bar; both surfaces that mount this bar — a queue
                // and a collection — hold local works, so it applies to each.
                Button {
                    showingTagSheet = true
                } label: {
                    Label("Tag", systemImage: "tag")
                }
                // 1bg's Download. The "Download" item above it sets `isSaved`, which
                // only stops an EPUB being freed — for a work whose copy is already
                // gone it changes a flag and downloads nothing. This fetches.
                Button {
                    Task { await bulkDownload() }
                } label: {
                    Label("Download missing copies", systemImage: WorkActionLabels.downloadEmptySymbol)
                }
                .disabled(isDownloading || missingCopies.isEmpty)
                finishedAction
            } label: {
                Text("Actions")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
            }
            .disabled(selectedWorks.isEmpty)
        }

        Spacer()

        Button {
            onDone()
        } label: {
            Image(systemName: "checkmark")
        }
        .accessibilityLabel("Done")
        .sheet(isPresented: $showingAddToQueue) {
            AddToQueueView(works: selectedWorks)
        }
        // The removal runs on dismiss rather than inside the picker: the picker
        // is shared with Add to Queue and must not learn about this scope. It
        // runs ONLY if the selection actually joined something, so cancelling
        // the picker leaves the works exactly where they were.
        .sheet(isPresented: $showingMoveToQueue, onDismiss: {
            guard totalQueueMemberships > membershipBeforeMove else { return }
            onRemove()
            // The moved rows have left this list; the selection went with them.
            onDone()
        }) {
            AddToQueueView(works: selectedWorks)
        }
        .sheet(isPresented: $showingAddToCollection) {
            AddToCollectionView(works: selectedWorks)
        }
        .sheet(isPresented: $showingTagSheet) {
            WorkBulkTagSheet(works: selectedWorks)
        }
        .confirmationDialog(
            "Remove \(selectedWorks.count) work\(selectedWorks.count == 1 ? "" : "s")?",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                onRemove()
                onDone()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The selected works will no longer be in this \(scopeName). "
                + "They stay in your Library either way.")
        }
    }

    /// 1bg's four, then "…" holding everything the Actions menu has that they
    /// don't — nothing the Collections layout offers is lost here.
    @ViewBuilder
    private var queueActions: some View {
        Button {
            Task { await bulkDownload() }
        } label: {
            Label("Download", systemImage: WorkActionLabels.downloadEmptySymbol)
        }
        .disabled(isDownloading || missingCopies.isEmpty)
        Spacer()
        Button(action: startMove) {
            Label("Move to", systemImage: "arrow.right.square")
        }
        .disabled(selectedWorks.isEmpty)
        Spacer()
        Button {
            showingTagSheet = true
        } label: {
            Label("Tag", systemImage: "tag")
        }
        .disabled(selectedWorks.isEmpty)
        Spacer()
        removeButton
        Spacer()
        Menu {
            libraryActions
            finishedAction
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .disabled(selectedWorks.isEmpty)
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            confirmRemove = true
        } label: {
            Label(removeLabel, systemImage: "minus.circle")
        }
        .disabled(selectedWorks.isEmpty)
    }

    /// Save, Favorite, Saved for Later, Add to Queue, Add to Collection — the
    /// same five, in the same order, in both layouts' menus.
    @ViewBuilder
    private var libraryActions: some View {
        if let download = WorkDownload.bulkAction(for: selectedWorks) {
            Button {
                Task { await WorkDownload.performBulk(download, on: selectedWorks, in: context, queue: downloadQueue) }
            } label: {
                let label = WorkDownload.bulkLabel(download)
                Label(label.title, systemImage: label.systemImage)
            }
        }
        Button {
            bulkFavorite()
        } label: {
            Label(allFavorited ? "Favorited" : "Favorite", systemImage: allFavorited ? "star.fill" : "star")
        }
        Button {
            bulkToggleSavedForLater()
        } label: {
            Label(
                WorkActionLabels.savedForLater(isQueued: allSavedForLater).title,
                systemImage: WorkActionLabels.savedForLater(isQueued: allSavedForLater).systemImage
            )
        }
        Button {
            showingAddToQueue = true
        } label: {
            Label("Add to Queue", systemImage: "list.bullet.rectangle")
        }
        Button {
            showingAddToCollection = true
        } label: {
            Label("Add to Collection", systemImage: "square.stack")
        }
    }

    private var finishedAction: some View {
        Button {
            bulkToggleFinished()
        } label: {
            let labels = WorkActionLabels.finished(isFinished: allFinished)
            Label(labels.title, systemImage: labels.systemImage)
        }
    }

    private func startMove() {
        membershipBeforeMove = totalQueueMemberships
        showingMoveToQueue = true
    }

    private var totalQueueMemberships: Int {
        selectedWorks.reduce(0) { total, work in
            total + work.queueMemberships.filter { !$0.isPendingDeletion }.count
        }
    }

    /// Works whose EPUB is gone — the only ones a download can do anything for.
    /// Re-fetching a work that already has one would reset its reading position
    /// for no gain.
    private var missingCopies: [SavedWork] {
        selectedWorks.filter { !WorkReaderPreparation.hasReadableEPUB(for: $0) }
    }

    /// Sequential, not concurrent: this is the same AO3 endpoint per work, and a
    /// parallel burst over a large selection is the kind of thing that gets an
    /// app rate-limited. A failure on one work does not stop the rest — the work
    /// simply still has no copy, which is the state it was already in.
    private func bulkDownload() async {
        isDownloading = true
        defer { isDownloading = false }
        for work in missingCopies {
            try? await WorkReaderPreparation.restoreReadableEPUB(for: work, in: context)
        }
    }

    private func bulkFavorite() {
        let shouldFavorite = !allFavorited
        let now = Date()
        for work in selectedWorks {
            work.isFavorite = shouldFavorite
            work.markModified(now)
        }
        try? context.save()
    }

    private func bulkToggleSavedForLater() {
        let shouldSave = !allSavedForLater
        for work in selectedWorks {
            if shouldSave {
                guard !work.isInSavedForLaterQueue else { continue }
                Task { @MainActor in
                    _ = await ReadingQueueService.addToSavedForLater(work, in: context)
                }
            } else {
                guard work.isInSavedForLaterQueue else { continue }
                ReadingQueueService.removeFromQueueAndDeleteIfQueueOnly(
                    work,
                    from: ReadingQueueService.ensureSavedForLaterQueue(in: context),
                    in: context
                )
            }
        }
    }

    private func bulkToggleFinished() {
        let shouldFinish = !allFinished
        for work in selectedWorks {
            if shouldFinish {
                WorkLifecycle.markFinished(work, in: context)
            } else {
                WorkLifecycle.markStillReading(work, in: context)
            }
        }
    }
}
