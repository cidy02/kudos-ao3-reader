import SwiftData
import SwiftUI

/// The bulk-action controls shown while a selection is active on any surface with
/// multiple local work cards, consistent everywhere it appears: Delete on the left
/// (always confirms — a batch, can't be undone), an "Actions" pill in the middle
/// holding every other bulk action (mirrors the single-item long-press context
/// menu, minus Read/Details which don't apply to a multi-selection), and a
/// checkmark on the right to exit selection mode without deleting anything.
struct WorkBulkActionBar: View {
    let selectedWorks: [SavedWork]
    /// Called after a confirmed bulk delete, so the caller can exit selection mode.
    var onDeleted: () -> Void = {}
    /// Called when the checkmark is tapped to exit selection mode without deleting.
    var onDone: () -> Void = {}

    @Environment(\.modelContext) private var context
    @State private var confirmDelete = false
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

    private var deleteMessage: String {
        let base = "The selected works will be moved to Recently Deleted. "
            + "You can restore them anytime in the next 90 days."
        guard selectedWorks.contains(where: \.ao3Unavailable) else { return base }
        return base + " Some of these are no longer available on AO3 — "
            + "if you don't restore them in time, they can't be re-saved afterward."
    }

    var body: some View {
        Button(role: .destructive) {
            confirmDelete = true
        } label: {
            Label("Delete", systemImage: "trash")
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
                Label(
                    allFinished ? "Mark as Still Reading" : "Mark as Finished",
                    systemImage: allFinished ? "arrow.uturn.backward.circle" : "checkmark.circle"
                )
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
            "Delete \(selectedWorks.count) work\(selectedWorks.count == 1 ? "" : "s")?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { bulkDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    private func bulkDelete() {
        for work in selectedWorks {
            PreservedWorkService.softDelete(work, in: context)
        }
        onDeleted()
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
                Task { await ReadingQueueService.addToSavedForLater(work, in: context) }
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

/// "Select All"/"Deselect All" toggle — takes over the top-right slot that used to
/// hold "Done" now that Done lives in `WorkBulkActionBar`'s checkmark instead.
struct SelectAllButton: View {
    let allSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(allSelected ? "Deselect All" : "Select All", action: action)
    }
}
