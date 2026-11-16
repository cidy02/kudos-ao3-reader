import SwiftUI

/// Shared confirmation for a work added to a queue.
struct QueueAddedToast: View {
    let queue: ReadingQueue
    let change: () -> Void

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(themeManager.appTheme.carouselQueueTint(hue: queue.displayHue, pickedHex: queue.colorHex))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text("Added to \(queue.displayName)")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Change", action: change)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.18), in: Capsule())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(.black.opacity(0.86), in: Capsule())
        .accessibilityElement(children: .contain)
    }
}
