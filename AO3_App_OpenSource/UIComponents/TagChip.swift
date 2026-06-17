import SwiftUI

/// A small capsule pill for a single tag. Defaults to a neutral, read-only look
/// (AO3 Work Tags); pass `tinted: true` for an accent-filled selected state.
struct TagChip: View {
    let text: String
    var tinted: Bool = false

    var body: some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(tinted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(
                tinted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                in: Capsule()
            )
    }
}
