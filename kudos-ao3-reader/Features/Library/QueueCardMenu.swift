import SwiftData
import SwiftUI

/// Press-and-hold on a reading queue, wherever its card or row is drawn — Home's
/// Reading Queues carousel and the Queues organizer (owner request, 2026-10-01:
/// queues had no menu where works and collections do). Edit Queue, Pin or Unpin,
/// and Delete: the queue page's "…" items and the organizer's swipes, so a long
/// press never offers less than they do. Saved for Later gets none, as it has no
/// Edit or Delete anywhere.
struct QueueCardMenu: ViewModifier {
    let queue: ReadingQueue
    /// Off while the host is selecting, where a long press would fight the
    /// selection taps.
    var isEnabled = true

    @Environment(\.modelContext) private var context
    @State private var showingEdit = false
    @State private var confirmDelete = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if queue.kind == .custom, isEnabled {
            content
                .contextMenu {
                    Button {
                        showingEdit = true
                    } label: {
                        Label("Edit Queue", systemImage: "pencil")
                    }
                    Button {
                        QueueOrganizerSelection.setPinned([queue], !queue.isPinned, in: context)
                    } label: {
                        Label(queue.isPinned ? "Unpin" : "Pin", systemImage: queue.isPinned ? "pin.slash" : "pin")
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete Queue", systemImage: "trash")
                    }
                }
                .sheet(isPresented: $showingEdit) { EditReadingQueueSheet(queue: queue) }
                .confirmationDialog(
                    QueueOrganizerSelection.deleteTitle([queue]),
                    isPresented: $confirmDelete,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        QueueOrganizerSelection.delete([queue], in: context)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(QueueOrganizerSelection.deleteMessage(count: 1))
                }
        } else {
            content
        }
    }
}
