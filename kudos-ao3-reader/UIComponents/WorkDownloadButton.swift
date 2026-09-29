import SwiftData
import SwiftUI

/// The one Download / Remove Download control rows and menus share, driven by
/// `WorkDownload`. Draws nothing when there is nothing to offer, and a work kept
/// by a queue or collection names its keeper instead of offering to remove it.
struct WorkDownloadButton: View {
    let work: SavedWork
    @Environment(\.modelContext) private var context

    var body: some View {
        if let action = WorkDownload.action(for: work) {
            let label = WorkDownload.label(action)
            Button {
                Task { try? await WorkDownload.perform(action, on: work, in: context) }
            } label: {
                Label(label.title, systemImage: label.systemImage)
            }
            .disabled(action.isInformational)
            .tint(.blue)
        }
    }
}

extension WorkDownload.Action {
    /// `keptBy` states why there is no Remove; it performs nothing.
    var isInformational: Bool {
        if case .keptBy = self { return true }
        return false
    }
}

/// Save for Later / Remove from Saved for Later as a row action — the swipe
/// 1ah, 1ai and 1aj draw first ("Queue").
struct SaveForLaterButton: View {
    let work: SavedWork
    @Environment(\.modelContext) private var context

    var body: some View {
        let label = WorkActionLabels.savedForLater(isQueued: work.isInSavedForLaterQueue)
        Button {
            ReadingQueueService.toggleSavedForLater(work, in: context)
        } label: {
            Label(label.title, systemImage: label.systemImage)
        }
        .tint(.indigo)
    }
}
