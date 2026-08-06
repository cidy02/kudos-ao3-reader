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
                Label(allSaved ? "Saved" : "Save", systemImage: allSaved ? "bookmark.fill" : "bookmark")
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
                    allSavedForLater ? "Remove from Saved for Later" : "Save for Later",
                    systemImage: allSavedForLater ? "bookmark.slash" : "clock.arrow.circlepath"
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
        .sheet(isPresented: $showingAddToCollection) {
            AddToCollectionView(works: selectedWorks)
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
