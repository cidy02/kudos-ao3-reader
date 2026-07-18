import SwiftUI

/// A small capsule pill for a single tag. Defaults to a neutral, read-only look
/// (AO3 Work Tags); pass `tinted: true` for an accent-filled selected state.
/// `multiline: true` lets a long canonical tag wrap instead of truncating
/// (Work Details' Tags cards, where the full AO3 tag text must stay readable).
struct TagChip: View {
    let text: String
    var tinted: Bool = false
    var multiline: Bool = false

    var body: some View {
        Text(text)
            .font(.caption)
            .lineLimit(multiline ? nil : 1)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(tinted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(
                tinted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                in: Capsule()
            )
    }
}
