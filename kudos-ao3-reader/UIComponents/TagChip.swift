import SwiftUI

/// A small capsule pill for a single tag. Defaults to a neutral, read-only look
/// (AO3 Work Tags); pass `tinted: true` for an accent-filled selected state.
/// `multiline: true` lets a long canonical tag wrap instead of truncating
/// (Work Details' Tags cards, where the full AO3 tag text must stay readable).
struct TagChip: View {
    let text: String
    var tinted: Bool = false
    var multiline: Bool = false
    /// An optional leading glyph naming the tag's category (see
    /// `AO3TagSearch.Field.symbol`). Tags arrive already categorised from AO3's own
    /// markup, so a fandom, a character and a ship are distinguishable at a glance
    /// instead of being one undifferentiated wall of capsules.
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
                    // No color of its own for now — inherits the chip's own
                    // foreground (below) instead of the app's accent tint, so
                    // an untinted chip doesn't read as accent-colored before
                    // per-category tag colors exist. Revisit once those land.
                    // The glyph is decorative — the category is announced by
                    // the caller's accessibility label, not by SF Symbol name.
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.caption)
                .lineLimit(multiline ? nil : 1)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            // `Color.primary`/a concrete gray, not the bare `.primary`/`.quaternary`
            // hierarchical styles: those are defined *relative to the current
            // foreground*, and every one of these chips sits inside a `Button` —
            // which sets that ambient foreground to the app's accent tint. The
            // chip inherited that tint through the hierarchy even though nothing
            // here asked for it, which is what actually painted every "neutral"
            // chip red — a concrete `Color` doesn't participate in that lookup.
            .foregroundStyle(tinted ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary))
            .background(
                tinted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.quaternarySystemFill)),
                in: Capsule()
            )
    }
}
