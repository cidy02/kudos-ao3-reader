import SwiftUI

/// `ReadingQueueBrowserView`'s queue list for the iPad/Mac sidebar, and its
/// "New Queue" sheet. The iPhone's bottom switcher bar (All Queues, the queue
/// pill, New Queue) is gone (owner, 2026-10-01): Back reaches the queue list,
/// which switches queues and makes new ones. Split into its own file (not its
/// own type) purely to keep
/// `ReadingQueueBrowser.swift` under this repo's file-length gate; every member
/// here still belongs to `ReadingQueueBrowserView` and reads its `@State`
/// directly, the same as if this were still inline.
extension ReadingQueueBrowserView {
    var newQueueSheet: some View {
        NewReadingQueueSheet(
            name: $newQueueName,
            hue: $newQueueHue,
            onCreate: createQueue,
            onCancel: {
                newQueueName = ""
                newQueueHue = nil
                showingNewQueue = false
            }
        )
    }

    // MARK: - Sidebar rows

    func queueRow(_ queue: ReadingQueue) -> some View {
        let workCount = ReadingQueueService.orderedWorks(in: queue).count
        let isSelected = queue.id == selectedQueue?.id
        return Button { select(queue) } label: {
            HStack(spacing: 10) {
                queueGlyph(queue)
                Text(queue.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(workCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue("\(workCount) work\(workCount == 1 ? "" : "s")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func queueGlyph(_ queue: ReadingQueue?) -> some View {
        if let queue, queue.kind != .savedForLater {
            Circle()
                .fill(themeManager.appTheme.carouselQueueTint(hue: queue.displayHue, pickedHex: queue.colorHex))
                .frame(width: 10, height: 10)
        } else {
            Image(systemName: WorkActionLabels.savedForLaterSymbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
