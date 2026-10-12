#if os(iOS)
import SwiftUI

/// The reader's floating top chrome: a close button at the leading edge and a
/// title/author pill centred between it and the trailing fan-menu button (whose
/// own 44pt width this reserves so the pill stays visually centred).
struct ReaderChromeTopBar: View {
    let title: String
    let author: String
    /// Hidden while the fan menu is open: the menu replaces its own button and so
    /// expands into this row, which would otherwise truncate the title to a word
    /// or two behind the first menu pill. The close button stays put.
    var titleHidden = false
    let onClose: () -> Void
    /// Opens work details for this book (title pill tap).
    var onOpenDetails: (() -> Void)?

    /// Where every other page's round bar buttons sit: 16pt from the screen's edge,
    /// their top on the safe area's. The reader's own were 12pt in and 8pt lower, so
    /// the back button jumped down and sideways on the way into a work.
    static let edgeInset: CGFloat = 16

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                // The navigation bar's own back mark at its size: the reader's was a
                // third smaller than the one on the page before it.
                Image(systemName: "chevron.backward")
                    .font(.system(size: 21.5, weight: .medium))
                    // Neutral, not the theme tint — Close has no active state to
                    // signal, same reasoning as the fan menu's own controls.
                    .foregroundStyle(Color.primary)
                    .frame(width: 44, height: 44)
                    // A thin chevron is a very small hit target on its own; the
                    // content shape restores the full 44pt circle a .plain button
                    // would otherwise not accept taps across.
                    .contentShape(Circle())
            }
            // .plain so the color above is this view's own explicit choice rather
            // than whatever the ambient button style would impose.
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
        // The host layer adds no inset of its own, and gives the fan button
        // opposite the same one.
        .padding(.horizontal, Self.edgeInset)
    }

    @ViewBuilder
    private var titlePill: some View {
        let content = VStack(spacing: 1) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if !author.isEmpty {
                authorLine
            }
        }
        .padding(.horizontal, 16)
        // As tall as its two lines, and no larger than the first accessibility size: at AX5 a
        // 44pt pill cut the title to "Sodium…" and pushed the author out underneath it. The
        // whole title is one tap away, in the work's details.
        .frame(minHeight: 44)
        .frame(maxWidth: 260)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .glassEffect(.regular, in: .capsule)
        .contentShape(.capsule)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(onOpenDetails == nil ? [] : [.isButton])
        .accessibilityHint(onOpenDetails == nil ? "" : "Opens work details")

        if let onOpenDetails {
            Button(action: onOpenDetails) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    /// Person glyph + author name under the title.
    private var authorLine: some View {
        HStack(spacing: 3) {
            Image(systemName: "person.fill")
                .font(.system(size: 9, weight: .semibold))
                .accessibilityHidden(true)
            Text(author)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(author)
    }
}
#endif
