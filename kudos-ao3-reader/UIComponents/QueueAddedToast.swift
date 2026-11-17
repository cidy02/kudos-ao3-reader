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

    /// Its own view so it reads the dynamic type size where it is drawn (a property on the toast
    /// would read the toast's environment, which a test or a preview never sets).
    var actions: some View { Actions(change: change, undo: undo) }

    static func stacksActions(_ size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }

    struct Actions: View {
        let change: () -> Void
        let undo: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            let layout = QueueAddedToast.stacksActions(dynamicTypeSize)
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(spacing: 6))
            layout {
                action("Undo", perform: undo)
                action("Change", perform: change)
            }
        }

        private func action(_ title: String, perform: @escaping () -> Void) -> some View {
            Button(action: perform) {
                Text(title)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.18), in: Capsule())
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
        }
    }
}
