import SwiftData
import SwiftUI

/// A work waiting on its Remove ask: off History (a hide marker), or out of
/// every queue for a queue-only work. Neither deletes anything.
struct PendingLibraryRemoval: Identifiable {
    let work: SavedWork
    let fromHistory: Bool
    var id: UUID { work.id }
}

extension View {
    /// The Library's swipe actions for one work row, shared by a section page and
    /// the Library dashboard's ledger so a work swipes the same way in both.
    ///
    /// The asks live on the screen (`libraryWorkRemovalConfirmations`), not the
    /// row: a swipe closes as the button fires, and an alert owned by the row
    /// that just closed is the kind that fails to present.
    func libraryWorkSwipeActions(
        _ work: SavedWork,
        kind: LibrarySectionKind,
        isFavoritesList: Bool,
        pendingDelete: Binding<SavedWork?>,
        pendingRemoval: Binding<PendingLibraryRemoval?>
    ) -> some View {
        modifier(LibraryWorkSwipeActions(
            work: work,
            kind: kind,
            isFavoritesList: isFavoritesList,
            pendingDelete: pendingDelete,
            pendingRemoval: pendingRemoval
        ))
    }

    /// The two asks behind `libraryWorkSwipeActions`, attached once per screen.
    func libraryWorkRemovalConfirmations(
        pendingDelete: Binding<SavedWork?>,
        pendingRemoval: Binding<PendingLibraryRemoval?>
    ) -> some View {
        modifier(LibraryWorkRemovalConfirmations(pendingDelete: pendingDelete, pendingRemoval: pendingRemoval))
    }
}

private struct LibraryWorkSwipeActions: ViewModifier {
    let work: SavedWork
    let kind: LibrarySectionKind
    /// Favorites' Works scope, where the star itself is what a row can lose.
    let isFavoritesList: Bool
    @Binding var pendingDelete: SavedWork?
    @Binding var pendingRemoval: PendingLibraryRemoval?

    @Environment(\.modelContext) private var context
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true

    func body(content: Content) -> some View {
        content
            // No full swipe: a flick should not un-keep a download.
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                // 1ah / 1ai / 1aj lead with Queue: Save for Later is the thing to
                // do with a work you are looking back over.
                if kind == .history || isFavoritesList {
                    SaveForLaterButton(work: work)
                }
                WorkDownloadButton(work: work)

                // Favorites carries Unfavorite on the trailing edge instead (1aj), and
                // one row offering the same toggle on both edges is two answers to
                // one question.
                if !isFavoritesList {
                    Button {
                        work.isFavorite.toggle()
                        work.markModified()
                        try? context.save()
                    } label: {
                        let labels = WorkActionLabels.favorite(isFavorite: work.isFavorite)
                        Label(labels.title, systemImage: labels.systemImage)
                    }
                    .tint(.yellow)
                }
            }
            // No full swipe: every button here removes something, and each asks.
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if isFavoritesList {
                    // 1aj draws the unstar where every other section has Delete: on the
                    // page that is *about* the star, taking it off is the removal,
                    // and soft-deleting the whole work from here was out of scale.
                    Button {
                        work.isFavorite = false
                        work.markModified()
                        try? context.save()
                    } label: {
                        let label = WorkActionLabels.favorite(isFavorite: true)
                        Label(label.title, systemImage: label.systemImage)
                    }
                    .tint(.yellow)
                } else if kind == .history || work.isQueueOnlyWork {
                    // History — 1ah: "Remove clears it from history, which is the only
                    // destructive thing this page can do." A hide marker, never a
                    // delete — reading the work again brings it back.
                    // Queue-only works keep a preserved EPUB and must never be hard-deleted
                    // by a generic Library swipe. Removing the queue membership is
                    // non-destructive (the record and EPUB survive); explicit deletion of a
                    // preserved copy lives behind confirmation in Queue Storage.
                    Button(role: .destructive) {
                        pendingRemoval = PendingLibraryRemoval(work: work, fromHistory: kind == .history)
                    } label: {
                        Label("Remove", systemImage: kind == .history ? "clock.badge.xmark" : "minus.circle")
                    }
                } else {
                    Button(role: .destructive) {
                        if confirmBeforeDelete {
                            pendingDelete = work
                        } else {
                            PreservedWorkService.softDelete(work, in: context)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
    }
}

private struct LibraryWorkRemovalConfirmations: ViewModifier {
    @Binding var pendingDelete: SavedWork?
    @Binding var pendingRemoval: PendingLibraryRemoval?

    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .deleteConfirmation(
                for: $pendingDelete,
                title: "Delete this work?",
                confirmLabel: "Delete",
                message: { PreservedWorkService.deleteConfirmationMessage(for: $0) },
                perform: { PreservedWorkService.softDelete($0, in: context) }
            )
            // Taking a work off a list asks first everywhere else, so it asks
            // here too (pass2-9).
            .destructiveConfirmation(
                for: $pendingRemoval,
                title: "Remove this work?",
                confirmLabel: "Remove",
                message: { removal in
                    removal.fromHistory
                        ? "“\(removal.work.title)” will leave your reading history. Reading it again brings it back."
                        : "“\(removal.work.title)” will leave every queue it is in. The work stays on this device."
                },
                perform: { removal in
                    if removal.fromHistory {
                        WorkLifecycle.removeFromHistory(removal.work, in: context)
                    } else {
                        ReadingQueueService.removeFromAllQueues(removal.work, in: context)
                    }
                }
            )
    }
}
