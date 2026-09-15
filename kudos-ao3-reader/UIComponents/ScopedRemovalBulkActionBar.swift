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

    @Environment(\.modelContext) private var context
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

    private var allSaved: Bool {
        !selectedWorks.isEmpty && selectedWorks.allSatisfy(\.isSaved)
    }

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
        Button(role: .destructive) {
            confirmRemove = true
        } label: {
            Label(removeLabel, systemImage: "minus.circle")
        }
        .disabled(selectedWorks.isEmpty)

        Spacer()

        Menu {
            Button {
                bulkSave()
            } label: {
                Label(
                    WorkActionLabels.saved(isSaved: allSaved).title,
                    systemImage: WorkActionLabels.saved(isSaved: allSaved).systemImage
                )
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
            // 1bg's Move to. Its own note calls this two verbs — add AND remove —
            // which is why it reuses the destination picker and then runs the
            // scoped removal this bar already owns, rather than being a variant
            // of Add to Queue that quietly leaves the work in both places.
            Button {
                membershipBeforeMove = totalQueueMemberships
                showingMoveToQueue = true
            } label: {
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
            Button {
                bulkToggleFinished()
            } label: {
                let labels = WorkActionLabels.finished(isFinished: allFinished)
                Label(labels.title, systemImage: labels.systemImage)
            }
        } label: {
            Text("Actions")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
        }
        .disabled(selectedWorks.isEmpty)

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

    private func bulkSave() {
        let shouldSave = !allSaved
        for work in selectedWorks {
            WorkLifecycle.setSaved(work, shouldSave, in: context)
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
