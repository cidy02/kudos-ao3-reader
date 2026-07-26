#if os(iOS)
import SwiftUI

/// The reader's floating top chrome: a close button at the leading edge and a
/// title/author pill centred between it and the trailing fan-menu button (whose
/// own 44pt width this reserves so the pill stays visually centred).
struct ReaderChromeTopBar: View {
    let title: String
    let author: String
    let tint: Color
    /// Hidden while the fan menu is open: the menu replaces its own button and so
    /// expands into this row, which would otherwise truncate the title to a word
    /// or two behind the first menu pill. The close button stays put.
    var titleHidden = false
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    // A thin chevron is a very small hit target on its own; the
                    // content shape restores the full 44pt circle a .plain button
                    // would otherwise not accept taps across.
                    .contentShape(Circle())
            }
            // .plain so the accent tint above is this view's own explicit choice
            // rather than whatever the ambient button style would impose.
            .buttonStyle(.plain)
            .glassEffect(.regular, in: Circle())
            .accessibilityLabel("Close reader")

            Spacer(minLength: 0)
            if !titleHidden {
                titlePill
            }
            Spacer(minLength: 0)

            // Reserves the fan button's own width so the pill above stays centred
            // between the two edges (the fan button itself floats independently in
            // a layer above this one). Purely a layout placeholder, so it must not
            // absorb the touches meant for that button.
            Color.clear
                .frame(width: 44, height: 44)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 12)
    }

    private var titlePill: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if !author.isEmpty {
                Text(author)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .frame(maxWidth: 260)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}
#endif
