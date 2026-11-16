import SwiftUI

/// Shared confirmation for a work added to a queue.
struct QueueAddedToast: View {
    let queue: ReadingQueue
    let change: () -> Void
    let undo: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    message
                    actions
                }
            } else {
                HStack(spacing: 10) {
                    message
                    actions
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(.black.opacity(0.86), in: RoundedRectangle(
            cornerRadius: dynamicTypeSize.isAccessibilitySize ? 20 : 100, style: .continuous
        ))
        .overlay {
            RoundedRectangle(cornerRadius: dynamicTypeSize.isAccessibilitySize ? 20 : 100, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var message: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(themeManager.appTheme.carouselQueueTint(hue: queue.displayHue, pickedHex: queue.colorHex))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text("Added to \(queue.displayName)")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            action("Undo", perform: undo)
            action("Change", perform: change)
        }
    }

    private func action(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(title, action: perform)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .background(.white.opacity(0.18), in: Capsule())
            .minimumHitTarget()
    }
}
