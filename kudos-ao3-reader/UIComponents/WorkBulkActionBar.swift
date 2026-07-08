import SwiftData
import SwiftUI

/// The bulk-action controls shown while a selection is active on any surface with
/// multiple local work cards — Delete / Save / Favorite, mirroring LibraryView's
/// own bulk action bar so selection behaves consistently everywhere it appears.
/// Delete always confirms (a batch, can't be undone); Save/Favorite are stackable
/// toggles that leave selection mode active.
struct WorkBulkActionBar: View {
    let selectedWorks: [SavedWork]
    /// Called after a confirmed bulk delete, so the caller can exit selection mode.
    var onDeleted: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var themeManager
    @State private var confirmDelete = false

    private var allSaved: Bool {
        !selectedWorks.isEmpty && selectedWorks.allSatisfy(\.isSaved)
    }

    private var allFavorited: Bool {
        !selectedWorks.isEmpty && selectedWorks.allSatisfy(\.isFavorite)
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

        Button {
            bulkSave()
        } label: {
            Label(allSaved ? "Saved" : "Save", systemImage: allSaved ? "bookmark.fill" : "bookmark")
        }
        .tint(allSaved ? themeManager.accentColor : nil)
        .disabled(selectedWorks.isEmpty)

        Spacer()

        Button {
            bulkFavorite()
        } label: {
            Label(allFavorited ? "Favorited" : "Favorite", systemImage: allFavorited ? "star.fill" : "star")
        }
        .tint(allFavorited ? themeManager.accentColor : nil)
        .disabled(selectedWorks.isEmpty)
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
}
